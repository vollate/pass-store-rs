package top.vollate.pars_gui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URI
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

internal const val MAX_OPENABLE_KEY_BYTES = 1024 * 1024

private const val EXTERNAL_DOCUMENT_AUTHORITY = "com.android.externalstorage.documents"
private const val DOWNLOADS_DOCUMENT_AUTHORITY = "com.android.providers.downloads.documents"

/**
 * Opens a document and returns the location the user selected.
 *
 * The selection is not copied. Bytes are read from the returned URI only when
 * import is confirmed.
 */
internal class OpenableFilePicker(
    private val activity: FlutterFragmentActivity,
) {
    private var activeResult: MethodChannel.Result? = null
    private val picker =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { pickerResult ->
            handlePickerResult(pickerResult.resultCode, pickerResult.data)
        }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> startPicker(call, result)
            "read" -> readSelectedFile(call, result)
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        activeResult?.error(
            "activity_destroyed",
            "File selection stopped because the Android activity was closed.",
            null,
        )
        activeResult = null
    }

    private fun startPicker(call: MethodCall, result: MethodChannel.Result) {
        if (activeResult != null) {
            result.error("openable_file_busy", "Another file selection is already in progress.", null)
            return
        }
        activeResult = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
                call.argument<String>("initialDirectory")
                    ?.trim()
                    ?.takeIf { it.startsWith("content://") }
                    ?.let { putExtra("android.provider.extra.INITIAL_URI", Uri.parse(it)) }
            }
        try {
            picker.launch(intent)
        } catch (error: Exception) {
            activeResult = null
            result.error("openable_file_picker_failed", error.message, null)
        }
    }

    private fun handlePickerResult(resultCode: Int, data: Intent?) {
        val result = activeResult ?: return
        if (resultCode != Activity.RESULT_OK) {
            complete(result, null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            complete(result, null)
            return
        }
        try {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Some providers only grant a temporary read for this selection.
            }
            val displayName = queryDisplayName(uri)
            val location =
                userSelectedOpenableLocation(
                    uri = uri.toString(),
                    displayName = displayName,
                    primaryStorageRoot = Environment.getExternalStorageDirectory().path,
                )
            val fileName = selectedOpenableFileName(location, displayName)
            complete(
                result,
                mapOf(
                    "uri" to uri.toString(),
                    "location" to location,
                    "fileName" to fileName,
                ),
            )
        } catch (error: Exception) {
            fail(result, error)
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index < 0) return null
            return cursor.getString(index)
        }
        return null
    }

    private fun readSelectedFile(call: MethodCall, result: MethodChannel.Result) {
        val uriValue = call.argument<String>("uri")?.trim()
        if (uriValue.isNullOrEmpty()) {
            result.error("invalid_selection", "The selected file is missing.", null)
            return
        }
        try {
            val text =
                activity.contentResolver.openInputStream(Uri.parse(uriValue))?.use { stream ->
                    readOpenableText(stream)
                } ?: throw java.io.IOException("The selected file could not be read.")
            result.success(text)
        } catch (error: Exception) {
            result.error("openable_file_read_failed", error.message, null)
        }
    }

    private fun complete(result: MethodChannel.Result, value: Any?) {
        if (activeResult !== result) return
        activeResult = null
        result.success(value)
    }

    private fun fail(result: MethodChannel.Result, error: Exception) {
        if (activeResult !== result) return
        activeResult = null
        result.error("openable_file_picker_failed", error.message, null)
    }
}

internal fun userSelectedOpenableLocation(
    uri: String,
    displayName: String?,
    primaryStorageRoot: String,
): String {
    resolvedDocumentPath(uri, primaryStorageRoot)?.let { return it }
    singleFileName(displayName)?.let { return it }
    throw IllegalArgumentException("The selected file has no location.")
}

internal fun selectedOpenableFileName(location: String, displayName: String?): String {
    singleFileName(displayName)?.let { return it }
    return singleFileName(location)
        ?: throw IllegalArgumentException("The selected file has no name.")
}

internal fun readOpenableText(stream: InputStream): String {
    val buffer = ByteArrayOutputStream()
    val chunk = ByteArray(8192)
    var total = 0
    while (true) {
        val read = stream.read(chunk)
        if (read < 0) break
        total += read
        if (total > MAX_OPENABLE_KEY_BYTES) {
            throw java.io.IOException("The selected file is too large to import as an SSH private key.")
        }
        buffer.write(chunk, 0, read)
    }
    return try {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(buffer.toByteArray()))
            .toString()
    } catch (_: CharacterCodingException) {
        throw java.io.IOException("The selected file is not a text SSH private key.")
    }
}

private fun resolvedDocumentPath(uri: String, primaryStorageRoot: String): String? {
    val parsed =
        try {
            URI(uri)
        } catch (_: Exception) {
            return null
        }
    if (parsed.scheme != "content") return null
    val documentId = documentId(parsed) ?: return null
    val authority = parsed.authority
    if (authority == EXTERNAL_DOCUMENT_AUTHORITY && documentId.startsWith("primary:")) {
        val relative = documentId.removePrefix("primary:").trim().trimStart('/')
        if (!isDisplayRelativePath(relative)) return null
        return primaryStorageRoot.trimEnd('/') + "/" + relative
    }
    if (authority == DOWNLOADS_DOCUMENT_AUTHORITY && documentId.startsWith("raw:")) {
        val rawPath = documentId.removePrefix("raw:").trim()
        if (rawPath.startsWith("/") && isDisplayRelativePath(rawPath.trimStart('/'))) {
            return rawPath
        }
    }
    return null
}

private fun documentId(uri: URI): String? {
    val rawPath = uri.rawPath ?: return null
    val marker = "/document/"
    val index = rawPath.indexOf(marker)
    if (index < 0) return null
    return try {
        URLDecoder.decode(rawPath.substring(index + marker.length), StandardCharsets.UTF_8)
    } catch (_: Exception) {
        null
    }
}

private fun isDisplayRelativePath(relative: String): Boolean {
    if (relative.isEmpty()) return false
    return relative.split('/').none { it.isEmpty() || it == "." || it == ".." }
}

private fun singleFileName(value: String?): String? {
    val trimmed = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val name = trimmed.substringAfterLast('/').substringAfterLast('\\').trim()
    if (name.isEmpty() || name == "." || name == ".." || name.contains('/') || name.contains('\\')) {
        return null
    }
    return name
}
