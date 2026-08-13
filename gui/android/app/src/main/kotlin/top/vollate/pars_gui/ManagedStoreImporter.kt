package top.vollate.pars_gui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.provider.DocumentsContract
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ForkJoinPool
import java.util.concurrent.ForkJoinTask
import java.util.concurrent.RecursiveAction
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Copies an Android document tree into app-private storage before Rust opens it as a path. */
internal class ManagedStoreImporter(
    private val activity: FlutterFragmentActivity,
) {
    private val importExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val copyPool = ForkJoinPool(COPY_PARALLELISM)
    private val directoryPicker: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(
            ActivityResultContracts.StartActivityForResult(),
        ) { pickerResult ->
            handleDirectoryPickerResult(pickerResult.resultCode, pickerResult.data)
        }
    private var activeResult: MethodChannel.Result? = null
    private var pickerDestinationBaseDirectory: String? = null

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> startDirectoryPicker(call, result)
            "copyDirectory" -> startDirectoryCopy(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startDirectoryPicker(call: MethodCall, result: MethodChannel.Result) {
        if (activeResult != null) {
            result.error("store_import_busy", "Another store import is already in progress.", null)
            return
        }
        val destination = call.argument<String>("destinationBaseDirectory")?.trim()
        if (destination.isNullOrEmpty()) {
            result.error(
                "invalid_destination",
                "The managed store destination directory is missing.",
                null,
            )
            return
        }

        activeResult = result
        pickerDestinationBaseDirectory = destination
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        try {
            Log.i(TAG, "Launching managed-store directory picker")
            directoryPicker.launch(intent)
        } catch (error: Exception) {
            activeResult = null
            pickerDestinationBaseDirectory = null
            result.error("store_picker_failed", error.message, null)
        }
    }

    private fun startDirectoryCopy(call: MethodCall, result: MethodChannel.Result) {
        if (activeResult != null) {
            result.error("store_import_busy", "Another store import is already in progress.", null)
            return
        }
        val destination = call.argument<String>("destinationBaseDirectory")?.trim()
        val treeUriValue = call.argument<String>("treeUri")?.trim()
        val policyValue = call.argument<String>("existingStorePolicy")?.trim()
        if (destination.isNullOrEmpty() || treeUriValue.isNullOrEmpty()) {
            result.error(
                "invalid_import_selection",
                "The selected directory or managed destination is missing.",
                null,
            )
            return
        }
        val policy =
            when (policyValue) {
                "replace" -> ExistingStorePolicy.REPLACE
                "merge" -> ExistingStorePolicy.MERGE
                else -> {
                    result.error(
                        "invalid_conflict_policy",
                        "The managed store conflict policy is invalid.",
                        null,
                    )
                    return
                }
            }

        activeResult = result
        Log.i(TAG, "Copying selected document tree into app storage")
        importExecutor.execute {
            try {
                val importedPath =
                    copyTreeIntoManagedStorage(Uri.parse(treeUriValue), destination, policy)
                activity.runOnUiThread {
                    Log.i(TAG, "Managed-store copy completed at $importedPath")
                    completeWithSuccess(result, importedPath)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    Log.e(TAG, "Managed-store copy failed", error)
                    completeWithError(result, error)
                }
            }
        }
    }

    private fun handleDirectoryPickerResult(resultCode: Int, data: Intent?) {
        Log.i(
            TAG,
            "Managed-store directory picker returned resultCode=$resultCode uri=${data?.data}",
        )
        val result = activeResult
        if (result == null) {
            Log.w(TAG, "Ignoring directory picker result because no import is active")
            return
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            completeWithSuccess(result, null)
            return
        }

        val treeUri = data.data!!
        val destination = pickerDestinationBaseDirectory
        if (destination == null) {
            completeWithError(
                result,
                IllegalStateException("The managed store destination was lost."),
            )
            return
        }
        val takeFlags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (takeFlags != 0) {
            try {
                activity.contentResolver.takePersistableUriPermission(treeUri, takeFlags)
            } catch (_: SecurityException) {
                // The transient activity grant is sufficient for the copy below.
            }
        }

        try {
            val destinationDirectory = managedDestination(treeUri, destination)
            if (destinationDirectory.exists() && !destinationDirectory.isDirectory) {
                throw IOException(
                    "The managed store destination is not a directory: '${destinationDirectory.path}'.",
                )
            }
            completeWithSuccess(
                result,
                mapOf(
                    "treeUri" to treeUri.toString(),
                    "destinationPath" to destinationDirectory.canonicalPath,
                    "destinationExists" to destinationDirectory.exists(),
                ),
            )
        } catch (error: Exception) {
            completeWithError(result, error)
        }
    }

    private fun completeWithSuccess(result: MethodChannel.Result, value: Any?) {
        if (activeResult !== result) {
            return
        }
        activeResult = null
        pickerDestinationBaseDirectory = null
        result.success(value)
    }

    private fun completeWithError(result: MethodChannel.Result, error: Exception) {
        if (activeResult !== result) {
            return
        }
        activeResult = null
        pickerDestinationBaseDirectory = null
        val code =
            if (error is StoreImportException) error.code else "store_import_failed"
        result.error(code, error.message ?: error.toString(), null)
    }

    fun dispose() {
        activeResult?.error(
            "activity_destroyed",
            "Store import stopped because the Android activity was closed.",
            null,
        )
        activeResult = null
        pickerDestinationBaseDirectory = null
        directoryPicker.unregister()
        importExecutor.shutdownNow()
        copyPool.shutdownNow()
    }

    private fun managedDestination(treeUri: Uri, destinationBase: String): File {
        val baseDirectory = File(destinationBase).canonicalFile
        val filesDirectory = activity.filesDir.canonicalFile
        if (!isWithin(filesDirectory, baseDirectory)) {
            throw SecurityException(
                "Refusing to import outside app storage: '${baseDirectory.path}'.",
            )
        }
        if (!baseDirectory.exists() && !baseDirectory.mkdirs()) {
            throw IOException("Failed to create app storage directory '${baseDirectory.path}'.")
        }
        if (!baseDirectory.isDirectory) {
            throw IOException("App storage destination is not a directory: '${baseDirectory.path}'.")
        }

        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocumentId)
        val sourceName = queryDisplayName(rootUri) ?: "store"
        return File(baseDirectory, slugPathSegment(sourceName))
    }

    private fun copyTreeIntoManagedStorage(
        treeUri: Uri,
        destinationBase: String,
        existingStorePolicy: ExistingStorePolicy,
    ): String {
        val startedAt = SystemClock.elapsedRealtime()
        val destinationDirectory = managedDestination(treeUri, destinationBase)
        val baseDirectory = destinationDirectory.parentFile
            ?: throw IOException("Managed store destination has no parent directory.")
        if (destinationDirectory.exists() && !destinationDirectory.isDirectory) {
            throw IOException(
                "The managed store destination is not a directory: '${destinationDirectory.path}'.",
            )
        }

        val stagingDirectory = File(baseDirectory, ".import-${UUID.randomUUID()}")
        val backupDirectory = File(baseDirectory, ".import-backup-${UUID.randomUUID()}")
        if (!stagingDirectory.mkdir()) {
            throw IOException("Failed to create import staging directory '${stagingDirectory.path}'.")
        }
        try {
            val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val copyStats = CopyStats()
            if (
                existingStorePolicy == ExistingStorePolicy.MERGE &&
                destinationDirectory.exists()
            ) {
                copyExistingTree(destinationDirectory, stagingDirectory, 0)
            }
            copyDocumentTree(
                treeUri,
                rootDocumentId,
                stagingDirectory,
                copyStats,
            )

            if (copyStats.fileCount == 0 && copyStats.directoryCount == 0) {
                Log.w(
                    TAG,
                    "Import enumerated no files or directories from $treeUri; " +
                        "destination was not changed",
                )
                throw StoreImportException(
                    code = "store_import_no_passwords",
                    message = "No passwords were found in the selected folder.",
                )
            }

            replaceDestination(
                stagingDirectory = stagingDirectory,
                destinationDirectory = destinationDirectory,
                backupDirectory = backupDirectory,
            )
            Log.i(
                TAG,
                "Copied ${copyStats.fileCount} files, ${copyStats.directoryCount} directories, " +
                    "and ${copyStats.passwordCount} passwords from $treeUri in " +
                    "${SystemClock.elapsedRealtime() - startedAt} ms using " +
                    "$COPY_PARALLELISM workers",
            )
            return destinationDirectory.canonicalPath
        } finally {
            if (stagingDirectory.exists()) {
                stagingDirectory.deleteRecursively()
            }
            if (backupDirectory.exists() && destinationDirectory.exists()) {
                backupDirectory.deleteRecursively()
            }
        }
    }

    private fun copyExistingTree(source: File, destination: File, depth: Int) {
        if (depth > MAX_TREE_DEPTH) {
            throw IOException("Existing managed store exceeds the maximum directory depth.")
        }
        val sourceCanonical = source.canonicalFile
        val children = source.listFiles()
            ?: throw IOException("Failed to list existing managed directory '${source.path}'.")
        for (child in children) {
            val childCanonical = child.canonicalFile
            if (
                child.absoluteFile.path != childCanonical.path ||
                !isWithin(sourceCanonical, childCanonical)
            ) {
                throw IOException(
                    "Existing managed store contains an unsupported link '${child.path}'.",
                )
            }
            val target = File(destination, child.name)
            if (child.isDirectory) {
                if (!target.mkdir()) {
                    throw IOException("Failed to stage existing directory '${target.path}'.")
                }
                copyExistingTree(child, target, depth + 1)
            } else if (child.isFile) {
                child.inputStream().use { input ->
                    FileOutputStream(target).use { output -> input.copyTo(output) }
                }
            } else {
                throw IOException(
                    "Existing managed store contains an unsupported file '${child.path}'.",
                )
            }
        }
    }

    private fun replaceDestination(
        stagingDirectory: File,
        destinationDirectory: File,
        backupDirectory: File,
    ) {
        val hadDestination = destinationDirectory.exists()
        if (hadDestination && !destinationDirectory.renameTo(backupDirectory)) {
            throw IOException(
                "Failed to prepare the existing managed store '${destinationDirectory.path}' for replacement.",
            )
        }

        if (stagingDirectory.renameTo(destinationDirectory)) {
            return
        }

        if (hadDestination && !destinationDirectory.exists()) {
            backupDirectory.renameTo(destinationDirectory)
        }
        throw IOException(
            "Failed to finalize imported store at '${destinationDirectory.path}'.",
        )
    }

    private fun copyDocumentTree(
        treeUri: Uri,
        rootDocumentId: String,
        destination: File,
        copyStats: CopyStats,
    ) {
        val copyError = AtomicReference<Exception?>(null)
        val visitedDirectories = ConcurrentHashMap.newKeySet<String>()
        copyPool.invoke(
            directoryCopyTask(
                treeUri = treeUri,
                parentDocumentId = rootDocumentId,
                destination = destination,
                visitedDirectories = visitedDirectories,
                depth = 0,
                copyStats = copyStats,
                copyError = copyError,
            ),
        )
        copyError.get()?.let { throw it }
    }

    private fun directoryCopyTask(
        treeUri: Uri,
        parentDocumentId: String,
        destination: File,
        visitedDirectories: MutableSet<String>,
        depth: Int,
        copyStats: CopyStats,
        copyError: AtomicReference<Exception?>,
    ): RecursiveAction =
        object : RecursiveAction() {
            override fun compute() {
                runCopyTask(copyError) {
                    copyDirectoryContents(
                        treeUri,
                        parentDocumentId,
                        destination,
                        visitedDirectories,
                        depth,
                        copyStats,
                        copyError,
                    )
                }
            }
        }

    private fun copyDirectoryContents(
        treeUri: Uri,
        parentDocumentId: String,
        destination: File,
        visitedDirectories: MutableSet<String>,
        depth: Int,
        copyStats: CopyStats,
        copyError: AtomicReference<Exception?>,
    ) {
        if (depth > MAX_TREE_DEPTH) {
            throw IOException("Selected store exceeds the maximum directory depth.")
        }
        if (!visitedDirectories.add(parentDocumentId)) {
            throw IOException("Selected store contains a directory cycle at '$parentDocumentId'.")
        }

        val entries = queryChildren(treeUri, parentDocumentId, depth)
        val childNames = mutableSetOf<String>()
        val childTasks = mutableListOf<RecursiveAction>()

        for (entry in entries) {
            val safeName = safeChildName(entry.displayName)
            if (!childNames.add(safeName)) {
                throw IOException(
                    "Selected store contains duplicate entries named '$safeName' in " +
                        "'$parentDocumentId'.",
                )
            }
            val target = File(destination, safeName)
            if (entry.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                if (target.exists() && !target.isDirectory) {
                    throw IOException(
                        "Imported directory conflicts with an existing file '${target.path}'.",
                    )
                }
                if (!target.exists() && !target.mkdir()) {
                    throw IOException("Failed to create imported directory '${target.path}'.")
                }
                copyStats.recordDirectory()
                childTasks += directoryCopyTask(
                    treeUri = treeUri,
                    parentDocumentId = entry.documentId,
                    destination = target,
                    visitedDirectories = visitedDirectories,
                    depth = depth + 1,
                    copyStats = copyStats,
                    copyError = copyError,
                )
                continue
            }

            childTasks +=
                object : RecursiveAction() {
                    override fun compute() {
                        runCopyTask(copyError) {
                            copyDocumentFile(treeUri, entry, safeName, target, copyStats)
                        }
                    }
                }
        }

        if (copyError.get() == null) {
            ForkJoinTask.invokeAll(childTasks)
        }
    }

    private fun copyDocumentFile(
        treeUri: Uri,
        entry: DocumentEntry,
        safeName: String,
        target: File,
        copyStats: CopyStats,
    ) {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, entry.documentId)
        val input =
            activity.contentResolver.openInputStream(documentUri)
                ?: throw IOException(
                    "Failed to open selected file '${entry.displayName}' ($documentUri).",
                )
        input.use { source ->
            FileOutputStream(target).use { output -> source.copyTo(output, COPY_BUFFER_BYTES) }
        }
        copyStats.recordFile(safeName.lowercase(Locale.ROOT).endsWith(".gpg"))
    }

    private fun runCopyTask(
        copyError: AtomicReference<Exception?>,
        action: () -> Unit,
    ) {
        if (copyError.get() != null) {
            return
        }
        try {
            action()
        } catch (error: Exception) {
            copyError.compareAndSet(null, error)
        }
    }

    /**
     * Some OEM DocumentsProviders return an empty cursor while a large folder is still loading.
     * DocumentsUI re-queries those cursors; a one-shot client must do the same or it silently
     * imports an empty directory.
     */
    private fun queryChildren(
        treeUri: Uri,
        parentDocumentId: String,
        depth: Int,
    ): List<DocumentEntry> {
        val treeChildrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        var attempt = 0
        while (true) {
            attempt += 1
            val treeQuery = queryDocumentEntries(treeChildrenUri, parentDocumentId)
            val entries = treeQuery.entries
            val loading = treeQuery.loading
            Log.i(
                TAG,
                "Listed ${entries.size} children for $parentDocumentId " +
                    "(attempt=$attempt loading=$loading uri=$treeChildrenUri)",
            )

            val retryInitialEmptyRoot = depth == 0 && entries.isEmpty() && attempt < ROOT_QUERY_ATTEMPTS
            if (!loading && !retryInitialEmptyRoot) {
                return entries
            }
            if (attempt >= MAX_LOADING_QUERY_ATTEMPTS) {
                throw IOException(
                    "Android did not finish listing selected folder '$parentDocumentId' " +
                        "after $attempt attempts ($treeChildrenUri).",
                )
            }
            try {
                Thread.sleep(QUERY_RETRY_DELAY_MS)
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                throw IOException("Store import was interrupted while listing '$parentDocumentId'.", error)
            }
        }
    }

    private fun queryDocumentEntries(
        childrenUri: Uri,
        parentDocumentId: String,
    ): DocumentQueryResult {
        val entries = mutableListOf<DocumentEntry>()
        var loading = false
        val cursor =
            activity.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            ) ?: throw IOException("Failed to list selected folder '$parentDocumentId'.")
        cursor.use {
            loading =
                it.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
            while (it.moveToNext()) {
                entries +=
                    DocumentEntry(
                        documentId = it.getString(0),
                        displayName = it.getString(1),
                        mimeType = it.getString(2),
                    )
            }
        }
        return DocumentQueryResult(entries = entries, loading = loading)
    }

    private fun queryDisplayName(documentUri: Uri): String? {
        val cursor =
            activity.contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            ) ?: return null
        cursor.use {
            return if (it.moveToFirst()) it.getString(0) else null
        }
    }

    private fun safeChildName(name: String): String {
        if (
            name.isBlank() ||
            name == "." ||
            name == ".." ||
            name.indexOf('/') >= 0 ||
            name.indexOf('\\') >= 0 ||
            name.indexOf('\u0000') >= 0
        ) {
            throw IOException("Selected store contains an invalid file name: '$name'.")
        }
        return name
    }

    private fun slugPathSegment(value: String): String {
        val slug =
            value
                .trim()
                .lowercase(Locale.ROOT)
                .replace(Regex("[^a-z0-9._-]+"), "-")
                .trim('-')
        return slug.ifEmpty { "store" }
    }

    private fun isWithin(parent: File, child: File): Boolean {
        return child.path == parent.path || child.path.startsWith(parent.path + File.separator)
    }

    private data class DocumentEntry(
        val documentId: String,
        val displayName: String,
        val mimeType: String,
    )

    private data class DocumentQueryResult(
        val entries: List<DocumentEntry>,
        val loading: Boolean,
    )

    private class CopyStats {
        private val files = AtomicInteger()
        private val directories = AtomicInteger()
        private val passwords = AtomicInteger()

        val fileCount: Int get() = files.get()
        val directoryCount: Int get() = directories.get()
        val passwordCount: Int get() = passwords.get()

        fun recordDirectory() {
            directories.incrementAndGet()
        }

        fun recordFile(isPassword: Boolean) {
            files.incrementAndGet()
            if (isPassword) {
                passwords.incrementAndGet()
            }
        }
    }

    private class StoreImportException(
        val code: String,
        message: String,
    ) : IOException(message)

    private enum class ExistingStorePolicy {
        REPLACE,
        MERGE,
    }

    companion object {
        const val CHANNEL_NAME = "top.vollate.pars_gui/store_import"
        private const val TAG = "ParsStoreImport"
        private const val COPY_PARALLELISM = 4
        private const val MAX_TREE_DEPTH = 128
        private const val ROOT_QUERY_ATTEMPTS = 5
        private const val MAX_LOADING_QUERY_ATTEMPTS = 40
        private const val QUERY_RETRY_DELAY_MS = 250L
        private const val COPY_BUFFER_BYTES = 16 * 1024
    }
}
