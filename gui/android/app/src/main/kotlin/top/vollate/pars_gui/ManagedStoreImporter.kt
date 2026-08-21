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

internal data class ImportDocumentEntry(
    val documentId: String,
    val displayName: String,
    val mimeType: String,
)

internal data class ImportDocumentQueryResult(
    val entries: List<ImportDocumentEntry>,
    val loading: Boolean,
)

internal data class StagedImportRecord(
    val handle: String,
    val staging: File,
    val destination: File,
    var backup: File? = null,
    var installed: Boolean = false,
    var committed: Boolean = false,
)

internal fun commitStagedImportRecord(
    record: StagedImportRecord,
    deleteBackup: (File) -> Boolean = { it.deleteRecursively() },
): Boolean {
    record.committed = true
    val backup = record.backup
    if (backup != null && backup.exists() && !deleteBackup(backup)) return false
    return backup?.exists() != true
}

internal fun disposeCommittedImportRecord(
    record: StagedImportRecord,
    deleteBackup: (File) -> Boolean = { it.deleteRecursively() },
) {
    if (!record.committed) return
    record.backup?.takeIf(File::exists)?.let(deleteBackup)
    record.staging.takeIf(File::exists)?.deleteRecursively()
}

internal fun queryImportEntriesWithRetries(
    depth: Int,
    rootAttempts: Int,
    maxLoadingAttempts: Int,
    query: (attempt: Int) -> ImportDocumentQueryResult,
    waitBeforeRetry: () -> Unit,
): List<ImportDocumentEntry> {
    var attempt = 0
    while (true) {
        attempt += 1
        val result = query(attempt)
        val retryInitialEmptyRoot =
            depth == 0 && result.entries.isEmpty() && attempt < rootAttempts
        if (!result.loading && !retryInitialEmptyRoot) return result.entries
        if (attempt >= maxLoadingAttempts) {
            throw IOException("Android did not finish listing the selected folder after $attempt attempts.")
        }
        waitBeforeRetry()
    }
}

