# pgp-and-key-management Specification

## Purpose

Document implemented PGP backend, `.gpg-id`, PGP key, SSH key, and key import
behavior.

## Requirements

### Requirement: CLI PGP client SHALL resolve key metadata through GPG

The CLI-oriented `PGPClient` SHALL resolve fingerprints, usernames, and emails
by invoking the configured PGP executable with `--list-keys --with-colons` for
each configured identity.

Sources: `core/src/pgp/utils.rs`, `core/src/pgp/mod.rs`,
`cli/src/command/init.rs`

#### Scenario: Init displays resolved key user information

- WHEN `pars init` receives GPG IDs
- THEN it creates a temporary PGP client
- AND uses resolved usernames and emails in the init message

### Requirement: PGP backend config SHALL support system, bundled, and pure-rust selections

The config schema SHALL store `pgp_config.backend` with supported values
`system_gpg`, `bundled`, and `pure_rust`. Defaults SHALL select `system_gpg`.
Bundled backend SHALL require `bundled_gpg_path`; system backend SHALL use
`system_gpg_path` when present or default to `gpg2`.

Sources: `core/src/config/cli.rs`, `core/src/pgp/backend.rs`,
`core/tests/pgp_backend_test.rs`, `config/cli/pars_config.toml`

#### Scenario: Default config selects system GPG

- WHEN `ParsConfig::default()` is created
- THEN `pgp_config.backend` is `SystemGpg`

#### Scenario: Bundled backend selects bundled path

- GIVEN backend is `bundled`
- AND `bundled_gpg_path` is configured
- WHEN a `SystemGpgBackend` is created from config
- THEN its executable is the bundled path

### Requirement: Pure Rust backend SHALL maintain file-based keyrings and support entry crypto

The pure Rust backend SHALL require `keyring_home`, create public/private
keyring directories, generate OpenPGP keys, import/export public and private
keys, list keys, validate recipients, encrypt entry content, and decrypt entry
content.

Sources: `core/src/pgp/rpgp_backend.rs`, `core/src/gui/mod.rs`,
`bridge/tests/bridge_smoke_test.rs`, `core/tests/rpgp_gnupg_interop_test.rs`

#### Scenario: Pure Rust bridge encrypts and decrypts an entry

- GIVEN config selects `pure_rust`
- AND the store `.gpg-id` contains a generated pure-rust key fingerprint
- WHEN bridge insert writes an entry
- AND bridge read reads that entry
- THEN the parsed password and fields match the inserted plaintext

### Requirement: `.gpg-id` recipient lookup SHALL prefer nearest ancestor file

Recipient lookup SHALL search from the target path toward the store root and
return the nearest `.gpg-id` file's non-empty lines.

Sources: `core/src/util/fs_util.rs`, `core/src/pgp/backend.rs`,
`core/tests/pgp_backend_test.rs`

#### Scenario: Subdirectory `.gpg-id` overrides root `.gpg-id`

- GIVEN root `.gpg-id` contains `alice@example.com`
- AND `work/.gpg-id` contains `team@example.com`
- WHEN recipients are validated for `work/github.gpg`
- THEN `team@example.com` is returned

#### Scenario: Empty backend recipient list is invalid

- GIVEN the nearest `.gpg-id` contains only comments or blank lines
- WHEN backend validation runs
- THEN it returns an invalid `.gpg-id` error

### Requirement: Bridge PGP key management SHALL generate, import, list, and export keys

The bridge SHALL expose methods to list keys, generate PGP keys, import public
PGP keys, import private PGP keys from text or file, export public PGP keys, and
export private PGP keys.

Sources: `bridge/src/api.rs`, `core/src/pgp/backend.rs`,
`bridge/tests/bridge_smoke_test.rs`, `gui/lib/services/key_repository.dart`

#### Scenario: Private PGP export requires confirmation

- GIVEN a fingerprint `ABC`
- WHEN private PGP export is requested
- THEN confirmation must equal `EXPORT PRIVATE KEY ABC`
- OTHERWISE the bridge returns a validation error

#### Scenario: Import type must match requested PGP import

- GIVEN pasted key material is detected as PGP public or private
- WHEN the requested import kind does not match the detected material
- THEN the bridge returns a validation error

