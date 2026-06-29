## Why

Several destructive or sensitive GUI actions currently ask users to type machine
identifiers such as full PGP fingerprints or full password-store paths. This is
hostile on mobile, easy to mistype, and trains users to copy opaque strings
instead of confirming the item they recognize.

## What Changes

- Replace GUI key deletion confirmation text with human-readable key labels
  while still targeting PGP keys internally by fingerprint and SSH keys by name.
- Make private-key export dialogs show the exact confirmation phrase and use a
  human-readable key label for PGP export instead of requiring the fingerprint.
- Replace single password-entry delete confirmation from full path input to a
  short display label, while keeping the full path visible as read-only context.
- Keep existing short destructive confirmations such as batch delete `DELETE`.
- Ensure destructive/sensitive confirmation fields show the exact required
  phrase before the user submits.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `flutter-security-and-onboarding`: Settings key deletion confirmation SHALL
  use human-readable key labels rather than requiring full PGP fingerprints.
- `pgp-and-key-management`: Private PGP key export confirmation SHALL no longer
  require the PGP fingerprint as the typed phrase.
- `password-store-entries`: GUI single-entry deletion SHALL use a short
  human-readable confirmation token instead of the full entry path.

## Impact

- GUI settings key-management dialogs and tests.
- GUI password-entry delete sheet and tests.
- Bridge/core private PGP export confirmation validation and related tests.
- Existing settings destructive confirmation fields that omit the required
  phrase from their visible instructions.
