# rPGP Mobile OpenPGP Roadmap

Status: completed

Goal: ship mobile PGP without requiring bundled GnuPG or an external OpenPGP
provider.

## Milestone 1: Commit Strategy And Documentation

- [x] Decide that Android and iOS use `pure_rust` first.
- [x] Document rPGP as the selected Rust OpenPGP implementation.
- [x] Keep system GnuPG as the CLI and desktop default.
- [x] Move bundled GnuPG mobile packaging to fallback status.

## Milestone 2: Backend Selection

- [x] Make bridge PGP helpers return a trait object instead of `SystemGpgBackend`.
- [x] Add request/config support for selecting `pure_rust`.
- [x] Default Android and iOS GUI launches to `pure_rust`.
- [x] Keep desktop GUI launches on system GnuPG unless config says otherwise.

## Milestone 3: rPGP Keyring

- [x] Add `RpgpBackend` and an app-owned file keyring.
- [x] Import public keys.
- [x] Import private keys and derive/store public keys where possible.
- [x] List keys with identity, fingerprint, and private-key availability.
- [x] Export public keys.
- [x] Export private keys after existing confirmation.
- [x] Generate an unprotected OpenPGP key for onboarding.

## Milestone 4: Entry Crypto

- [x] Resolve `.gpg-id` recipients against rPGP keyring.
- [x] Encrypt entry content to binary `.gpg` output.
- [x] Decrypt entry files using available private keys.
- [x] Preserve existing entry parsing behavior after decryption.
- [x] Return actionable errors for missing recipients and missing private keys.

## Milestone 5: Interoperability And Mobile Verification

- [x] Add pure Rust tests that do not need system GnuPG.
- [x] Add optional GnuPG interoperability tests.
- [x] Run Rust workspace tests.
- [x] Run Flutter repository tests.
- [x] Build Android debug APK for device `7eaf4718`.
- [x] Install and smoke launch on device `7eaf4718`.

Optional GnuPG interoperability tests run with `PARS_RUN_GPG_INTEROP=1 cargo
test -p pars-core --test rpgp_gnupg_interop_test`.

## Commit Policy

Commit this roadmap before implementation. Commit the implementation once all
roadmap milestones are complete, using `--no-gpg-sign`.
