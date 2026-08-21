package top.vollate.pars_gui

import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ManagedStoreImporterInstrumentedTest {
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var activity: MainActivity
    private lateinit var importer: ManagedStoreImporter
    private lateinit var testRoot: File
    private val grantedTreeUris = mutableMapOf<String, Uri>()

    @Before
    fun setUp() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { launched ->
            activity = launched
            importer = launched.managedStoreImporter
            testRoot = File(launched.filesDir, "instrumented-import-${UUID.randomUUID()}")
            assertTrue(testRoot.mkdirs())
        }
    }

    @After
    fun tearDown() {
        if (::testRoot.isInitialized) testRoot.deleteRecursively()
        if (::scenario.isInitialized) scenario.close()
    }

    @Test
    fun providerTraversalStagesNestedGitAndCommitRemovesBackup() {
        val digestBefore = resetProvider(SyntheticStoreDocumentsProvider.FULL_ROOT)
        val destination = File(testRoot, "synthetic-vault")
        assertTrue(destination.mkdirs())
        File(destination, "old-marker").writeText("old")
        val unrelated = File(activity.filesDir, "instrumentation-unrelated-${UUID.randomUUID()}")
        assertTrue(unrelated.mkdirs())
        File(unrelated, "keep").writeText("keep")
        try {
            val staged = stage(SyntheticStoreDocumentsProvider.FULL_ROOT)
            val handle = staged.getValue("handle")
            val staging = File(staged.getValue("stagingPath"))
            assertTrue(handle.isNotBlank())
            assertFalse(handle.contains(File.separator))
            assertNotEquals(staging.canonicalPath, handle)
            assertEquals(destination.canonicalPath, staged.getValue("destinationPath"))
            assertTrue(staging.isDirectory)
            assertEquals("SYNTHETIC-RECIPIENT\n", File(staging, ".gpg-id").readText())
            assertEquals("ref: refs/heads/main\n", File(staging, ".git/HEAD").readText())
            assertTrue(File(staging, ".git/config").readText().contains("synthetic.git"))
            assertTrue(File(staging, ".git/refs/heads/main").isFile)
            val objects =
                File(staging, ".git/objects")
                    .walkTopDown()
                    .filter(File::isFile)
                    .toList()
            assertEquals(SyntheticStoreDocumentsProvider.OBJECT_COUNT + 3, objects.size)
            assertTrue(File(staging, "folder/nested.gpg").isFile)

            val finalized =
                call(
                    "finalizeStagedDirectory",
                    mapOf(
                        "handle" to handle,
                        // The production contract accepts only the opaque handle. Extra untrusted
                        // destination data cannot redirect installation.
                        "destinationPath" to unrelated.path,
                    ),
                )
            assertNull(finalized.code)
            assertEquals(destination.canonicalPath, finalized.value)
            assertEquals(
                SyntheticStoreDocumentsProvider.OBJECT_COUNT + 3,
                File(destination, ".git/objects")
                    .walkTopDown()
                    .count(File::isFile),
            )
            assertEquals("keep", File(unrelated, "keep").readText())
            assertEquals(1, backupDirectories().size)

            val committed = call("commitStagedDirectory", mapOf("handle" to handle))
            assertNull(committed.code)
            assertTrue(backupDirectories().isEmpty())
            assertTrue(stagingDirectories().isEmpty())
            assertFalse(File(destination, "old-marker").exists())
            exportVerificationTree(destination, "verification-import-valid")

            val stats = providerStats(SyntheticStoreDocumentsProvider.FULL_ROOT)
            assertTrue(stats.rootAttempts >= 3)
            assertTrue(stats.openCalls >= 260)
            assertEquals(0, stats.mutationCalls)
            assertEquals(digestBefore, stats.digest)
        } finally {
            unrelated.deleteRecursively()
        }
    }

    @Test
    fun finalizedImportRollbackRestoresPreviousDestination() {
        resetProvider(SyntheticStoreDocumentsProvider.FULL_ROOT)
        val destination = File(testRoot, "synthetic-vault")
        assertTrue(destination.mkdirs())
        File(destination, "old-marker").writeText("old")

        val staged = stage(SyntheticStoreDocumentsProvider.FULL_ROOT)
        val handle = staged.getValue("handle")
        assertNull(call("finalizeStagedDirectory", mapOf("handle" to handle)).code)
        assertFalse(File(destination, "old-marker").exists())
        assertTrue(File(destination, ".git").isDirectory)
        assertEquals(1, backupDirectories().size)

        val rolledBack = call("rollbackStagedDirectory", mapOf("handle" to handle))
        assertNull(rolledBack.code)
        assertEquals("old", File(destination, "old-marker").readText())
        assertFalse(File(destination, ".git").exists())
        assertTrue(backupDirectories().isEmpty())
        assertTrue(stagingDirectories().isEmpty())
    }

    @Test
    fun absentGitIsStagedForDartDecisionAndCancelRemovesOnlyStage() {
        val digestBefore = resetProvider(SyntheticStoreDocumentsProvider.LOCAL_ROOT)
        val staged = stage(SyntheticStoreDocumentsProvider.LOCAL_ROOT)
        val handle = staged.getValue("handle")
        val staging = File(staged.getValue("stagingPath"))
        val destination = File(staged.getValue("destinationPath"))

        assertTrue(File(staging, ".gpg-id").isFile)
        assertTrue(File(staging, "login.gpg").isFile)
        assertFalse(File(staging, ".git").exists())
        assertFalse(destination.exists())
        val cancelled = call("cancelStagedDirectory", mapOf("handle" to handle))
        assertNull(cancelled.code)
        assertFalse(staging.exists())
        assertFalse(destination.exists())
        assertTrue(stagingDirectories().isEmpty())

        val continued = stage(SyntheticStoreDocumentsProvider.LOCAL_ROOT)
        val continuedHandle = continued.getValue("handle")
        val continuedDestination = File(continued.getValue("destinationPath"))
        assertNull(
            call("finalizeStagedDirectory", mapOf("handle" to continuedHandle)).code,
        )
        assertNull(call("commitStagedDirectory", mapOf("handle" to continuedHandle)).code)
        assertTrue(continuedDestination.isDirectory)
        assertFalse(File(continuedDestination, ".git").exists())
        exportVerificationTree(continuedDestination, "verification-import-local")

        assertEquals(
            digestBefore,
            providerStats(SyntheticStoreDocumentsProvider.LOCAL_ROOT).digest,
        )
    }

    @Test
    fun invalidGitStageIsCancelledWithoutReplacingDestination() {
        resetProvider(SyntheticStoreDocumentsProvider.INVALID_GIT_ROOT)
        val destination = File(testRoot, "invalid-git-vault")
        assertTrue(destination.mkdirs())
        File(destination, "old-marker").writeText("old")

        val staged = stage(SyntheticStoreDocumentsProvider.INVALID_GIT_ROOT)
        val handle = staged.getValue("handle")
        val staging = File(staged.getValue("stagingPath"))
        assertEquals("not-a-valid-head\n", File(staging, ".git/HEAD").readText())
        exportVerificationTree(staging, "verification-import-invalid")

        val cancelled = call("cancelStagedDirectory", mapOf("handle" to handle))
        assertNull(cancelled.code)
        assertFalse(staging.exists())
        assertEquals("old", File(destination, "old-marker").readText())
        assertFalse(File(destination, ".git").exists())
    }

    @Test
    fun unknownOutsideAndUnsafeTransactionsFailClosed() {
        resetProvider(SyntheticStoreDocumentsProvider.LOCAL_ROOT)
        val unknown = call("finalizeStagedDirectory", mapOf("handle" to "unknown"))
        assertNotNull(unknown.code)

        val outsideBase = File(activity.filesDir.parentFile, "outside-${UUID.randomUUID()}")
        val outside =
            call(
                "stageDirectory",
                mapOf(
                    "destinationBaseDirectory" to outsideBase.path,
                    "treeUri" to treeUri(SyntheticStoreDocumentsProvider.LOCAL_ROOT).toString(),
                ),
            )
        assertNotNull(outside.code)
        assertFalse(outsideBase.exists())

        for (root in listOf(SyntheticStoreDocumentsProvider.UNSAFE_ROOT, SyntheticStoreDocumentsProvider.CYCLE_ROOT)) {
            resetProvider(root)
            val failed =
                call(
                    "stageDirectory",
                    mapOf(
                        "destinationBaseDirectory" to testRoot.path,
                        "treeUri" to treeUri(root).toString(),
                    ),
                )
            assertNotNull("expected provider tree to fail: $root", failed.code)
            assertTrue("stage leaked for $root", stagingDirectories().isEmpty())
            assertFalse(File(testRoot.parentFile, "escape").exists())
            val stats = providerStats(root)
            assertEquals(0, stats.mutationCalls)
        }
    }

    private fun stage(rootId: String): Map<String, String> {
        val result =
            call(
                "stageDirectory",
                mapOf(
                    "destinationBaseDirectory" to testRoot.path,
                    "treeUri" to treeUri(rootId).toString(),
                ),
            )
        assertNull("${result.code}: ${result.message}", result.code)
        @Suppress("UNCHECKED_CAST")
        return (result.value as Map<*, *>).entries.associate { (key, value) ->
            key as String to value as String
        }
    }

    private fun call(method: String, arguments: Map<String, Any?>): CapturedResult {
        val result = CapturedResult()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            importer.handleMethodCall(MethodCall(method, arguments), result)
        }
        assertTrue("$method timed out", result.await())
        return result
    }

    private fun resetProvider(rootId: String): String {
        treeUri(rootId)
        return providerStats(rootId).digest
    }

    private fun providerStats(rootId: String): ProviderStats {
        val uri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri(rootId),
            "$rootId/${SyntheticStoreDocumentsProvider.STATS_DOCUMENT}",
        )
        val value =
            requireNotNull(activity.contentResolver.openInputStream(uri))
                .bufferedReader()
                .use { it.readText() }
        val parts = value.split('|', limit = 4)
        return ProviderStats(
            rootAttempts = parts[0].toInt(),
            openCalls = parts[1].toInt(),
            mutationCalls = parts[2].toInt(),
            digest = parts[3],
        )
    }

    private data class ProviderStats(
        val rootAttempts: Int,
        val openCalls: Int,
        val mutationCalls: Int,
        val digest: String,
    )

    private fun treeUri(rootId: String): Uri =
        grantedTreeUris.getOrPut(rootId) { pickSyntheticTree(rootId) }

    private fun pickSyntheticTree(rootId: String): Uri {
        val result = CapturedResult()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            importer.handleMethodCall(
                MethodCall(
                    "pickDirectory",
                    mapOf(
                        "destinationBaseDirectory" to testRoot.path,
                        "initialUri" to DocumentsContract.buildDocumentUri(
                            SyntheticStoreDocumentsProvider.AUTHORITY,
                            rootId,
                        ).toString(),
                    ),
                ),
                result,
            )
        }
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        assertTrue(
            "DocumentsUI did not open",
            device.wait(Until.hasObject(By.pkg("com.google.android.documentsui")), 15_000),
        )
        val title =
            when (rootId) {
                SyntheticStoreDocumentsProvider.FULL_ROOT -> "Synthetic Vault"
                SyntheticStoreDocumentsProvider.LOCAL_ROOT -> "Local Vault"
                SyntheticStoreDocumentsProvider.INVALID_GIT_ROOT -> "Invalid Git Vault"
                SyntheticStoreDocumentsProvider.UNSAFE_ROOT -> "Unsafe Vault"
                SyntheticStoreDocumentsProvider.CYCLE_ROOT -> "Cycle Vault"
                else -> error("unknown synthetic root")
            }
        requireNotNull(device.wait(Until.findObject(By.text(title)), 10_000)) {
            "DocumentsUI did not open the requested synthetic root: $title"
        }
        val select = device.wait(Until.findObject(By.res("android", "button1")), 10_000)
        requireNotNull(select) { "DocumentsUI select action is unavailable" }
        require(select.isEnabled) { "DocumentsUI rejected the synthetic provider root" }
        select.click()
        if (device.wait(
                Until.hasObject(By.res("com.google.android.documentsui", "alertTitle")),
                3_000,
            )
        ) {
            requireNotNull(
                device.wait(Until.findObject(By.res("android", "button1")), 2_000),
            ) { "DocumentsUI grant confirmation is unavailable" }.click()
        }
        assertTrue("pickDirectory timed out", result.await())
        assertNull("${result.code}: ${result.message}", result.code)
        val selection = result.value as Map<*, *>
        return Uri.parse(requireNotNull(selection["treeUri"] as? String))
    }

    private fun exportVerificationTree(source: File, name: String) {
        val destination = File(activity.filesDir, name)
        destination.deleteRecursively()
        assertTrue(source.copyRecursively(destination, overwrite = true))
    }

    private fun stagingDirectories(): List<File> =
        testRoot.listFiles()?.filter { it.name.startsWith(".import-") && !it.name.startsWith(".import-backup-") }
            .orEmpty()

    private fun backupDirectories(): List<File> =
        testRoot.listFiles()?.filter { it.name.startsWith(".import-backup-") }.orEmpty()

    private class CapturedResult : MethodChannel.Result {
        private val latch = CountDownLatch(1)

        @Volatile
        var value: Any? = null
            private set

        @Volatile
        var code: String? = null
            private set

        @Volatile
        var message: String? = null
            private set

        override fun success(result: Any?) {
            value = result
            latch.countDown()
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            code = errorCode
            message = errorMessage
            latch.countDown()
        }

        override fun notImplemented() {
            code = "not_implemented"
            latch.countDown()
        }

        fun await(): Boolean = latch.await(90, TimeUnit.SECONDS)
    }
}
