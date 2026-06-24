# rPGP Mobile OpenPGP Roadmap

Goal: ship mobile PGP without requiring bundled GnuPG or an external OpenPGP
provider.

## Milestone 1: Commit Strategy And Documentation

- [x] Decide that Android and iOS use `pure_rust` first.
- [x] Document rPGP as the selected Rust OpenPGP implementation.
- [x] Keep system GnuPG as the CLI and desktop default.
- [x] Move bundled GnuPG mobile packaging to fallback status.

## Milestone 2: Backend Selection

- [ ] Make bridge PGP helpers return a trait object instead of `SystemGpgBackend`.
- [ ] Add request/config support for selecting `pure_rust`.
- [ ] Default Android and iOS GUI launches to `pure_rust`.
- [ ] Keep desktop GUI launches on system GnuPG unless config says otherwise.

## Milestone 3: rPGP Keyring

- [ ] Add `RpgpBackend` and an app-owned file keyring.
- [ ] Import public keys.
- [ ] Import private keys and derive/store public keys where possible.
- [ ] List keys with identity, fingerprint, and private-key availability.
- [ ] Export public keys.
- [ ] Export private keys after existing confirmation.
- [ ] Generate an unprotected OpenPGP key for onboarding.

## Milestone 4: Entry Crypto

- [ ] Resolve `.gpg-id` recipients against rPGP keyring.
- [ ] Encrypt entry content to binary `.gpg` output.
- [ ] Decrypt entry files using available private keys.
- [ ] Preserve existing entry parsing behavior after decryption.
- [ ] Return actionable errors for missing recipients and missing private keys.

## Milestone 5: Interoperability And Mobile Verification

- [ ] Add pure Rust tests that do not need system GnuPG.
- [ ] Add optional GnuPG interoperability tests.
- [ ] Run Rust workspace tests.
- [ ] Run Flutter repository tests.
- [ ] Build Android debug APK for device `7eaf4718`.
- [ ] Install and smoke launch on device `7eaf4718`.

## Commit Policy

Commit this roadmap before implementation. Commit the implementation once all
roadmap milestones are complete, using `--no-gpg-sign`.
