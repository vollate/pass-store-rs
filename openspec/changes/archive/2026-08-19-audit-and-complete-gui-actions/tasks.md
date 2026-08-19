## 1. Complete and Record the Production GUI Audit

- [x] 1.1 Scan non-generated Flutter, Android, and iOS production GUI sources for literal empty action callbacks, empty method bodies, unimplemented markers, placeholder surfaces, and always-null action handlers; record every match with file, line, reachability, and classification.
- [x] 1.2 Confirm the audit classification distinguishes the three entry-detail defects from rebuild-only `setState` closures, unreachable directory-copy plumbing, platform-channel unknown-method responses, plugin exception handling, generated code, test/fake repositories, and Android signing configuration.
- [x] 1.3 Add a verification document for this change containing the before/after audit inventory and remove the resolved Edit/Regenerate/Delete bullet from the main `flutter-vault-and-manage` Needs Verification section only after implementation is validated.

## 2. Reuse Focused Manage Workflows

- [x] 2.1 Add focused single-entry launcher functions in the Manage library for edit, regenerate, and delete while keeping the underlying form widgets private and preserving existing submit/error state.
- [x] 2.2 Make focused edit load only the selected entry and preserve both reconstructed-field save and first-line replacement behavior with the existing optional commit message.
- [x] 2.3 Make focused regenerate use singular UI copy and call `batchRegenerateEntries` with exactly the selected entry, length 24, the selected symbol policy, and the existing optional commit behavior.
- [x] 2.4 Make focused delete display the full target path, require the existing display-label confirmation, call `deleteEntry` with the correct recursive flag, and preserve optional commit behavior.

## 3. Wire Entry Detail Actions

- [x] 3.1 Replace the Edit, Regenerate, and Delete literal empty callbacks with explicit action callbacks or a typed detail-route action result; leave controls disabled when the repository cannot manage entries.
- [x] 3.2 Update `VaultScreen` to await the detail action, close and dispose the decrypted sheet before mutation navigation, and launch the matching focused workflow for the same `PasswordEntry`.
- [x] 3.3 Report successful entry and batch results through `AppNotification`, refresh/rebuild visible Vault state as needed, and keep cancellation notification-free.
- [x] 3.4 Verify errors remain visible in the focused operation sheet and that a failed optional Git commit is not reported as a rolled-back vault mutation.

## 4. Remove Remaining Production Callback Placeholders

- [x] 4.1 Make `EntryTile` directory copy handling nullable so `VaultScreen` no longer supplies the unreachable `onCopy: () {}` callback.
- [x] 4.2 Replace the Settings Git fallback's mocked-phase placeholder text with an explicit unavailable-capability explanation and ensure it exposes no nonfunctional action control.
- [x] 4.3 Add a production-source regression test that rejects literal empty closures assigned to user-action properties such as `onPressed`, `onTap`, and `onLongPress`, excluding generated and test sources without broad allowlists.

## 5. Regression Tests

- [x] 5.1 Add an `EntryDetailSheet` widget test proving Edit, Regenerate, and Delete each invoke their supplied callback and are disabled when callbacks are absent.
- [x] 5.2 Add `VaultScreen` tests proving each detail action clears/closes detail before opening the focused workflow and that cancelling performs no repository mutation.
- [x] 5.3 Add recording-repository tests proving edit targets the displayed path, regenerate passes a one-entry list and preserves existing content semantics, and delete requires confirmation before targeting the displayed path.
- [x] 5.4 Add result/error tests proving successful actions notify the user, failed actions remain actionable with an error, and delete removes the stale entry from the visible Vault list.

## 6. Validation

- [x] 6.1 Run Dart formatting checks, focused entry-detail/Vault/Manage widget tests, the full Flutter test suite, and `flutter analyze`.
- [x] 6.2 Re-run the production GUI empty-implementation audit and verify that no reachable user-action callback remains literally empty; document all remaining intentional findings.
- [x] 6.3 Run strict OpenSpec validation for `audit-and-complete-gui-actions` and confirm all implementation evidence is captured before archival.
