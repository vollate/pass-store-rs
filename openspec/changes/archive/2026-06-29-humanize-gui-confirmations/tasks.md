## 1. Confirmation Inventory

- [x] 1.1 Audit GUI confirmation fields for key deletion, private-key export, single-entry deletion, batch deletion, and settings local-repo deletion.
- [x] 1.2 Document which confirmations remain acceptable short phrases and which require UI or backend changes.

## 2. PGP Private Export Confirmation

- [x] 2.1 Update bridge PGP private export validation to derive the expected phrase from the selected key's listed human-readable identity while still exporting by fingerprint.
- [x] 2.2 Add or update bridge/core tests for successful PGP private export with `EXPORT PRIVATE KEY <identity>` and rejection of the old fingerprint phrase.

## 3. Settings Key Confirmation UI

- [x] 3.1 Add small helper logic for key confirmation labels and private-export phrases in settings key management widgets.
- [x] 3.2 Update PGP and SSH key deletion dialogs to show key name, key type, fingerprint context, and the exact required typed confirmation.
- [x] 3.3 Update private-key export dialogs to show the exact `EXPORT PRIVATE KEY <label>` phrase before enabling export.
- [x] 3.4 Update settings key-management widget tests for PGP delete, SSH delete, PGP export, and SSH export confirmation behavior.
- [x] 3.5 Update settings Git local-repo deletion to show and enforce the selected store-name confirmation phrase.

## 4. Password Entry Delete Confirmation

- [x] 4.1 Update the single-entry delete sheet to require `PasswordEntry.displayName` rather than the full entry path.
- [x] 4.2 Keep the selected entry's full path visible as read-only target context and reset confirmation text when the selected entry changes.
- [x] 4.3 Update manage-screen widget tests for successful deletion and incorrect confirmation copy.

## 5. Verification

- [x] 5.1 Run focused bridge tests covering key export confirmation.
- [x] 5.2 Run focused Flutter widget tests covering settings key management and manage delete confirmation.
- [x] 5.3 Run formatting and static analysis for touched Rust and Dart files.
- [x] 5.4 Run `openspec validate humanize-gui-confirmations --strict`.
