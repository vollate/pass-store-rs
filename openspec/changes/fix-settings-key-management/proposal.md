## Why

Settings currently lets users view and add PGP/SSH keys, but it does not let
them remove keys they no longer want to keep on the device. The PGP passphrase
cache also accepts a passphrase without identifying which PGP key it belongs
to, making the saved secret ambiguous when multiple PGP keys exist.

## What Changes

- Add settings actions to delete existing PGP keys and SSH keys.
- Require deletion confirmation that identifies the exact key being removed.
- Make PGP passphrase caching key-specific by requiring the user to choose the
  target PGP key before saving a passphrase.
- Persist and expose enough metadata for the cached PGP passphrase to be tied
  to its selected key.
- Clear or invalidate a cached passphrase when its associated PGP key is
  deleted.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pgp-and-key-management`: Key management must support deleting PGP and SSH
  keys through the GUI-facing repository/bridge surface.
- `flutter-security-and-onboarding`: Settings must expose key deletion and
  key-specific PGP passphrase cache behavior.

## Impact

- Rust key management and bridge APIs may need delete-key methods for PGP and
  SSH keys.
- Flutter `KeyRepository` and repository implementations need matching methods.
- Flutter `SecurityRepository` passphrase cache data needs associated PGP key
  metadata.
- Settings UI and tests need updates for delete actions, confirmation flows,
  passphrase key selection, and cache invalidation.
