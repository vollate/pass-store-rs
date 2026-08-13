## 1. Protection Policy and Fixtures

- [x] 1.1 Add pure-Rust test fixtures for v4 private keys with protected primary/signing/encryption packets using legacy SHA-1 S2K, including a low-cost deterministic fixture for CI and metadata coverage for coded count 255.
- [x] 1.2 Add fixtures for compliant v4 managed protection, v6 Argon2/AEAD protection, unprotected private material, and protected packets that require different passphrases.
- [x] 1.3 Implement a centralized, explicitly versioned local protection policy that constructs v4 AES-256 CFB + iterated SHA-256 count 224 and v6 AES-256 OCB + Argon2id `t=3`, `p=4`, `m_enc=16` parameters with fresh per-packet randomness.
- [x] 1.4 Implement and test the accepted-policy predicate so compliant non-legacy packets are recognized without rewrite and MD5, SHA-1, and RIPEMD-160 S2K packets require migration.
- [x] 1.5 Add tests that policy constants do not drift when the rPGP dependency default changes and are never reduced based on measured runtime.

## 2. One-Pass Private-Key Preparation

- [x] 2.1 Refactor inspected private-key ownership so the pure-Rust import path can prepare a mutable key without exposing private bytes or plaintext parameters through public DTOs or `Debug` output.
- [x] 2.2 Implement all-packet preparation that unlocks each protected primary key or subkey exactly once with the supplied passphrase and rejects absent, incorrect, or inconsistent packet passphrases before mutation.
- [x] 2.3 Re-protect every noncompliant protected packet with the applicable local policy and the same passphrase while leaving currently unprotected packets under the existing unprotected-import behavior.
- [x] 2.4 Verify bindings, capabilities, public packet bytes, and canonical primary fingerprint before and after preparation, and return a typed sanitized failure on any mismatch.
- [x] 2.5 Zeroize temporary serialized secret buffers where supported and add tests that preparation errors and debug output contain no passphrase, source key bytes, plaintext secret parameters, or derived material.
- [x] 2.6 Add a regression test proving the pure-Rust import path does not run a separate legacy passphrase validation before performing the one required unlock used for re-protection.

## 3. Atomic Pure-Rust Keyring Storage

- [x] 3.1 Add a restrictive same-directory temporary-file writer for protected private-key records with flush, sync, atomic rename, and failure cleanup.
- [x] 3.2 Change private-key storage to serialize only the fully re-protected OpenPGP key into the atomic writer; never serialize an unprotected intermediate to persistent storage.
- [x] 3.3 Stage public-record updates so a new import is complete only after the private record is durable, while preserving an existing public/private record until its replacement is ready.
- [x] 3.4 Add fault-injection tests for preparation, serialization, permission, sync, and rename failures that prove duplicate import preserves the previous private-key file and leaves no temporary secret file.
- [x] 3.5 Update core import/backend plumbing to provide the validated passphrase to pure-Rust preparation without changing system-GPG ownership of local key protection.
- [x] 3.6 Add import tests covering protected v4/v6, unprotected, duplicate, incorrect-passphrase, inconsistent-packet-passphrase, and unchanged-fingerprint outcomes.

## 4. Existing-Key Migration and Export

- [x] 4.1 Add a fingerprint-bound core operation that loads one existing pure-Rust private record, validates all protected packets, and atomically migrates only noncompliant protection.
- [x] 4.2 Make compliant existing records a validation-only no-op and test that their private-key file is not replaced merely to refresh salts or timestamps.
- [x] 4.3 Add migration failure tests proving wrong passwords, unsupported packet combinations, and storage failures preserve the original record and report no prepared session.
- [x] 4.4 Ensure deleting and listing migrated keys continue to use the unchanged canonical fingerprint and existing keyring paths.
- [x] 4.5 Add rPGP round-trip tests that a migrated key decrypts password-store entries with the same passphrase and no longer uses legacy SHA-1 S2K on subsequent unlocks.
- [x] 4.6 Add GnuPG interoperability coverage that exports a re-protected private key, imports it with the same passphrase, confirms the same fingerprint, and decrypts a fixture.

## 5. Bridge Contract

