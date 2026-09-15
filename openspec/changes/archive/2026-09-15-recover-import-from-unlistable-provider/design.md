## Context

`ManagedStoreImporter` enumerates a granted tree URI with `ContentResolver.query` on `DocumentsContract.buildChildDocumentsUriUsingTree`, retrying the root up to `ROOT_QUERY_ATTEMPTS` times because some providers return an empty cursor while still loading. `queryImportEntriesWithRetries` exits as soon as a query reports `loading=false`, unless the root is still empty and attempts remain. When the root ends up empty, `stageTreeIntoManagedStorage` finds `fileCount == 0 && directoryCount == 0` and raises `store_import_no_passwords`.

That logic is correct for the behavior it was built against: the synthetic instrumentation provider returns an empty cursor and then `EXTRA_LOADING=true`, so the retry loop reaches real rows on the third query. A ColorOS device instead returns zero children with `loading=false` on every attempt for a folder that visibly contains `.gpg` entries. The retry loop cannot distinguish that from a genuinely empty folder, and SAF exposes no signal that a provider is withholding rows. AOSP's `FileSystemProvider.queryChildDocuments` has a branch that returns an empty cursor and logs `Queried directory "<id>" is hidden`, which is consistent with the symptom but is emitted by the provider's process and is not observable by the app.

The picker itself succeeds and the root document resolves well enough for `queryDisplayName` to name the destination, so the grant is valid. Only enumeration is empty. Because Import is the primary onboarding path, an affected device cannot bring an existing store onto the phone at all.

## Goals / Non-Goals

**Goals:**

- Keep SAF as the default and only path whenever the provider works; a working provider must see no behavior change.
- Treat a root that enumerates zero children as a recoverable provider fault instead of a successful empty import.
- Offer a direct-filesystem read of the user-selected folder as an explicitly authorized recovery, reusing the existing staging transaction unchanged.
- Keep the recovery read-only, scoped to the selected directory, and subject to the existing safety rejections.
- Explain the failure and the authorization in localized text, and leave the user a clear outcome when they decline.

**Non-Goals:**

- Replacing SAF, or using the direct path for any import that the provider can enumerate.
- Writing, deleting, moving, or modifying anything in shared storage.
- Requesting `MANAGE_EXTERNAL_STORAGE` at startup, during onboarding, or as a precondition for ordinary Import.
- Reading folders the user did not select in the picker during this same flow.
- ZIP/TAR import, changes to Clone, and changes to Rust registration, Git classification, finalize, commit, or rollback.
- Working around providers that have no filesystem identity, such as cloud roots.

## Decisions

### 1. The provider is always attempted first and the fallback is failure-triggered only

Import runs the existing SAF traversal, including loading retries, before anything else. The fallback is reachable only from the specific outcome where the granted **root** enumerates zero children after all attempts. An empty subdirectory below a root that did enumerate is legitimate and must not trigger it, so the trigger is evaluated at depth 0 only, where `queryChildren` already special-cases `rootAttempts`.

Always preferring the direct path when the permission happens to be held was rejected: it would silently route every import around SAF, lose the user-scoped grant model, and mask real provider regressions.

### 2. `stageDirectory` reports a structured provider-fault outcome; Dart owns the decision

Kotlin classifies the empty root and fails with a distinct code (`store_import_provider_unlistable`) instead of `store_import_no_passwords`. The human decision and all user-facing text stay in Dart, matching the established split where platform/Dart import owns staging decisions, Git classification, and cancel/commit/rollback while Kotlin owns the transaction mechanics.

Dart then explains the situation, and only on explicit consent requests authorization and invokes a separate `stageDirectoryDirect` method with the same tree URI. Prompting from Kotlin was rejected because it would duplicate localization and bypass the existing resolver pattern.

### 3. Authorization is `MANAGE_EXTERNAL_STORAGE`, requested contextually

`Environment.isExternalStorageManager()` gates the direct read. When it is false, Dart sends the user to `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` for this package and re-checks on return; it never assumes the grant. Revocation between attempts is handled by re-checking immediately before each direct read rather than caching the result.

