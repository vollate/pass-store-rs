package top.vollate.pars_gui.autofill

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ParsAutofillStateStoreInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val index = File(context.filesDir, "instrumented-autofill-index.json")
    private val store = File(context.filesDir, "stores/instrumented-autofill")

    @After
    fun cleanup() {
        ParsAutofillStateStore.clear(context)
        index.delete()
        store.deleteRecursively()
    }

    @Test
    fun explicitPublicationEnablesAndClearLeavesFailClosedTombstone() {
        store.mkdirs()
        index.writeText(
            """{
              "version":2,
              "store_id":"instrumented-store",
              "store_name":"Instrumented",
              "store_root":"${store.absolutePath}",
              "generated_at_epoch_seconds":0,
              "entries":[{
                "path":"example.com/alice",
                "display_name":"example.com",
                "service_name":"example.com",
                "username":"alice",
                "path_website":"example.com",
                "enriched_websites":[],
                "is_favorite":false,
                "autofill_rank":null,
                "updated_at_epoch_seconds":0
              }]
            }""".trimIndent(),
        )

        assertTrue(
            ParsAutofillStateStore.publish(
                context = context,
                configPath = File(context.filesDir, "pars_config.toml").absolutePath,
                indexPath = index.absolutePath,
                storeRoot = store.absolutePath,
                passphrase = "synthetic-passphrase",
            ),
        )
        val published = ParsAutofillStateStore.read(context)
        assertTrue(published.enabled)
        assertEquals(store.absolutePath, published.storeRoot)
        assertEquals("synthetic-passphrase", published.passphrase)
        assertFalse(published.generation.isNullOrBlank())
        assertTrue(ParsAutofillStateStore.canServe(published, index.exists()))

        assertTrue(ParsAutofillStateStore.clear(context))
        val cleared = ParsAutofillStateStore.read(context)
        assertFalse(cleared.enabled)
        assertNull(cleared.storeRoot)
        assertNull(cleared.passphrase)
        assertFalse(ParsAutofillStateStore.canServe(cleared, index.exists()))
        assertTrue(index.exists())
        assertTrue(
            ParsAutofillNativeBridge.queryCandidates(
                context = context,
                website = "example.com",
                appName = null,
                query = null,
                limit = 10,
            ).isEmpty(),
        )
    }

    @Test
    fun tombstoneDuringResolutionRejectsCredentialAndReplacementGetsNewGeneration() {
        store.mkdirs()
        index.writeText("{}")
        assertTrue(
            ParsAutofillStateStore.publish(
                context,
                "/config",
                index.absolutePath,
                store.absolutePath,
                "synthetic",
            ),
        )
        val first = ParsAutofillStateStore.read(context)
        val generation = requireNotNull(first.generation)
        var reads = 0
        val credential =
            ParsAutofillNativeBridge.resolveCredentialWith(
                path = "example.com/alice",
                generation = generation,
                stateReader = {
                    if (reads++ == 0) {
                        first
                    } else {
                        ParsAutofillStateStore.clear(context)
                        ParsAutofillStateStore.read(context)
                    }
                },
                nativeResolve = {
                    """{"error":null,"credential":{"path":"example.com/alice","username":"alice","password":"synthetic"}}"""
                },
            )
        assertNull(credential)

        index.writeText("{}")
        assertTrue(ParsAutofillStateStore.publish(context, "/config", index.path, store.path, null))
        val replacement = ParsAutofillStateStore.read(context)
        assertTrue(replacement.enabled)
        assertTrue(replacement.generation != generation)
    }

    @Test
    fun publicationFailsClosedWithoutStoreOrIndex() {
        assertFalse(
            ParsAutofillStateStore.publish(
                context = context,
                configPath = null,
                indexPath = index.absolutePath,
                storeRoot = store.absolutePath,
                passphrase = "synthetic-passphrase",
            ),
        )
        val state = ParsAutofillStateStore.read(context)
        assertFalse(state.enabled)
        assertNull(state.storeRoot)
        assertNull(state.passphrase)
    }
}
