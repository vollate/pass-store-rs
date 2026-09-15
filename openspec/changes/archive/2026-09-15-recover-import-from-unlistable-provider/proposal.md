## Why

On a ColorOS device, Import of a normal internal-storage folder containing `.gpg` entries fails with "No passwords were found." The `DocumentsProvider` returns an empty child cursor for the granted tree root with `EXTRA_LOADING=false` and never yields rows, so the importer stages nothing and reports an empty store.

The existing root-retry mitigation was designed and verified only against a provider that returns an empty cursor and then announces `EXTRA_LOADING=true`, reaching real rows on the third query. A provider that reports "finished loading, zero children" for a folder the user can plainly see defeats it. This exact exposure was recorded as an accepted residual risk of `2026-09-15-adopt-single-store-and-optional-git` ("OEM-specific DocumentsUI implementations are covered by lower-level safety/retry tests, while UI automation ran on the Android 16 Google emulator") and has now been hit on a real device. Import is the primary onboarding path, so an affected device currently has no way to bring an existing store onto the phone.

## What Changes

- Keep the Storage Access Framework as the only enumeration path that runs by default. The provider is always attempted first, including the existing loading-retry behavior; nothing about a working provider changes.
- Distinguish "the provider exposed an empty tree" from "the user selected an empty folder". A root that enumerates zero children is treated as a provider fault to be recovered from, not as a successful import of an empty store.
- Add an explicitly user-authorized direct-filesystem fallback used **only** after the provider enumerates zero children at the root. It resolves the selected tree to a real filesystem path, reads the store with ordinary file APIs, and stages it through the unchanged staging/finalize/commit/rollback transaction.
- Gate the fallback on `MANAGE_EXTERNAL_STORAGE` ("All files access"), requested contextually at the moment of failure with a plain explanation, never at startup and never as a precondition for normal Import.
- Report an actionable provider-fault outcome with a distinct error code and localized `en`/`zh` strings when the fallback is declined, unavailable, or also finds nothing. The current flat "No passwords were found." is replaced for this case.
- Confine the fallback to reading the user-selected directory. It never writes to, deletes from, or moves anything in shared storage, and it stays subject to the existing link, cycle, path-escape, duplicate-name, and unsafe-entry rejections.

## Capabilities

### New Capabilities

- `android-direct-store-read`: authorized direct-filesystem enumeration of a user-selected store folder when the Android `DocumentsProvider` cannot enumerate it, covering tree-URI-to-path resolution, All-files-access authorization and revocation, read-only scoping to the selected directory, and the safety rejections that staging already enforces.

### Modified Capabilities

- `store-lifecycle`: Import currently guarantees only that it copies "every provider-visible file and directory", which makes an unlistable tree a conformant empty import. The requirement changes so that a root enumerating zero children is a recoverable provider fault: Import must attempt the provider first, may then offer the authorized direct read, and must report a distinct provider-fault outcome rather than silently succeeding or reporting an empty store.

## Impact

- `gui/android/app/src/main/kotlin/top/vollate/pars_gui/ManagedStoreImporter.kt`: empty-root classification, the direct-read staging path, and the new failure code.
- `gui/android/app/src/main/AndroidManifest.xml`: `MANAGE_EXTERNAL_STORAGE` declaration plus the settings intent used to request it.
- `gui/lib/services/path_picker_service.dart` and `gui/lib/screens/onboarding/widgets/onboarding_store_setup_widgets.dart`: the authorization prompt and the new error code, which currently discards the platform message in favor of a localized string.
- `gui/lib/l10n/app_en.arb`, `gui/lib/l10n/app_zh.arb`, and generated localizations: provider-fault and authorization strings.
- `gui/android/app/src/androidTest/`: the synthetic provider gains an "empty and not loading" tree; new instrumentation covers provider-first ordering, the fallback, and the declined path.
- Distribution: `MANAGE_EXTERNAL_STORAGE` requires a Play Console declaration. Sideloaded and F-Droid builds are unaffected, and the permission must remain unused unless the provider has already failed.
- No Rust, bridge, CLI, or store-registration behavior changes. Staging, finalize, commit, and rollback seams are reused unchanged.
