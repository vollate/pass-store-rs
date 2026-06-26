## 1. Core and Bridge Key Deletion

- [x] 1.1 Add failing Rust tests for deleting PGP keys through the pure Rust backend and deleting SSH private/public key files by name.
- [x] 1.2 Extend the PGP backend trait with a delete operation and implement it for system/bundled GPG and pure Rust keyrings.
- [x] 1.3 Add a core SSH key deletion helper that removes both `<name>` and `<name>.pub` and errors when neither exists.
- [x] 1.4 Add bridge request/response APIs for deleting PGP keys by fingerprint and SSH keys by name.
- [x] 1.5 Regenerate Flutter Rust Bridge bindings and update generated Dart/Rust bridge files.

## 2. Flutter Repository and Security State

- [x] 2.1 Add failing Dart tests for `KeyRepository` delete methods in fake and bridge-backed repository behavior.
- [x] 2.2 Add `deletePgpKey` and `deleteSshKey` to `KeyRepository`, `FakeParsRepository`, and `BridgeBackedRepository`.
- [x] 2.3 Add failing security repository tests for key-bound PGP passphrase storage, biometric session restoration with fingerprint metadata, and legacy unbound cache clearing.
- [x] 2.4 Replace bare PGP passphrase storage/session APIs with a key-bound cache value that includes the selected PGP fingerprint.
- [x] 2.5 Add a security repository method for clearing cached and active PGP passphrase state only when it matches a deleted fingerprint.

## 3. Settings UI

- [x] 3.1 Add failing widget tests for PGP key deletion, SSH key deletion, deletion cancellation, delete failure display, and key-specific passphrase saving.
- [x] 3.2 Add Delete actions to PGP and SSH key menu controls in Settings.
- [x] 3.3 Implement key deletion confirmation dialogs that require exact key-identifying confirmation text and warn about local key material removal.
- [x] 3.4 Refresh visible key data after successful deletion and keep keys visible when deletion fails or is canceled.
- [x] 3.5 Update the PGP passphrase storage sheet to require selecting a private PGP key before saving and to display the cached key identity.
- [x] 3.6 Clear matching cached/active PGP passphrase state after successful PGP key deletion.

## 4. Verification

- [x] 4.1 Run Rust tests covering core key management, PGP backend behavior, and bridge smoke coverage.
- [x] 4.2 Run Flutter tests covering security repository, bridge-backed repository, and settings smoke flows.
- [x] 4.3 Run formatting, static analysis, and OpenSpec validation for the change.
