## Confirmation Inventory

### Requires change

- `settings_key_management_widgets.dart`: PGP key deletion requires typing the
  full fingerprint. It should require the visible key name and show the
  fingerprint only as context.
- `settings_key_management_widgets.dart`: Private-key export uses a generic
  confirmation field with no visible phrase. PGP export also relies on the
  backend's fingerprint phrase. It should show `EXPORT PRIVATE KEY <key name>`
  for both PGP and SSH, while still targeting PGP by fingerprint.
- `manage_single_entry_widgets.dart`: Single-entry delete requires the full
  password-store path. It should require `PasswordEntry.displayName` and show
  the full path as read-only context.
- `settings_git_widgets.dart`: Delete-local-repo uses a generic confirmation
  field. Because it delegates to local-store deletion, the UI must show the
  expected selected-store name before submission.

### Acceptable as-is

- `manage_batch_widgets.dart`: Batch delete requires the short explicit token
  `DELETE` and already shows that expected text on validation failure.
- `settings_store_widgets.dart`: Local store deletion already uses the store
  name after `simplify-store-delete-confirmation`.