- [x] 5.1 Add the fingerprint-bound existing-private-key preparation request/response and bridge method, including the backend-confirmed fingerprint on success.
- [x] 5.2 Add stable bridge failure kinds for unsupported packet protection and local re-protection/commit failure, with sanitized core-to-bridge mappings.
- [x] 5.3 Update protected PGP import responses so success is returned only after pure-Rust re-protection commits, while system and bundled GPG retain their existing import behavior.
- [x] 5.4 Update the supported method table and secret-field configuration so preparation passphrases and any future private preparation fields cannot be logged.
- [x] 5.5 Add bridge smoke tests for import commit ordering, fingerprint-bound existing-key migration, compliant no-op, typed failures, system-GPG separation, and secret redaction.
- [x] 5.6 Regenerate flutter_rust_bridge Rust/Dart bindings and verify generated APIs match the declared method table.

## 6. Flutter Session Orchestration and i18n

- [x] 6.1 Extend the Flutter repository abstraction and bridge-backed implementation with fingerprint-bound existing-key preparation and typed failure mapping.
- [x] 6.2 Keep protected import pending until the bridge confirms re-protection commit, and start the key-bound PGP session only after that success.
- [x] 6.3 Prepare or migrate an existing selected key before manual passphrase session activation, clearing retry input and leaving prior session state unchanged on failure.
- [x] 6.4 Apply the same preparation boundary when a passphrase is restored from explicit Keychain/KMS storage or biometric unlock, without changing opt-in persistence behavior.
- [x] 6.5 Preserve immediate, five-minute, fifteen-minute, one-hour, and until-app-exit expiration behavior and ensure preparation never extends or bypasses an existing timeout.
- [x] 6.6 Add all new pending, success, and typed failure messages to the existing localization resources and use generated i18n accessors without introducing hard-coded English strings or a new sheet style.
- [x] 6.7 Reuse the established Settings, Onboarding, and vault unlock pending/error components, disable duplicate submission during one-time legacy work, and keep password entry visible when the keyboard opens.
- [x] 6.8 Add repository, security-orchestration, and widget tests for import commit ordering, existing-key migration, biometric/secure-cache preparation, retry cleanup, localized feedback, duplicate-submit prevention, and unchanged expiration.

## 7. Verified Managed-Key Deletion

- [x] 7.1 Replace unit-valued PGP deletion with a core result that reports the canonical fingerprint, prior private-material presence, verified private-record absence, and verified public-record absence.
- [x] 7.2 Serialize deletion against same-fingerprint import/migration, remove the authoritative managed private record before the public record, clean same-key preparation temporaries, and verify path absence without modifying `.gpg-id`.
- [x] 7.3 Add pure-Rust fault tests for complete deletion, private-removal failure preserving the public listing, public-cleanup failure returning a private-absent partial result, and deletion racing preparation.
- [x] 7.4 Add a dedicated bridge deletion response and typed cleanup failure mapping without adding a passphrase to the request; regenerate Rust/Dart bindings and update the supported method contract.
- [x] 7.5 Update the Flutter repository and Settings deletion flow to clear matching session/cache state whenever private absence is confirmed, preserve it when private removal fails, refresh visible state, and render full/partial/failure outcomes through i18n using the existing dialog and notification style.
- [x] 7.6 Add bridge, repository, security, and widget tests proving the converted private record is actually gone, partial outcomes are accurate, confirmation remains name-based, and `.gpg-id` references are preserved as missing-local-material records.
- [x] 7.7 Require only the PGP display name for GUI deletion confirmation, excluding a trailing `<email>` identity component while preserving SSH confirmation behavior; make the dialog keyboard-safe and cover both behaviors with widget tests.

## 8. Verification and Performance Evidence

- [x] 8.1 Run focused core and bridge tests, full Rust workspace tests, formatting, and lint checks for the affected crates.
- [x] 8.2 Run Flutter generation, localization generation, formatting, static analysis, and focused/full test suites.
- [x] 8.3 Run GnuPG interoperability tests on a supported desktop environment and record the exact GnuPG/rPGP versions used.
- [x] 8.4 On the reference Android device in release mode, record the one-time coded-count-255 SHA-1 import/migration duration separately from subsequent session preparation and entry decryption.
- [x] 8.5 Capture a post-migration profile proving subsequent unlock no longer enters `sha1_checked` legacy S2K; document `sha1-checked` replacement or specialization only as a future optional optimization.
- [x] 8.6 Verify no plaintext private key, passphrase, salt-derived key, or raw private material appears in Rust logs, bridge diagnostics, Flutter notifications, temporary files, or failure snapshots.
- [x] 8.7 Run `openspec validate reprotect-imported-private-keys --strict` and confirm every normative scenario has automated coverage or an explicit device/interoperability verification step.
