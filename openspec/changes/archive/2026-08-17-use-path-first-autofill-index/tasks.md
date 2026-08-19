## 1. Core Path-First Model and Persistence

- [x] 1.1 Add unit tests for logical path normalization and derivation of immediate-parent service name, filename-stem username, host-like website identity, display fallback, nested paths, Unicode/case handling, and root-level entries.
- [x] 1.2 Replace `AutofillIndexEntry` and related request/candidate models with the path-first schema, including separate `path_website` and `enriched_websites` fields, and delete Android package and decrypted-username fields.
- [x] 1.3 Replace index reads/writes with strict replacement-schema decoding and atomic temporary-file replacement; add malformed-index and concurrent-reader safety tests without adding legacy parsing or migration code.

## 2. Core Lifecycle, Matching, and Resolution APIs

- [x] 2.1 Replace backend-backed refresh with `rebuild_autofill_index`, recursively deriving all records from store paths plus ranking metadata without accepting a backend, executable, or passphrase; prove zero decrypt calls in tests.
- [x] 2.2 Implement no-op-when-uninitialized upsert, move, remove/path-prefix, and ranking-patch operations, including preservation of ranking and enriched aliases across moves and tests that unrelated logical records remain unchanged.
- [x] 2.3 Implement path-only reconciliation for batch store/Git changes and verify that it performs no decryption or secret parsing.
- [x] 2.4 Replace candidate matching with normalized path-website, case-insensitive app/service-name, enriched-website, and text-fallback score classes; preserve bounded favorite/recent bonuses and delete package normalization/matching code and tests.
- [x] 2.5 Change credential resolution to return the indexed filename-stem username and decrypt exactly the selected entry once for its first-line password, without writing or enriching the index; add counting-backend regression tests.
- [x] 2.6 Implement explicit non-empty-path website enrichment and alias clearing, including URL/website/service normalization, selected-path-only decrypt counts, all-or-nothing failure behavior, and preservation of path-derived metadata.

## 3. Bridge and Generated SDK Surface

- [x] 3.1 Replace `bridge/src/api.rs` autofill DTOs and functions with rebuild, upsert, move, remove, reconcile, ranking-patch, enrichment, alias-clear, query, resolve, and clear operations; omit PGP inputs from every default lifecycle request.
- [x] 3.2 Replace `bridge/src/autofill_native.rs` query JSON with website/app-name/query/limit inputs, delete Android package members, and keep credential resolution as the only normal native secret-bearing operation.
- [x] 3.3 Delete old refresh/package API symbols rather than retaining aliases or wrappers, regenerate Rust and Dart Flutter Rust Bridge bindings, and verify generated source contains only the replacement contract.
- [x] 3.4 Add bridge and native-ABI tests for new JSON shapes, strict rejection/fail-closed handling of malformed replacement indexes, zero-decrypt lifecycle calls, and one-decrypt credential resolution.

## 4. Dart Repository and Vault Orchestration

- [x] 4.1 Replace `AutofillRepository`, bridge adapters, fakes, and tests with the path-first lifecycle and query methods, including explicit URL-enrichment controls and no passphrase requirement for default rebuild.
- [x] 4.2 Update `BridgeBackedRepository` to upsert after successful create/edit, move after successful rename/move, remove after successful entry/folder delete, and reconcile only changed paths after batch store/Git refreshes.
- [x] 4.3 Patch favorite/recent ranking after metadata changes while preserving the metadata-only read regression that forbids full rebuilds and decrypt amplification.
- [x] 4.4 Ensure incremental autofill failures cannot roll back already-successful vault mutations, report actionable autofill errors, and remain no-ops when the index has not been initialized.
- [x] 4.5 Replace Settings refresh/clear UI and tests with path-only wording and add a separate default-off URL-enrichment flow that requires explicit non-empty selection, disclosure, failure reporting, and alias clearing.
- [x] 4.6 Publish platform state and synchronize iOS identities only after successful atomic index operations, without coupling normal index publication to PGP session preparation.

## 5. Android Provider Replacement

- [x] 5.1 Replace `ParsedAutofillRequest` and request parsing to expose web domain, human-readable app label, text query, and field IDs, obtaining the label through `PackageManager` without passing the package identifier to shared matching.
- [x] 5.2 Replace Kotlin native bridge request/candidate models and JSON serialization with the app-name contract and delete all `androidPackage` parameters and package-match display paths.
- [x] 5.3 Update both `ParsAutofillService` and `ParsCredentialProviderService` to query by website/app label, retain authenticated selected-entry resolution, and return no exact candidate for package-only requests.
- [x] 5.4 Replace Android parser, bridge, AutofillService, Credential Manager, cancellation, authentication, and dataset tests to cover domain matches, app-label matches, package omission, and one selected credential.

## 6. iOS Provider Replacement

- [x] 6.1 Replace Swift shared-index decoding with the path-first schema and register `ASPasswordCredentialIdentity` values only for host-like path websites and explicit enriched website aliases.
- [x] 6.2 Replace Swift C-ABI query construction and candidate models with website/app-name/query inputs and remove the Android-package placeholder parameter.
- [x] 6.3 Update the Credential Provider extension to display path-derived service/username values, preserve local authentication, and resolve only the selected path.
- [x] 6.4 Replace iOS JSON-decoding, identity synchronization, provider-list, authentication-cancel, and selected-credential tests for the replacement schema.

## 7. Verification and Documentation

- [x] 7.1 Run Rust autofill/core/bridge tests, full workspace tests, formatting, and Clippy with warnings denied; verify no old refresh-with-backend or Android package autofill symbols remain.
- [x] 7.2 Run focused Dart repository/settings tests, the full Flutter test suite, `flutter analyze`, and Dart formatting checks.
- [x] 7.3 Run Android unit/instrumentation checks and an iOS build/test pass where signing infrastructure permits, recording any platform-only verification limitations.
- [x] 7.4 Run strict OpenSpec validation and update autofill documentation plus `calibrate-rpgp-local-key-protection/verification.md` to distinguish the previous whole-vault Autofill amplification from single-entry rPGP latency.
- [x] 7.5 Build and install a release APK without clearing app data, then verify on the real vault that explicit path rebuild and metadata updates perform zero decrypts, selected credential resolution performs exactly one decrypt, and end-to-end selected-entry open remains below 800 ms.