`READ_EXTERNAL_STORAGE` and the `READ_MEDIA_*` permissions were rejected because `.gpg` files are not media and are unreadable through them on API 33+. `ACTION_OPEN_DOCUMENT` multi-select was rejected because it loses directory structure, which the store layout depends on.

### 4. The tree URI is the only accepted proof of intent, and only for the external-storage authority

`stageDirectoryDirect` accepts a tree URI, never a caller-supplied path. It resolves a path only when the authority is the platform external-storage provider, because that is the only authority whose document IDs have a documented `<volume>:<relative-path>` filesystem identity. Any other authority, including cloud providers, reports the provider fault as unrecoverable rather than guessing a path.

Resolution splits the document ID on the first `:`, maps the volume via `StorageManager.getStorageVolumes()` (matching the primary volume for `primary`, otherwise the volume UUID), and joins the relative part to the volume directory. The result is canonicalized and must be an existing directory contained within that volume's directory; anything else is rejected. Hand-assembling `/storage/emulated/0` was rejected as unreliable across multi-user and removable volumes.

### 5. The direct read reuses staging and every existing safety rule

The direct path produces the same staging directory, opaque handle, and destination as the SAF path, then hands off to the unchanged finalize/commit/rollback seams. It re-applies the current rejections — unsafe names, duplicates, cycles, path escape, symlinks and other non-regular entries, and maximum depth — against real filesystem entries, and opens files read-only. Git classification continues to run on the staged result, so an OEM that hid `.git` is still surfaced by the existing absent-Git decision.

### 6. Declining is a first-class outcome

If the user declines authorization, the settings round trip returns without the grant, resolution fails, or the direct read also finds nothing, Import reports the localized provider-fault message and leaves no staging behind. The message names the cause and points to Clone, which the prior design already established as the fallback when an Android provider does not expose the tree. Import never reports success in this path.

## Risks / Trade-offs

- **[Risk] `MANAGE_EXTERNAL_STORAGE` is a broad, Play-reviewed permission.** → Declare it with the Play Console justification, keep it unused unless the provider has already failed, request it only at the point of failure, and never make normal Import depend on it. Sideloaded and F-Droid builds are unaffected.
- **[Risk] Bypassing SAF weakens the user-scoped grant model.** → The tree URI from the picker remains the only accepted input, the read is confined to the resolved selected directory, and the fallback cannot run without both a prior provider failure and an explicit grant.
- **[Risk] Path resolution may fail on exotic or emulated volumes.** → Resolution is strictly validated and reports the unrecoverable provider fault on any mismatch rather than reading a guessed location.
- **[Risk] The folder may change between the failed enumeration and the direct read.** → Staging copies a point-in-time snapshot and validates the staged result before any destination is touched, exactly as the SAF path does.
- **[Risk] The grant is held but the folder is still unreadable, for example under `Android/data`.** → Report the same provider-fault outcome with the read error surfaced as non-secret diagnostics instead of an empty success.
- **[Trade-off] Two enumeration implementations must stay behaviorally aligned.** → Keep the traversal rules in shared helpers already covered by JVM tests, and add instrumentation that runs both paths against equivalent trees.

## Migration Plan

1. Add the empty-root classification and the distinct error code, with localized `en`/`zh` strings, so affected devices get an actionable message even before the fallback exists.
2. Add tree-URI-to-path resolution and the authorization check as independently testable helpers.
3. Add `stageDirectoryDirect` and the Dart consent flow, keeping the SAF path untouched.
4. Extend the synthetic provider with an "empty and not loading" root; add instrumentation for provider-first ordering, successful fallback, declined authorization, and unresolvable authorities.
5. Verify on the ColorOS device that Import succeeds through the fallback, and on the emulator that a working provider never triggers it.

Rollback removes the fallback method and the permission declaration; the first step's clearer error remains valid on its own and the SAF path is unchanged throughout.

## Open Questions

- Whether the granted All-files access should be surfaced in Settings with an explanation and a revocation shortcut, or left entirely to system settings.
- Whether a successful fallback import should record that it bypassed the provider, so later support reports can distinguish those stores.
- Whether iOS needs any analogous handling, or whether its document picker has no equivalent failure.
