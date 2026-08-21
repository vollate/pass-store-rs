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

        assertEquals(entries, result)
        assertEquals(258, result.size)
        assertEquals(".git", safeImportChildName(result.first().displayName))
        assertEquals(".gpg-id", safeImportChildName(result[1].displayName))
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

        assertEquals(listOf(expected), result)
        assertEquals(3, attempts)
        assertEquals(2, waits)
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
