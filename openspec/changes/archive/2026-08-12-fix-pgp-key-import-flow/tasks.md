## 1. Core PGP Import Inspection

- [x] 1.1 Add core fixtures and failing tests for armored public keys, armored protected/unprotected private keys, and binary public/private key files.
- [x] 1.2 Add a byte-safe PGP import inspection result that reports key kind, canonical fingerprint, display identity, private-key availability, and passphrase protection.
- [x] 1.3 Replace marker-only PGP classification in the new import path with packet inspection while preserving sanitized errors and existing SSH detection behavior.
- [x] 1.4 Add failing tests that correct and incorrect passphrases are distinguished by unlocking the imported encryption-capable private material.
- [x] 1.5 Implement in-memory exact-material passphrase validation with zeroized temporary secret buffers and no secret values in errors.

## 2. Backend Import Identity and Atomicity

- [x] 2.1 Add failing system-GPG and pure-Rust tests that new and duplicate imports return the source key's canonical fingerprint and confirmed metadata.
- [x] 2.2 Make backend import accept byte-safe inspected material so binary files are not converted through UTF-8 text.
- [x] 2.3 Resolve system-GPG import identity from the inspected fingerprint plus backend confirmation instead of returning an empty fingerprint.
- [x] 2.4 Ensure protected private-key validation runs before either backend mutates its keyring, with tests that absent or incorrect passphrases leave no newly imported key.
- [x] 2.5 Add GnuPG interoperability coverage for supported armored/binary and protected/unprotected private-key imports.

## 3. Typed Native Bridge API

- [x] 3.1 Add failing bridge smoke tests for text/file inspection, public/private source independence, typed protection state, canonical fingerprint responses, and sanitized passphrase failures.
- [x] 3.2 Add PGP-specific text and file inspection/import request and response DTOs, including optional secret passphrase input and typed failure kinds.
- [x] 3.3 Implement text and file endpoints through the shared core inspector and atomic importer while keeping legacy type-specific methods as compatibility wrappers.
- [x] 3.4 Update the supported bridge method table and secret-field configuration so passphrase and key material cannot be logged.
- [x] 3.5 Regenerate Flutter Rust Bridge bindings and update bridge API adapter tests for the new methods and DTOs.

## 4. Flutter Repository and Security Orchestration

- [x] 4.1 Add Flutter models for PGP import source, inspected key metadata, protection state, and typed import failures.
- [x] 4.2 Extend `KeyRepository`, bridge-backed implementation, and test fakes with source-independent text/file inspection and import operations.
- [x] 4.3 Add repository tests proving file contents stay in Rust, returned fingerprints are preserved, and typed failures are mapped without secret text.
- [x] 4.4 Add security orchestration tests that a validated protected import starts a session for the returned fingerprint without durable storage by default.
- [x] 4.5 Implement explicit Remember in Keychain/KMS handling using the existing key-bound cache and cover enable/save/failure behavior without rolling back the imported key.

## 5. Shared PGP Import UI

- [x] 5.1 Add failing widget tests for a reusable PGP import body covering Text/File selection, native picker cancellation/error, inspection progress, and public/private branching.
- [x] 5.2 Implement the shared import state machine and UI with pasted text, a compact native key-file picker row, inline sanitized errors, and disabled actions while input is incomplete or submitting.
- [x] 5.3 Add the protected-private passphrase state with obscured input, validation retry, and a Remember in Keychain/KMS control that defaults off.
- [x] 5.4 Clear text, passphrase, and transient inspection state on success, cancellation, disposal, and failure paths, and add widget assertions that secrets are not rendered in errors or notifications.

## 6. Settings and Onboarding Integration

- [x] 6.1 Replace the Settings-only Text/File choice plus private-only file branch with the shared source-independent PGP import body.
- [x] 6.2 On Settings success, refresh the key list from the repository and report the canonical imported key without advancing on validation failure.
- [x] 6.3 Replace the Onboarding pasted-text-only form with the same Text/File import body and injected `PathPickerService`.
- [x] 6.4 On Onboarding success, select the returned fingerprint, attach it to the selected store when applicable, and advance to SSH only after protected-key validation succeeds.
- [x] 6.5 Add Settings and Onboarding widget tests for public, unprotected-private, protected-private correct/incorrect passphrase, opt-in cache, and secure-storage failure outcomes.

## 7. Verification

- [x] 7.1 Run focused core and bridge key-management/import test suites on the supported local backend configurations.
- [x] 7.2 Run focused Flutter repository, security, Settings, and Onboarding widget tests.
- [x] 7.3 Run Rust formatting and workspace checks plus `flutter analyze`, resolving all regressions introduced by the change.
- [x] 7.4 Run `openspec validate fix-pgp-key-import-flow --strict` and confirm every scenario has automated coverage or an explicit interoperability test.