internal fun safeImportChildName(name: String): String {
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

internal fun requireStagedImportRecord(
    handle: String,
    stagedImports: Map<String, StagedImportRecord>,
    filesDirectory: File,
): StagedImportRecord {
    val record = stagedImports[handle] ?: throw SecurityException("Refusing an unknown staged import.")
    val root = filesDirectory.canonicalFile
    fun within(file: File): Boolean {
        val canonical = file.canonicalFile
        return canonical.path == root.path || canonical.path.startsWith(root.path + File.separator)
    }
    if (
        !within(record.staging) ||
        !within(record.destination) ||
        record.destination.canonicalFile == root ||
        !record.staging.name.startsWith(".import-")
    ) {
        throw SecurityException("Refusing an unknown staged import.")
    }
    return record
}

internal fun cancelKnownStagedImport(
    stagingPath: String,
    stagedImports: MutableSet<String>,
    filesDirectory: File,
) {
    val staging = File(stagingPath).canonicalFile
    val root = filesDirectory.canonicalFile
    val within = staging.path == root.path || staging.path.startsWith(root.path + File.separator)
    if (
        !stagedImports.contains(staging.path) ||
        !within ||
        !staging.name.startsWith(".import-") ||
        !staging.isDirectory
    ) {
        throw SecurityException("Refusing an unknown staged import.")
    }
    if (!staging.deleteRecursively()) {
        throw IOException("Failed to remove staged import.")
    }
    stagedImports.remove(staging.path)
}

/** Copies an Android document tree into app-private storage before Rust opens it as a path. */
internal class ManagedStoreImporter(
    private val activity: FlutterFragmentActivity,
) {
    private val importExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val copyPool = ForkJoinPool(COPY_PARALLELISM)
    private val stagedImports = ConcurrentHashMap<String, StagedImportRecord>()
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
            "stageDirectory" -> startDirectoryStage(call, result)
            "finalizeStagedDirectory" -> finalizeStagedDirectory(call, result)
            "commitStagedDirectory" -> commitStagedDirectory(call, result)
            "rollbackStagedDirectory" -> rollbackStagedDirectory(call, result)
            "cancelStagedDirectory" -> cancelStagedDirectory(call, result)
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
            call.argument<String>("initialUri")
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(it)) }
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

    private fun startDirectoryStage(call: MethodCall, result: MethodChannel.Result) {
        if (activeResult != null) {
            result.error("store_import_busy", "Another store import is already in progress.", null)
            return
        }
        val destination = call.argument<String>("destinationBaseDirectory")?.trim()
        val treeUriValue = call.argument<String>("treeUri")?.trim()
        if (destination.isNullOrEmpty() || treeUriValue.isNullOrEmpty()) {
            result.error(
                "invalid_import_selection",
                "The selected directory or managed destination is missing.",
                null,
            )
            return
        }
        activeResult = result
        Log.i(TAG, "Copying selected document tree into app storage")
        importExecutor.execute {
            try {
                val staged = stageTreeIntoManagedStorage(Uri.parse(treeUriValue), destination)
                activity.runOnUiThread {
                    Log.i(TAG, "Managed-store staging completed")
                    completeWithSuccess(result, staged)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    Log.e(TAG, "Managed-store copy failed", error)
                    completeWithError(result, error)
                }
            }
        }
    }

    private fun finalizeStagedDirectory(call: MethodCall, result: MethodChannel.Result) {
        if (activeResult != null) {
            result.error("store_import_busy", "Another store import is already in progress.", null)
            return
        }
        val handle = call.argument<String>("handle")?.trim()
        if (handle.isNullOrEmpty()) {
            result.error("invalid_import_stage", "The staged import is missing.", null)
            return
        }
        activeResult = result
        importExecutor.execute {
            try {
                val finalized = finalizeStagedImport(handle)
                activity.runOnUiThread { completeWithSuccess(result, finalized) }
            } catch (error: Exception) {
                activity.runOnUiThread { completeWithError(result, error) }
            }
        }
    }

    private fun commitStagedDirectory(call: MethodCall, result: MethodChannel.Result) {
        finishTransaction(call, result, commit = true)
    }

    private fun rollbackStagedDirectory(call: MethodCall, result: MethodChannel.Result) {
        finishTransaction(call, result, commit = false)
    }

    private fun finishTransaction(call: MethodCall, result: MethodChannel.Result, commit: Boolean) {
        val handle = call.argument<String>("handle")?.trim()
        if (handle.isNullOrEmpty()) {
            result.error("invalid_import_stage", "The staged import is missing.", null)
            return
        }
        try {
            if (commit) commitStagedImport(handle) else rollbackStagedImport(handle)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                if (commit) "store_import_cleanup_failed" else "store_import_rollback_failed",
                if (commit) "Imported store backup cleanup failed." else "Previous store restoration failed.",
                null,
            )
        }
    }

    private fun cancelStagedDirectory(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<String>("handle")?.trim()
        if (handle.isNullOrEmpty()) {
            result.error("invalid_import_stage", "The staged import is missing.", null)
            return
        }
        try {
            cancelStagedImport(handle)
            result.success(null)
        } catch (error: Exception) {
            result.error("store_import_cancel_failed", "Staged import cleanup failed.", null)
        }
    }

    private fun handleDirectoryPickerResult(resultCode: Int, data: Intent?) {
        Log.i(TAG, "Managed-store directory picker returned resultCode=$resultCode")
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
        val message =
            if (error is StoreImportException) error.message else "Password-store import failed."
        result.error(code, message, null)
    }

    fun dispose() {
        activeResult?.error(
            "activity_destroyed",
            "Store import stopped because the Android activity was closed.",
            null,
        )
        activeResult = null
        pickerDestinationBaseDirectory = null
        stagedImports.values.toList().forEach { record ->
            if (record.committed) {
                // Registration is irreversible. Cleanup may retry, but dispose must
                // never restore an obsolete backup over the active store.
                disposeCommittedImportRecord(record)
            } else if (record.installed) {
                try {
                    rollbackRecord(record)
                } catch (_: Exception) {
                    // Leave the backup for the next bounded cleanup attempt.
                }
            } else {
                record.staging.deleteRecursively()
            }
        }
        stagedImports.clear()
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

    private fun stageTreeIntoManagedStorage(
        treeUri: Uri,
        destinationBase: String,
    ): Map<String, String> {
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
        if (!stagingDirectory.mkdir()) {
            throw IOException("Failed to create import staging directory '${stagingDirectory.path}'.")
        }
        try {
            val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val copyStats = CopyStats()
            copyDocumentTree(treeUri, rootDocumentId, stagingDirectory, copyStats)
            if (copyStats.fileCount == 0 && copyStats.directoryCount == 0) {
                throw StoreImportException(
                    code = "store_import_no_passwords",
                    message = "No passwords were found in the selected folder.",
                )
            }
            val handle = UUID.randomUUID().toString()
            val record =
                StagedImportRecord(
                    handle = handle,
                    staging = stagingDirectory.canonicalFile,
                    destination = destinationDirectory.canonicalFile,
                )
            stagedImports[handle] = record
            Log.i(
                TAG,
                "Staged ${copyStats.fileCount} files, ${copyStats.directoryCount} directories, " +
                    "and ${copyStats.passwordCount} passwords in " +
                    "${SystemClock.elapsedRealtime() - startedAt} ms",
            )
            return mapOf(
                "handle" to handle,
                "stagingPath" to record.staging.path,
                "destinationPath" to record.destination.path,
            )
        } catch (error: Exception) {
            stagingDirectory.deleteRecursively()
            throw error
        }
    }

    private fun validatedRecord(handle: String): StagedImportRecord =
        requireStagedImportRecord(handle, stagedImports, activity.filesDir)

    private fun finalizeStagedImport(handle: String): String {
        val record = validatedRecord(handle)
        if (record.installed || !record.staging.isDirectory) {
            throw SecurityException("Refusing an invalid staged import state.")
        }
        val backup = File(record.destination.parentFile, ".import-backup-${UUID.randomUUID()}")
        record.backup = backup
        try {
            replaceDestination(record.staging, record.destination, backup)
            record.installed = true
            return record.destination.canonicalPath
        } catch (error: Exception) {
            restoreBackup(record.destination, backup)
            throw error
        }
    }

    private fun commitStagedImport(handle: String) {
        val record = validatedRecord(handle)
        if (!record.installed) throw SecurityException("Import is not finalized.")
        if (!commitStagedImportRecord(record)) {
            throw IOException("Failed to remove import backup.")
        }
        stagedImports.remove(handle)
    }

    private fun rollbackStagedImport(handle: String) {
        val record = validatedRecord(handle)
        if (record.committed) {
            throw SecurityException("Committed import cannot be rolled back.")
        }
        if (record.installed) rollbackRecord(record) else if (!record.staging.deleteRecursively()) {
            throw IOException("Failed to remove staged import.")
        }
        stagedImports.remove(handle)
    }

    private fun cancelStagedImport(handle: String) {
        val record = validatedRecord(handle)
        if (record.installed) throw SecurityException("Finalized import requires rollback.")
        if (!record.staging.isDirectory || !record.staging.deleteRecursively()) {
            throw IOException("Failed to remove staged import.")
        }
        stagedImports.remove(handle)
    }

    private fun rollbackRecord(record: StagedImportRecord) {
        if (record.destination.exists() && !record.destination.deleteRecursively()) {
            throw IOException("Failed to remove imported destination during rollback.")
        }
        val backup = record.backup
        if (backup != null && backup.exists()) {
            if (!backup.renameTo(record.destination) || !record.destination.exists()) {
                throw IOException("Failed to restore previous store.")
            }
        }
        record.installed = false
    }

    private fun restoreBackup(destination: File, backup: File) {
        if (destination.exists() && !destination.deleteRecursively()) {
            throw IOException("Failed to remove incomplete destination.")
        }
        if (backup.exists() && (!backup.renameTo(destination) || !destination.exists())) {
            throw IOException("Failed to restore previous store.")
        }
    }

    private fun replaceDestination(
        stagingDirectory: File,
        destinationDirectory: File,
        backupDirectory: File,
    ) {
        val hadDestination = destinationDirectory.exists()
        if (hadDestination && !destinationDirectory.renameTo(backupDirectory)) {
            throw IOException("Failed to prepare the existing managed store for replacement.")
        }

        if (stagingDirectory.renameTo(destinationDirectory)) return

        if (hadDestination && !destinationDirectory.exists()) {
            if (!backupDirectory.renameTo(destinationDirectory) || !destinationDirectory.exists()) {
                throw IOException("Failed to restore the existing managed store.")
            }
        }
        throw IOException("Failed to finalize the imported store.")
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
            val safeName = safeImportChildName(entry.displayName)
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
        entry: ImportDocumentEntry,
        safeName: String,
        target: File,
        copyStats: CopyStats,
    ) {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, entry.documentId)
        val input =
            activity.contentResolver.openInputStream(documentUri)
                ?: throw IOException("Failed to open a selected file.")
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
    ): List<ImportDocumentEntry> {
        val treeChildrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        return queryImportEntriesWithRetries(
            depth = depth,
            rootAttempts = ROOT_QUERY_ATTEMPTS,
            maxLoadingAttempts = MAX_LOADING_QUERY_ATTEMPTS,
            query = { attempt ->
                val treeQuery = queryDocumentEntries(treeChildrenUri, parentDocumentId)
                Log.i(
                    TAG,
                    "Listed ${treeQuery.entries.size} children " +
                        "(attempt=$attempt loading=${treeQuery.loading})",
                )
                treeQuery
            },
            waitBeforeRetry = {
                try {
                    Thread.sleep(QUERY_RETRY_DELAY_MS)
                } catch (error: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw IOException("Store import was interrupted while listing.", error)
                }
            },
        )
    }

    private fun queryDocumentEntries(
        childrenUri: Uri,
        parentDocumentId: String,
    ): ImportDocumentQueryResult {
        val entries = mutableListOf<ImportDocumentEntry>()
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
            ) ?: throw IOException("Failed to list the selected folder.")
        cursor.use {
            loading =
                it.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
            while (it.moveToNext()) {
                entries +=
                    ImportDocumentEntry(
                        documentId = it.getString(0),
                        displayName = it.getString(1),
                        mimeType = it.getString(2),
                    )
            }
        }
        return ImportDocumentQueryResult(entries = entries, loading = loading)
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