### Requirement: GUI-facing PGP key management SHALL delete local PGP keys

The GUI-facing key-management API SHALL support deleting a local PGP key by
fingerprint through the configured PGP backend. Deletion SHALL remove local
public key material and local private key material for that fingerprint when
present, and SHALL report an error when the key cannot be found or cannot be
deleted.

Sources: `core/src/pgp/backend.rs`, `core/src/pgp/rpgp_backend.rs`,
`bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete PGP key by fingerprint

- GIVEN a PGP key exists in the configured backend
- WHEN the GUI-facing delete PGP key API is called with that fingerprint
- THEN the key is removed from subsequent key listings
- AND local private key material for that fingerprint is removed when it exists

#### Scenario: Missing PGP key deletion reports an error

- GIVEN no local PGP key matches fingerprint `ABC`
- WHEN the GUI-facing delete PGP key API is called with fingerprint `ABC`
- THEN the API returns a key-management error

### Requirement: SSH key management SHALL operate without external ssh-keygen for generated ed25519 keys

The core key management layer SHALL generate OpenSSH ed25519 keys directly,
write private keys with private permissions on Unix, write `.pub` public keys,
compute `SHA256:` fingerprints, list `.pub` keys, import unencrypted OpenSSH
ed25519 private keys, and export public/private SSH keys.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`, `gui/lib/services/key_repository.dart`

#### Scenario: Generated SSH key creates private and public files

- WHEN an SSH ed25519 key named `mobile-key` is generated
- THEN `<ssh_dir>/mobile-key` exists
- AND `<ssh_dir>/mobile-key.pub` exists
- AND the fingerprint starts with `SHA256:`

#### Scenario: Private SSH export requires confirmation

- GIVEN key name `github-mobile`
- WHEN private SSH export is requested
- THEN confirmation must equal `EXPORT PRIVATE KEY github-mobile`

### Requirement: GUI-facing SSH key management SHALL delete local SSH keys

The GUI-facing key-management API SHALL support deleting a local SSH key by key
name from the configured SSH directory. Deletion SHALL remove both the private
key file and matching `.pub` public key file when present, and SHALL report an
error when neither file exists.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete SSH key by name

- GIVEN SSH key files `mobile-key` and `mobile-key.pub` exist in the configured
  SSH directory
- WHEN the GUI-facing delete SSH key API is called with name `mobile-key`
- THEN both files are removed
- AND subsequent SSH key listings do not include `mobile-key`

#### Scenario: Missing SSH key deletion reports an error

- GIVEN no SSH key files exist for name `missing-key`
- WHEN the GUI-facing delete SSH key API is called with name `missing-key`
- THEN the API returns a key-management error

### Requirement: Key material detection SHALL classify supported pasted keys

Key material detection SHALL recognize PGP public keys, PGP private keys, and
SSH private keys by supported BEGIN/END markers and SHALL reject unsupported
text without echoing invalid private key text in the error.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`

#### Scenario: PGP public text is classified

- GIVEN text with `BEGIN PGP PUBLIC KEY BLOCK` and matching end marker
- WHEN detection runs
- THEN the result is `pgp_public`

#### Scenario: Invalid private key text is not echoed

- GIVEN incomplete private key text
- WHEN detection rejects it
- THEN the error string does not include the invalid private text

### Requirement: Selected PGP keys SHALL be appended to root `.gpg-id` once

Adding a PGP key to the selected store SHALL create the store root if needed,
append the normalized fingerprint to root `.gpg-id`, preserve an existing final
line, and avoid duplicate entries.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`

#### Scenario: Duplicate selected key is not appended twice

- GIVEN `.gpg-id` already contains a fingerprint
- WHEN the same fingerprint is added twice
- THEN `.gpg-id` contains one copy of that fingerprint

## Needs Verification

- CLI recipient lookup does not filter comment lines before constructing
  `PGPClient`, while backend validation does. Intended `.gpg-id` comment support
  across CLI and GUI needs verification.
- System GPG import methods currently return empty fingerprints after import;
  the GUI record name may therefore fall back to an empty fingerprint. Intended
  post-import fingerprint resolution needs verification.
- Pure Rust backend accepts passphrases during key generation, but decryption
  currently attempts empty-password secret-key decryption. Encrypted private-key
  behavior needs verification.
