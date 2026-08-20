package top.vollate.pars_gui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ParsClipboardOwnershipTest {
    @Test
    fun `older same-value lease cannot clear a newer Pars copy`() {
        assertFalse(
            parsClipboardMatches(
                currentText = "same-secret",
                currentLabel = parsClipboardLabel("new-token"),
                expectedText = "same-secret",
                ownerToken = "old-token",
            ),
        )
    }

    @Test
    fun `external identical text is not owned by Pars`() {
        assertFalse(
            parsClipboardMatches(
                currentText = "same-secret",
                currentLabel = "Another app",
                expectedText = "same-secret",
                ownerToken = "pars-token",
            ),
        )
    }

    @Test
    fun `matching text and owner token can be cleared`() {
        assertTrue(
            parsClipboardMatches(
                currentText = "secret",
                currentLabel = parsClipboardLabel("pars-token"),
                expectedText = "secret",
                ownerToken = "pars-token",
            ),
        )
    }
}
