package top.vollate.pars_gui

import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class OpenableFilePickerTest {
    @Test
    fun `primary external document keeps the selected path and file name`() {
        val uri =
            "content://com.android.externalstorage.documents/document/primary%3ADownload%2Fgh_vollate"
        val location =
            userSelectedOpenableLocation(
                uri = uri,
                displayName = "gh_vollate",
                primaryStorageRoot = "/storage/emulated/0",
            )

        assertEquals("/storage/emulated/0/Download/gh_vollate", location)
        assertEquals("gh_vollate", selectedOpenableFileName(location, "gh_vollate"))
    }

    @Test
    fun `downloads raw document keeps the selected path`() {
        val uri =
            "content://com.android.providers.downloads.documents/document/raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2Fgh_vollate"

        assertEquals(
            "/storage/emulated/0/Download/gh_vollate",
            userSelectedOpenableLocation(
                uri = uri,
                displayName = "gh_vollate",
                primaryStorageRoot = "/storage/emulated/0",
            ),
        )
    }

    @Test
    fun `unknown provider falls back to the file name`() {
        assertEquals(
            "gh_vollate",
            userSelectedOpenableLocation(
                uri = "content://com.example.documents/document/42",
                displayName = "gh_vollate",
                primaryStorageRoot = "/storage/emulated/0",
            ),
        )
    }

    @Test
    fun `read returns text and does not accept a huge file`() {
        val text = readOpenableText(ByteArrayInputStream("ssh-ed25519 AAAA".toByteArray(StandardCharsets.UTF_8)))
        assertEquals("ssh-ed25519 AAAA", text)

        val huge = ByteArray(MAX_OPENABLE_KEY_BYTES + 1) { 'a'.code.toByte() }
        assertThrows(java.io.IOException::class.java) {
            readOpenableText(ByteArrayInputStream(huge))
        }
    }
}
