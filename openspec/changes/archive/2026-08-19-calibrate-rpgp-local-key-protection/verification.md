## Verification environment

- Date: 2026-08-15
- Rust: `rustc 1.98.0-nightly (31a9463c6 2026-05-25)`
- rPGP: `pgp 0.20.0`
- GnuPG: `2.5.21`, libgcrypt `1.12.2`
- Flutter: `3.44.2`
- Reference device: OnePlus PHK110, Android 16 / API 36, arm64-v8a
- Device build: `OnePlus/PHK110/OP5913L1:16/BP2A.250605.015/T.26c6ee8-56ebcf-56ebcc:user/release-keys`

## Stage attribution

The release benchmark reports backend construction, encrypted-file read,
message parse, private-key read/parse, private-packet S2K, PKESK recovery, and
payload decrypt/decompress separately. It never prints a passphrase, private
parameters, derived key material, plaintext, raw private-key material, salt, or
IV. The captured Android logs were also checked for the fixed fixture
passphrase and plaintext; neither occurred.

A desktop release run with the deterministic three-packet legacy SHA-1 coded-1
fixture produced:

- source packets: AES-256 CFB, SHA-1, coded count 1
- stored packets: AES-256 CFB, SHA-256, coded count 224 (the calibrated desktop
  result, bounded by the policy-v2 16 MiB ceiling)
- import and re-protection: 178 ms
- subsequent all-packet preparation: 118 ms, `migrated=false`
- repeated entry decrypt p95 over 10 samples: 51,046 microseconds
- warm decrypt S2K stage: approximately 27–30 ms
- warm key read/parse: approximately 0.13–0.19 ms
- warm PKESK recovery: approximately 0.03 ms
- warm payload decrypt/decompress: below 0.01 ms

Both desktop and Android measurements isolate private-packet S2K as the
performance-dominant stage of one decrypt. The one-time source S2K and migration
cost is reported separately and excluded from the subsequent-decrypt acceptance
result.

A later real-vault UI trace did reproduce a 13.67-second entry-open path, but
stage attribution showed that it was not one slow rPGP decrypt:

- private-key preparation: 229 ms
- session setup: 0 ms
- entry decrypt plus metadata handling: 13,440 ms
- approximately 220 serial entry decryptions at roughly 55–65 ms each

The amplification came from
`BridgeBackedRepository.readEntry()` -> `_rememberEntry()` -> `_saveMetadata()`
-> the former full Autofill refresh, which decrypted the entire vault to rebuild
matching metadata. The single-entry measurements above remain valid: all
measured non-S2K stages of each decrypt stayed below 1 ms, while repeating the
S2K-dominant decrypt hundreds of times created the UI delay. The follow-up
`use-path-first-autofill-index` change removes PGP access from default rebuild,
mutation, favorite, and recent flows and reserves exactly one decrypt for the
selected credential.

## Android release evidence

`flutter build apk --release --target-platform android-arm64` rebuilt the
production APK and release Rust bridge. The production APK SHA-256 is
`705a1e7e860ca65623444bf21f7d25351b73675fe9e633027fe64897d666197c`.
Its packaged `libpars_bridge.so` SHA-256 is
`e1e00da6f9d400d21dba7fac39b682ca2c2f6ef69e1770b7ffc49472602594bb`.

Because the production APK is intentionally not debuggable, device measurement
used a temporary debuggable Android wrapper containing:

- the same packaged release `libpars_bridge.so`, with the exact production hash
  above; and
- the benchmark compiled by `cargo ndk` with Rust's `release` profile.

The temporary wrapper allowed the release benchmark to run as the application
UID against an isolated child of the real app support directory:
`/data/user/0/top.vollate.pars_gui/files/pgp-policy-v2-benchmark`. The temporary
Gradle/JNI inputs were removed immediately after packaging. After measurement,
the benchmark keyring and fixture were deleted and the non-debuggable
production release APK was reinstalled. The real `files/pgp` record and password
store were not modified.

The clean import run recorded:

- backend creation: below 1 ms
- source primary and two subkeys: AES-256 CFB / SHA-1 / coded-1
- import, calibration, and re-protection: 320 ms
- policy metadata: version 2, coded count 217
- stored primary and two subkeys: AES-256 CFB / SHA-256 / coded-217
- decoded policy count: 13,107,200 bytes (12.5 MiB), within the 1–16 MiB bounds

Five separate cold-process policy-compliant preparations recorded 147, 147,
155, 147, and 161 ms. Every run reported `migrated=false`; cold preparation p95
was therefore 161 ms.

Thirty subsequent representative entry decrypts recorded:

- p95 total: **49,657 microseconds (49.657 ms)**, below the 800 ms requirement
- total observed range: 49.347–53.942 ms
- private-packet S2K observed range: 48.818–52.860 ms
- key read/parse: 0.307–0.780 ms
- encrypted read plus message parse: below 0.12 ms
- PKESK recovery: 0.083–0.133 ms
- payload decrypt/decompress: 0.010–0.056 ms

The authoritative stored packets and all post-migration preparation/decrypt
runs use SHA-256. Therefore rPGP's SHA-1 dispatch, including `sha1-checked`, is
not reachable in those runs. SHA-1 appears only in the separately timed source
fixture import.

## Correctness and interoperability

- Pure-Rust core tests cover deterministic calibration, RFC count
  quantization, floor/ceiling behavior, policy metadata reuse/recovery,
  calibrated import/generation, policy-v1 migration, policy-v2 no-op, v6
  preservation, wrong/mixed passphrases, transactional import rollback,
  existing-record rollback, and stage-separated decrypt.
- `PARS_RUN_GPG_INTEROP=1 cargo test -p pars-core --test
  rpgp_gnupg_interop_test -- --nocapture` passed all eight tests. Calibrated
  private exports retain standard protected OpenPGP encoding, fingerprint, and
  passphrase and remain usable by GnuPG.
- Bridge smoke tests passed all 18 tests.
- Flutter security/repository focused tests passed all 45 tests.
- Full Flutter suite passed all 166 tests.
- `cargo test --workspace -- --skip macos_clipboard_test` passed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `flutter analyze` passed.
- `openspec validate calibrate-rpgp-local-key-protection --strict` passed.

No bridge API or Flutter session-expiration behavior changed. No unlocked-key,
derived-key, KeyStore/Keychain private-key envelope, or durable plaintext cache
was added.
