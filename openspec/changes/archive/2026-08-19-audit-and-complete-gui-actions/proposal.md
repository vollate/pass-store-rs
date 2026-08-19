## Why

The loaded entry-detail surface exposes Edit, Regenerate, and Delete as active buttons whose callbacks are literal no-ops, so taps provide no navigation, result, or error. A production-GUI audit is needed now to distinguish genuine empty action implementations from intentional framework/test no-ops and to prevent future user-visible controls from silently doing nothing.

## What Changes

- Inventory literal empty callbacks, unimplemented markers, placeholder surfaces, and empty method bodies across Flutter, Android, and iOS GUI production sources, classifying every finding as user-visible defect, intentional lifecycle/framework behavior, generated code, test fixture, or configuration debt.
- Replace the entry-detail Edit, Regenerate, and Delete no-op handlers with focused single-entry workflows backed by `ManageRepository`.
- Close or transition the detail sheet before opening a mutation workflow so decrypted content is cleared and a successful mutation cannot leave stale entry details visible.
- Reuse the existing edit, password-regeneration, delete-confirmation, optional-commit, error, and result-notification behavior rather than introducing a second mutation contract.
- Remove unreachable callback placeholders such as the directory-copy no-op and replace stale placeholder fallback copy with explicit unavailable-state behavior where applicable.
- Add regression coverage that exercises all three entry-detail actions through `VaultScreen` and rejects new literal empty user-action callbacks in production GUI source.
- Record intentional exclusions: rebuild-only `setState(() {})` closures, unknown-method `notImplemented` responses, plugin `UnimplementedError` handling, generated initializers, test doubles, and Android release-signing configuration are not treated as missing runtime action implementations.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `flutter-vault-and-manage`: Entry detail will provide working edit, regenerate, and delete transitions and production GUI controls will fail visibly or be disabled rather than silently invoking empty callbacks.

## Impact

- Flutter entry detail and vault orchestration under `gui/lib/screens/vault/`.
- Reusable single-entry operation sheet launchers under `gui/lib/screens/manage/`.
- Entry tile callback typing and Settings unavailable-state copy where audit findings require cleanup.
- Flutter widget/source-regression tests in `gui/test/`.
- No Rust core, bridge DTO, password-store ciphertext, Android/iOS Autofill contract, or repository mutation API changes are expected.
