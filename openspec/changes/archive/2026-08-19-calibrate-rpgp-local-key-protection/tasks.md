## 1. Reproduce and Attribute the Regression

- [x] 1.1 Extend the rPGP Android benchmark with secret-safe stage timings for backend creation, message/key I/O and parsing, S2K/private-packet unlock, PKESK recovery, and payload decrypt/decompress.
- [x] 1.2 Run the benchmark through the same release-built native artifact and app-managed keyring path as the Flutter app; record the actual stored primary/subkey protection profiles and isolate the observed near-10-second stage.
- [x] 1.3 Add regression checks that distinguish one-time legacy SHA-1 migration, policy-v1 coded-224 preparation, and subsequent policy-compliant entry decrypt so the performance result cannot accidentally combine those phases.

## 2. Versioned Local Calibration Policy

- [x] 2.1 Implement a deterministic v4 S2K calibration component using the optimized production SHA-256 derivation path, a 100 ms target, 1 MiB decoded-count floor, 16 MiB ceiling, RFC count quantization, warm-up, and bounded verification.
- [x] 2.2 Add injectable timing/calibration seams and unit tests for count estimation, floor/ceiling clamping, downward quantization, slow-device behavior, and malformed timing results without using wall-clock assertions in CI.
- [x] 2.3 Add versioned non-secret policy-v2 metadata under the pure-Rust keyring and persist it with atomic write/rollback behavior; reuse a valid result and recalibrate only when metadata is absent, malformed, or stale.
- [x] 2.4 Update managed v4 parameter construction and accepted-policy detection to use the persisted calibrated count while leaving the existing v6 Argon2/AEAD policy unchanged.

## 3. Key Creation and Authorized Migration

- [x] 3.1 Apply the calibrated v4 profile during one-pass protected private-key import, preserving fresh per-packet salt/IV, the original passphrase, public bytes, bindings, capabilities, and canonical fingerprint; make any calibration, re-protection, verification, or commit failure reject the entire import without fallback or session start.
- [x] 3.2 Change protected pure-Rust key generation to apply the calibrated managed profile directly in memory before the only persistent serialization, avoiding an rPGP-default protected record and immediate S2K rework.
- [x] 3.3 Treat existing legacy and policy-v1 coded-224 records as migratable when they do not match policy v2; migrate only after successful all-packet authorization and do not rewrite an already compliant record.
- [x] 3.4 Add fault-injection and secret-safety tests proving calibration/preparation/serialization failures preserve the prior private record and expose no passphrase, private parameters, derived key, plaintext, or temporary unprotected record.

## 4. Correctness and Interoperability

- [x] 4.1 Add core tests for protected import, protected generation, fixed-profile migration, compliant no-op, wrong passphrase, mixed packet passphrases, unprotected keys, unchanged v6 behavior, transactional import failure, and existing-record rollback under policy v2.
- [x] 4.2 Add rPGP round-trip and GnuPG interoperability tests proving calibrated exports remain standard protected OpenPGP material, retain the same fingerprint and passphrase, and decrypt representative entries.
- [x] 4.3 Verify existing bridge and Flutter session-expiration behavior remains unchanged and no unlocked-key, derived-key, KeyStore/Keychain envelope, or durable plaintext cache is introduced.

## 5. Performance and Final Validation

- [x] 5.1 Build the production Android native library in release mode, confirm the stored encryption packet matches policy v2, and record cold preparation plus repeated decrypt samples separately.
- [x] 5.2 Demonstrate subsequent representative entry decrypt p95 below 800 ms on the reference Android device and confirm post-migration runs do not enter `sha1-checked`.
- [x] 5.3 Run Rust formatting, focused and workspace tests, strict linting, bridge/Flutter regression tests, and strict OpenSpec validation; record versions, packet profiles, timing evidence, and any excluded one-time legacy cost.
