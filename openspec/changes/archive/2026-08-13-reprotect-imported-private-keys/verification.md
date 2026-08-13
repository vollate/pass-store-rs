## Verification environment

- Date: 2026-08-13
- rPGP: `pgp 0.20.0`
- GnuPG: `2.5.21` with libgcrypt `1.12.2`
- Android device: PHK110, Android 16 / API 36, SM8475
- Android build fingerprint: `OnePlus/PHK110/OP5913L1:16/BP2A.250605.015/T.26c6ee8-56ebcf-56ebcc:user/release-keys`
- Android benchmark binary: `cargo ndk -t arm64-v8a build --release -p pars-core --example reprotect_android_benchmark`

## Desktop correctness and interoperability

- `cargo test --workspace -- --skip macos_clipboard_test` passed with an isolated temporary `GNUPGHOME`. The skipped pre-existing test requires live macOS clipboard interaction; all Rust unit, bridge, integration, and documentation tests otherwise passed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `flutter analyze` passed with no issues.
- Full `flutter test` passed: 162 tests. This includes deletion confirmation
  coverage proving `Display Name <email>` requires only `Display Name`, plus a
  390×844 viewport with a 320-pixel software-keyboard inset proving the
  confirmation field and delete action remain above the keyboard without a
  layout overflow.
- `PARS_RUN_GPG_INTEROP=1 cargo test -p pars-core --test rpgp_gnupg_interop_test -- --nocapture` passed all eight tests, including the non-optional low-cost legacy SHA-1 fixture and the GnuPG-generated coded-count-255 case.
- The maximum legacy fixture exported by GnuPG was inspected before import as two AES-128/CFB, iterated SHA-1 packets with coded count 255. After pure-Rust import, both packets were AES-256/CFB, iterated SHA-256 packets with coded count 224. GnuPG imported the result under the same passphrase and decrypted the interoperability entry with the unchanged fingerprint.

## Android release timing

The benchmark used a disposable private key and keyring under `/data/local/tmp`; it did not read or mutate application data. Coded count 255 decodes to 65,011,712 hashed octets per protected packet.

| Phase | Packet state | Wall time |
|---|---|---:|
| One-time import and re-protection | Two AES-128/SHA-1/coded-255 packets | 692 ms |
| Subsequent fingerprint-bound preparation | Two AES-256/SHA-256/coded-224 packets; `migrated=false` | 144 ms |
| Subsequent password-entry decryption | Managed encryption subkey | 67 ms |

The times are reference-device evidence, not CI thresholds.

## Post-migration SHA-1 profile

The device OEM exposed `simpleperf` but rejected hardware and software sampling events for the shell user, so the release binary was examined with NDK `lldb-server` and the same resolved function-regex probe in both phases:

`sha1_checked.*digest.*update`

- Legacy import: the probe hit immediately in `<sha1_checked::Sha1 as digest::digest::DynDigest>::update` after the source profile reported SHA-1/coded-255.
- Post-migration preparation: the operation completed in 141 ms while all three resolved `sha1_checked` update locations reported hit count `0`.

Together with persisted-packet inspection showing SHA-256/coded-224, this confirms subsequent preparation does not enter the legacy SHA-1 S2K path. Replacing or specializing `sha1-checked` remains a future optional optimization for the one-time compatibility path only.

## Secret-safety checks

- Imported source bytes are held in `SecretSlice`; its `Debug` implementation redacts parsed material and raw bytes.
- Serialized private armor is zeroized after the restrictive same-directory atomic write.
- Preparation/import/deletion responses contain fingerprints and sanitized failure kinds only; bridge payload logging remains disabled and `passphrase`, `password`, `armored_text`, `content`, and `private_key` remain declared secret fields.
- Fault tests verify failed preparation/permission/sync/rename preserves the existing private record and leaves no temporary secret file.
- No benchmark or profile output includes a passphrase, private-key bytes, decrypted secret parameters, or derived key.
