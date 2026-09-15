## 1. Classify the unlistable root

- [x] 1.1 Distinguish an empty granted root from an empty subdirectory in `ManagedStoreImporter`, evaluating the fault only at depth 0 after all root attempts are exhausted.
- [x] 1.2 Raise a distinct `store_import_provider_unlistable` failure instead of `store_import_no_passwords` for that case, and delete staging before returning.
- [x] 1.3 Log the tree authority, root document ID, and final attempt count for the fault path, without logging entry names or file contents.
- [x] 1.4 Add JVM tests asserting that an empty root reports the provider fault while an empty subdirectory below an enumerated root stages as an ordinary empty directory.

## 2. Surface the fault in Flutter

- [x] 2.1 Add `storeImportProviderUnlistable` and the authorization-prompt strings to `app_en.arb` and `app_zh.arb`, then regenerate localizations.
- [x] 2.2 Map the new code in `path_picker_service.dart` and stop routing it through the `store_import_no_passwords` substitution in `onboarding_store_setup_widgets.dart`.
- [x] 2.3 Present the provider-fault explanation with the recovery offer and a Clone pointer, defaulting to no filesystem access when the user takes no action.
- [x] 2.4 Add Dart tests for the new code mapping, the localized message in both locales, and the declined path leaving no store registered.

## 3. Resolve the selection to a filesystem path

- [x] 3.1 Add a tree-URI-to-path resolver that accepts only the platform external-storage authority and splits the tree document ID into volume and relative parts.
- [x] 3.2 Map the volume through `StorageManager.getStorageVolumes()`, matching the primary volume for `primary` and otherwise the volume UUID.
- [x] 3.3 Canonicalize the result and require an existing directory contained within the volume directory, failing closed on unsupported authorities, unresolvable volumes, and containment violations.
- [x] 3.4 Add JVM tests for primary and UUID volumes, escaping relative parts, unknown authorities, and non-directory targets.

## 4. Authorize the recovery

- [x] 4.1 Declare `MANAGE_EXTERNAL_STORAGE` in the manifest with a comment recording that it is reachable only from the import provider-fault path.
- [x] 4.2 Add an authorization check backed by `Environment.isExternalStorageManager()` that is re-evaluated immediately before every direct read rather than cached.
- [x] 4.3 Add the contextual request that opens `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` for this package and re-checks the grant on return without assuming success.
- [x] 4.4 Add tests covering never requesting authorization on a working provider, declining, dismissing, and revocation between attempts.

## 5. Stage through the direct read

- [x] 5.1 Add a `stageDirectoryDirect` method channel entry that accepts the tree URI only, never a caller-supplied path, and fails closed otherwise.
- [x] 5.2 Traverse the resolved directory read-only and reuse the existing safe-name, duplicate-name, cycle, path-escape, and maximum-depth rejections against real filesystem entries.
- [x] 5.3 Reject non-regular entries including symbolic links, and confine traversal to the resolved selected directory.
- [x] 5.4 Produce the same staging directory, opaque handle, and destination as the provider path and hand off to the unchanged finalize, commit, and rollback seams.
- [x] 5.5 Verify Git classification still runs on a directly staged tree, including the absent-Git decision.
- [x] 5.6 Confirm the source directory is unchanged after staging and that no file was opened for writing.

## 6. Instrumentation and device evidence

- [x] 6.1 Extend the synthetic `DocumentsProvider` with a root that returns zero children and reports loading finished on every query.
- [x] 6.2 Add instrumentation asserting the provider is attempted first and that a working provider never invokes the direct path or requests authorization.
- [x] 6.3 Add instrumentation for a successful recovery, a declined recovery, and an unresolvable authority.
- [ ] 6.4 Verify on the ColorOS device that Import recovers the real store, and on the Android emulator that the provider path is unchanged.
- [x] 6.5 Record device evidence with device model, build fingerprint, and the resulting entry count, without recording entry names or secrets.

## 7. Validation and hygiene

- [x] 7.1 Run `dart format`, `flutter analyze`, and the Flutter test suite.
- [ ] 7.2 Run the Android JVM unit tests and the instrumentation suite.
- [x] 7.3 Run `cargo fmt --all -- --check`, workspace Clippy, and workspace tests to confirm no Rust behavior changed.
- [x] 7.4 Run `openspec validate recover-import-from-unlistable-provider --strict` and record the Play Console justification needed for `MANAGE_EXTERNAL_STORAGE`.
