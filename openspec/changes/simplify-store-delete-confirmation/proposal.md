## Why

Deleting an app-managed store currently asks users to type the full normalized
root path, which can be an unreadable Android internal path such as
`/data/user/0/top.vollate.pars_gui/files/stores/...`. That protects a
destructive action, but the confirmation token is hostile and easy to mistype.

## What Changes

- Change local store deletion confirmation to require only the final store
  name, derived from the store root basename and matching the name shown in the
  store list.
- Keep the full store root visible as read-only context in the delete dialog.
- Update validation errors and helper text so users know they should type the
  displayed store name, not the full path.
- Preserve destructive safeguards: the selected root must still be configured,
  must exist as a directory, must not be a filesystem root, and deletion must
  remove the store from config before deleting files.
- Add tests covering the store-name confirmation path and mismatch failure.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `store-lifecycle`: Delete-local-store confirmation changes from full
  normalized root matching to final store name matching.

## Impact

- Bridge delete-local-store validation in `bridge/src/api.rs`.
- Flutter settings store delete dialog in
  `gui/lib/screens/settings/widgets/settings_store_widgets.dart`.
- Repository-facing tests in `gui/test/bridge_backed_repository_test.dart` and
  bridge/store lifecycle tests that exercise delete-local-store confirmation.
- Generated bridge bindings should not need schema changes because the request
  still carries `root` and `confirmation` strings.
