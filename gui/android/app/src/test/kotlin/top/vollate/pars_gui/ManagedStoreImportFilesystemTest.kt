package top.vollate.pars_gui

import android.provider.DocumentsContract
import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ManagedStoreImportFilesystemTest {
    @Test
    fun `provider-visible dot Git tree is returned unchanged`() {
        val objectEntries =
            (0 until 256).map { index ->
                ImportDocumentEntry(
                    documentId = "root/.git/objects/${index.toString(16)}",
                    displayName = "object-$index",
                    mimeType = "application/octet-stream",
                )
            }
        val entries =
            listOf(
                ImportDocumentEntry(
                    documentId = "root/.git",
                    displayName = ".git",
                    mimeType = DocumentsContract.Document.MIME_TYPE_DIR,
                ),
                ImportDocumentEntry(
                    documentId = "root/.gpg-id",
                    displayName = ".gpg-id",
                    mimeType = "text/plain",
                ),
            ) + objectEntries

        val result =
            queryImportEntriesWithRetries(
                depth = 0,
                rootAttempts = 5,
                maxLoadingAttempts = 40,
                query = { ImportDocumentQueryResult(entries, loading = false) },
                waitBeforeRetry = {},
            )

        assertEquals(entries, result.entries)
        assertEquals(258, result.entries.size)
        assertEquals(".git", safeImportChildName(result.entries.first().displayName))
        assertEquals(".gpg-id", safeImportChildName(result.entries[1].displayName))
    }

    @Test
    fun `empty root and loading provider are retried before copy`() {
        var attempts = 0
        var waits = 0
        val expected =
            ImportDocumentEntry(
                documentId = "root/entry.gpg",
                displayName = "entry.gpg",
                mimeType = "application/octet-stream",
            )

        val result =
            queryImportEntriesWithRetries(
                depth = 0,
                rootAttempts = 5,
                maxLoadingAttempts = 40,
                query = {
                    attempts += 1
                    when (attempts) {
                        1 -> ImportDocumentQueryResult(emptyList(), loading = false)
                        2 -> ImportDocumentQueryResult(emptyList(), loading = true)
                        else -> ImportDocumentQueryResult(listOf(expected), loading = false)
                    }
                },
                waitBeforeRetry = { waits += 1 },
            )

        assertEquals(listOf(expected), result.entries)
        assertEquals(3, result.attempts)
        assertEquals(3, attempts)
        assertEquals(2, waits)
    }

    @Test
    fun `empty root is a provider fault after all retries`() {
        var attempts = 0
        val listing =
            queryImportEntriesWithRetries(
                depth = 0,
                rootAttempts = 5,
                maxLoadingAttempts = 40,
                query = {
                    attempts += 1
                    ImportDocumentQueryResult(emptyList(), loading = false)
                },
                waitBeforeRetry = {},
            )

        var code: String? = null
        try {
            requireListableImportEntries(0, listing)
        } catch (error: StoreImportException) {
            code = error.code
        }
        assertEquals(5, attempts)
        assertEquals("store_import_provider_unlistable", code)
    }

    @Test
    fun `empty subdirectory is a legitimate listing`() {
        val listing = ImportDocumentListing(emptyList(), attempts = 1)

        assertTrue(requireListableImportEntries(1, listing).isEmpty())
    }

    @Test
    fun `direct read requires prior provider failure and current authorization`() {
        requireAuthorizedDirectRead(
            providerFailedForTree = true,
            hasAllFilesAccess = true,
        )
        for (
            state in
                listOf(
                    false to true,
                    true to false,
                )
        ) {
            var rejected = false
            try {
                requireAuthorizedDirectRead(
                    providerFailedForTree = state.first,
                    hasAllFilesAccess = state.second,
                )
            } catch (_: StoreImportException) {
                rejected = true
            }
            assertTrue("expected direct read rejection for $state", rejected)
        }
    }

    @Test
    fun `external storage tree resolver validates authority volume and containment`() {
        val sandbox = Files.createTempDirectory("pars-import-volume").toFile()
        try {
            val primary = File(sandbox, "primary").apply { mkdirs() }
            val selected = File(primary, "password-store").apply { mkdirs() }
            val removable = File(sandbox, "removable").apply { mkdirs() }
            val removableSelected = File(removable, "vault").apply { mkdirs() }
            val volumes =
                listOf(
                    ImportStorageVolume(primary, isPrimary = true, uuid = null),
                    ImportStorageVolume(removable, isPrimary = false, uuid = "ABCD-1234"),
                )

            assertEquals(
                selected.canonicalPath,
                resolveExternalStorageTreeDirectory(
                    EXTERNAL_STORAGE_AUTHORITY,
                    "primary:password-store",
                    volumes,
                ).canonicalPath,
            )
            assertEquals(
                removableSelected.canonicalPath,
                resolveExternalStorageTreeDirectory(
                    EXTERNAL_STORAGE_AUTHORITY,
                    "ABCD-1234:vault",
                    volumes,
                ).canonicalPath,
            )
            for (
                selection in
                    listOf(
                        "example.invalid" to "primary:password-store",
                        EXTERNAL_STORAGE_AUTHORITY to "unknown:password-store",
                        EXTERNAL_STORAGE_AUTHORITY to "primary:../outside",
                        EXTERNAL_STORAGE_AUTHORITY to "primary:missing",
                    )
            ) {
                var errorCode: String? = null
                try {
                    resolveExternalStorageTreeDirectory(
                        selection.first,
                        selection.second,
                        volumes,
                    )
                } catch (error: StoreImportException) {
                    errorCode = error.code
                }
                assertEquals(
                    "expected provider-fault rejection for $selection",
                    "store_import_provider_unlistable",
                    errorCode,
                )
            }
        } finally {
            sandbox.deleteRecursively()
        }
    }

    @Test
    fun `direct copy preserves source and rejects symbolic links`() {
        val sandbox = Files.createTempDirectory("pars-import-direct").toFile()
        try {
            val source = File(sandbox, "source").apply { mkdirs() }
            val destination = File(sandbox, "destination").apply { mkdirs() }
            File(source, ".gpg-id").writeText("KEY\n")
            File(source, "folder").mkdir()
            File(source, "folder/login.gpg").writeText("ciphertext")
            val sourceDigest =
                source.walkTopDown().associate { it.relativeTo(source).path to it.lastModified() }

            val stats = copyDirectStoreTree(source, destination)

            assertEquals(2, stats.fileCount)
            assertEquals(1, stats.directoryCount)
            assertEquals(1, stats.passwordCount)
            assertEquals("ciphertext", File(destination, "folder/login.gpg").readText())
            assertEquals(
                sourceDigest,
                source.walkTopDown().associate { it.relativeTo(source).path to it.lastModified() },
            )

            val linkedSource = File(sandbox, "linked-source").apply { mkdirs() }
            Files.createSymbolicLink(
                File(linkedSource, "link").toPath(),
                File(source, ".gpg-id").toPath(),
            )
            val linkedDestination = File(sandbox, "linked-destination").apply { mkdirs() }
            var rejected = false
            try {
                copyDirectStoreTree(linkedSource, linkedDestination)
            } catch (_: IOException) {
                rejected = true
            }
            assertTrue(rejected)
        } finally {
            sandbox.deleteRecursively()
        }
    }

    @Test
    fun `cancelling known stage removes entire synthetic Git tree`() {
        val filesRoot = Files.createTempDirectory("pars-import-test").toFile()
        try {
            val staging = File(filesRoot, ".import-fixture")
            val gitObjects = File(staging, ".git/objects/ab")
            assertTrue(gitObjects.mkdirs())
            File(staging, ".gpg-id").writeText("ABC\n")
            File(gitObjects, "object").writeBytes(byteArrayOf(1, 2, 3))
            val known = mutableSetOf(staging.canonicalPath)

            cancelKnownStagedImport(staging.path, known, filesRoot)

            assertFalse(staging.exists())
            assertTrue(known.isEmpty())
        } finally {
            filesRoot.deleteRecursively()
        }
    }

    @Test
    fun `opaque handle is bound to its staged source and exact destination`() {
        val filesRoot = Files.createTempDirectory("pars-import-test").toFile()
        val outside = Files.createTempDirectory("pars-import-outside").toFile()
        try {
            val staging = File(filesRoot, "stores/.import-fixture")
            val destination = File(filesRoot, "stores/vault")
            assertTrue(staging.mkdirs())
            val record = StagedImportRecord("known", staging, destination)
            assertEquals(
                destination.canonicalPath,
                requireStagedImportRecord(
                    "known",
                    mapOf("known" to record),
                    filesRoot,
                ).destination.canonicalPath,
            )
            var unknownRejected = false
            try {
                requireStagedImportRecord("other", mapOf("known" to record), filesRoot)
            } catch (_: SecurityException) {
                unknownRejected = true
            }
            assertTrue(unknownRejected)
            var mismatchedDestinationRejected = false
            try {
                requireStagedImportRecord(
                    "bad",
                    mapOf("bad" to StagedImportRecord("bad", staging, File(outside, "vault"))),
                    filesRoot,
                )
            } catch (_: SecurityException) {
                mismatchedDestinationRejected = true
            }
            assertTrue(mismatchedDestinationRejected)
        } finally {
            filesRoot.deleteRecursively()
            outside.deleteRecursively()
        }
    }

    @Test
    fun `committed cleanup failure can never restore obsolete backup`() {
        val filesRoot = Files.createTempDirectory("pars-import-test").toFile()
        try {
            val staging = File(filesRoot, "stores/.import-fixture").apply { mkdirs() }
            val destination = File(filesRoot, "stores/vault").apply {
                mkdirs()
                resolve("marker").writeText("new")
            }
            val backup = File(filesRoot, "stores/.import-backup").apply {
                mkdirs()
                resolve("marker").writeText("old")
            }
            val record =
                StagedImportRecord(
                    handle = "known",
                    staging = staging,
                    destination = destination,
                    backup = backup,
                    installed = true,
                )

            assertFalse(commitStagedImportRecord(record) { false })
            assertTrue(record.committed)
            disposeCommittedImportRecord(record)

            assertEquals("new", File(destination, "marker").readText())
            assertFalse(backup.exists())
        } finally {
            filesRoot.deleteRecursively()
        }
    }

    @Test
    fun `unknown stage and unsafe child names are rejected`() {
        val filesRoot = Files.createTempDirectory("pars-import-test").toFile()
        try {
            val staging = File(filesRoot, ".import-unknown")
            assertTrue(staging.mkdirs())
            var rejected = false
            try {
                cancelKnownStagedImport(staging.path, mutableSetOf(), filesRoot)
            } catch (_: SecurityException) {
                rejected = true
            }
            assertTrue(rejected)

            for (name in listOf("", ".", "..", "a/b", "a\\b")) {
                var unsafe = false
                try {
                    safeImportChildName(name)
                } catch (_: IOException) {
                    unsafe = true
                }
                assertTrue("expected unsafe name: $name", unsafe)
            }
        } finally {
            filesRoot.deleteRecursively()
        }
    }
}
