## Why

PGP key import is inconsistent across the GUI: Settings offers a partial
Text/File choice while Onboarding only accepts pasted text, and neither flow
collects and verifies a private-key passphrase after import. System GPG imports
can also return an empty fingerprint, preventing the imported key, active
session, and optional secure-storage cache from being associated reliably.

## What Changes

- Give both Settings and Onboarding one consistent PGP import flow with Text and
  File as source choices.
- Detect whether supported imported PGP material is public or private regardless
  of whether it came from text or a file; do not treat File as synonymous with
  private-key import.
- Return the imported key's canonical fingerprint and metadata for every
  supported backend, including system GPG and duplicate/re-import cases.
- After importing a passphrase-protected private key, require the user to enter
  and validate its passphrase against that exact key before completing the flow.
- Start a key-bound in-memory PGP session after successful validation and offer
  explicit, opt-in storage in the platform Keychain/KMS; public and unprotected
  private keys do not request an unnecessary passphrase.
- Keep private key material and passphrases out of errors, logs, and persistent
  storage unless the user explicitly enables secure passphrase storage.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pgp-and-key-management`: Make PGP import source-independent, return a stable
  imported fingerprint, and support exact-key private passphrase validation.
- `flutter-security-and-onboarding`: Use the same Text/File import experience in
  Settings and Onboarding and complete private imports with a key-bound session
  plus optional secure passphrase storage.
- `native-bridge-api`: Expose typed source detection/import and private-key
  passphrase validation behavior without leaking secret inputs.

## Impact

- Rust core PGP backends and key-material detection/import helpers.
- Native bridge request/response DTOs, supported method table, generated Flutter
  bindings, and secret-field configuration.
- Flutter `KeyRepository`, bridge-backed repository, Onboarding key setup,
  Settings key management, security repository integration, and path picker UI.
- Rust bridge/core tests and Flutter repository, security, and widget tests.
- No CLI command behavior or password-store file format changes are intended.
