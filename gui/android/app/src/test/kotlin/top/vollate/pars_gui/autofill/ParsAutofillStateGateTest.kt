package top.vollate.pars_gui.autofill

import java.nio.file.Files
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ParsAutofillStateGateTest {
    @Test
    fun disabledTombstoneRejectsLeftoverIndex() {
        val state =
            ParsAutofillState(
                enabled = false,
                configPath = "/config",
                indexPath = "/leftover-index",
                storeRoot = "/old-store",
                passphrase = "must-not-be-used",
                generation = null,
            )

        assertFalse(ParsAutofillStateStore.canServe(state, indexExists = true))
    }

    @Test
    fun tombstoneDuringCredentialResolutionReturnsNothing() {
        val directory = Files.createTempDirectory("pars-autofill-gate").toFile()
        try {
            val index = directory.resolve("index.json").apply { writeText("{}") }
            val enabled =
                ParsAutofillState(
                    enabled = true,
                    configPath = "/config",
                    indexPath = index.path,
                    storeRoot = "/store",
                    passphrase = "synthetic",
                    generation = "generation-a",
                )
            val disabled = enabled.copy(enabled = false, storeRoot = null, generation = null)
            assertNull(disabled.generation)
            assertFalse(ParsAutofillStateStore.samePublication(enabled, disabled))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun publicationRequiresExplicitEnabledStateAndValidIndex() {
        val enabled =
            ParsAutofillState(
                enabled = true,
                configPath = "/config",
                indexPath = "/index",
                storeRoot = "/store",
                passphrase = null,
                generation = "generation-a",
            )
        val missingRoot = enabled.copy(storeRoot = null)

        assertTrue(ParsAutofillStateStore.canServe(enabled, indexExists = true))
        assertFalse(ParsAutofillStateStore.canServe(enabled, indexExists = false))
        assertFalse(ParsAutofillStateStore.canServe(missingRoot, indexExists = true))
    }

    @Test
    fun completionHistoryRequiresCurrentPublicationAndTreatsNativeFailureAsBestEffort() {
        val directory = Files.createTempDirectory("pars-autofill-completion").toFile()
        try {
            val index = directory.resolve("index.json").apply { writeText("{}") }
            val state =
                ParsAutofillState(
                    enabled = true,
                    configPath = "/config",
                    indexPath = index.path,
                    storeRoot = "/store",
                    passphrase = null,
                    generation = "generation-a",
                )
            var nativeCalled = false
            assertTrue(
                ParsAutofillNativeBridge.recordCompletionWith(
                    path = "example.com/alice",
                    generation = "generation-a",
                    stateReader = { state },
                    nativeRecord = {
                        nativeCalled = true
                        """{"recorded":true,"error":null}"""
                    },
                ),
            )
            assertTrue(nativeCalled)

            nativeCalled = false
            assertFalse(
                ParsAutofillNativeBridge.recordCompletionWith(
                    path = "example.com/alice",
                    generation = "stale-generation",
                    stateReader = { state },
                    nativeRecord = {
                        nativeCalled = true
                        """{"recorded":true,"error":null}"""
                    },
                ),
            )
            assertFalse(nativeCalled)

            assertFalse(
                ParsAutofillNativeBridge.recordCompletionWith(
                    path = "example.com/alice",
                    generation = "generation-a",
                    stateReader = { state },
                    nativeRecord = { """{"recorded":false,"error":{"message":"write failed"}}""" },
                ),
            )
        } finally {
            directory.deleteRecursively()
        }
    }
}
