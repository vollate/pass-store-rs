# native-bridge-api Specification

## Purpose

Document the Flutter/Rust bridge API surface and error/response conventions.

## Requirements

### Requirement: Bridge SHALL expose the declared method table

The bridge SHALL expose the methods listed in `SUPPORTED_METHODS`, including
config, store, entry, Git, app-state, PGP key, SSH key, and external URL
operations.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/bridge/bridge_config.toml`, `gui/lib/bridge/pars_bridge_api.dart`

#### Scenario: Method table matches generated API surface

- WHEN bridge smoke tests compare `SUPPORTED_METHODS`
- THEN the table equals the expected generated method list

### Requirement: Bridge responses SHALL carry typed errors instead of throwing Rust panics

Bridge async methods SHALL return response DTOs containing either result data or
an optional `BridgeFailure`. Failure categories SHALL map config, store, PGP,
Git, clipboard, validation, conflict, and unsupported platform errors.

Sources: `bridge/src/api.rs`, `gui/test/pars_bridge_api_test.dart`

#### Scenario: Conflict preserves kind and path

- GIVEN a Rust core conflict for an existing entry
- WHEN it is converted to bridge failure
- THEN category is `Conflict`
- AND `conflict_kind` and `path` are populated

### Requirement: Bridge config methods SHALL load, save, and configure TOML config

The bridge SHALL load config as pretty TOML, save supplied TOML after parsing it
as `ParsConfig`, and configure selected PGP backend fields.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`core/src/config/cli.rs`

#### Scenario: Configure pure-rust backend writes config

- WHEN `configure_pgp_backend` is called with backend `pure_rust`
- AND `keyring_home` is provided
- THEN config is saved with backend `pure_rust`
- AND `keyring_home` is written

### Requirement: Bridge entry methods SHALL delegate to GUI core APIs and selected PGP backend

Bridge entry operations SHALL create `EntryRef` values from root/path, choose a
PGP backend from config and optional executable override, and expose list, read,
copy password, insert, generate, edit, move, and delete operations.

Sources: `bridge/src/api.rs`, `core/src/gui/mod.rs`,
`bridge/tests/bridge_smoke_test.rs`, `core/tests/gui_api_test.rs`

#### Scenario: Copy entry password returns parsed first-line password

- GIVEN bridge `copy_entry_password` can read an entry
- WHEN the entry plaintext is parsed
- THEN the response contains the entry path and password
- AND the bridge itself does not write to the system clipboard

### Requirement: Bridge Git methods SHALL return command output DTOs

Bridge Git methods SHALL return `GitCommandOutputDto` containing command,
stdout, stderr, exit code, and success flag when Git execution reaches the
process boundary.

Sources: `bridge/src/api.rs`, `core/src/gui/mod.rs`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Run arbitrary Git args uses validation

- WHEN `run_git_args` receives args
- THEN `GitOperationRequest::new` validates them before execution

### Requirement: Bridge key methods SHALL cover PGP and SSH key operations

The bridge SHALL expose key listing, PGP key-material inspection from text and
file sources, source-independent PGP import with exact-key passphrase
validation, PGP key generate/export, `.gpg-id` append, SSH key
generate/import/export, and a GitHub SSH settings URL. PGP inspection and import
responses SHALL return typed key kind, protection state, canonical fingerprint,
and sanitized failures needed by Flutter without returning secret material.

Sources: `bridge/src/api.rs`, `core/src/key_management.rs`,
`bridge/tests/bridge_smoke_test.rs`

#### Scenario: GitHub SSH settings returns fixed URL

- WHEN `open_github_ssh_settings` is called
- THEN the response URL is `https://github.com/settings/keys`

#### Scenario: PGP file inspection reads key bytes in Rust

- GIVEN a selected local file contains supported armored or binary PGP key
  material
- WHEN Flutter requests PGP file inspection
- THEN the bridge reads and inspects the file without returning its key bytes to
  Flutter
- AND returns typed key metadata

#### Scenario: PGP import response identifies the imported key

- GIVEN inspected PGP material has canonical fingerprint `ABC`
- WHEN the corresponding text or file import succeeds
- THEN the response contains a key record for fingerprint `ABC`
- AND identifies whether public or private material was imported

#### Scenario: PGP passphrase failure is typed and sanitized

- GIVEN a protected private PGP key is submitted with an incorrect passphrase
- WHEN the bridge validates the import request
- THEN the response contains a passphrase validation failure kind
- AND contains neither the passphrase nor private key material

### Requirement: Bridge tooling config SHALL mark secret fields

Bridge tooling config SHALL identify secret fields so request/response payload
logging can avoid passwords, PGP passphrases, content, armored key text, and
private key fields.

Sources: `gui/bridge/bridge_config.toml`

#### Scenario: Secret fields are configured

- WHEN bridge tooling config is inspected
- THEN `secret_fields` includes `password`, `passphrase`, `content`,
  `armored_text`, and `private_key`

### Requirement: Bridge private-key preparation SHALL be transactional and sanitized

The bridge SHALL make pure-Rust private-key re-protection part of protected
private import and SHALL expose a fingerprint-bound operation for preparing an
existing private key before a PGP session starts. Success SHALL be returned only
after the protected keyring record is committed or confirmed compliant.
Failures SHALL distinguish missing/incorrect passphrase, unsupported packet
protection, and local re-protection or commit failure without returning secret
input.

#### Scenario: Protected import responds after re-protection commit

- **GIVEN** protected private-key material and its correct passphrase are sent
  through the typed import API for the pure-Rust backend
- **WHEN** the source packets require managed re-protection
- **THEN** the bridge returns the imported key record only after the protected
  replacement has been committed
- **AND** the response contains no passphrase, private-key bytes, or derived
  material

#### Scenario: Existing-key preparation is fingerprint-bound

- **GIVEN** private keys `ABC` and `DEF` exist in the pure-Rust keyring
- **WHEN** the bridge preparation operation receives fingerprint `DEF` and its
  passphrase
- **THEN** it validates and, when necessary, migrates only key `DEF`
- **AND** it returns the backend-confirmed fingerprint `DEF`

#### Scenario: Re-protection failure is typed and sanitized

- **GIVEN** a pure-Rust private import or existing-key preparation cannot safely
  re-protect all required packets
- **WHEN** the bridge maps the core failure
- **THEN** the response contains a stable typed failure kind suitable for
  localized Flutter messaging
- **AND** its message contains neither the passphrase nor private-key material

#### Scenario: System GPG retains native key management

- **GIVEN** the selected backend is system GPG or bundled GPG
- **WHEN** protected private-key import succeeds
- **THEN** the bridge does not rewrite the material using the pure-Rust managed
  profile
- **AND** the configured GPG implementation remains responsible for its local
  private-key protection

### Requirement: Bridge PGP deletion SHALL report verified secret-material state

The bridge PGP deletion operation SHALL return a structured result containing
the backend-confirmed fingerprint, whether private material existed, whether
the private record is confirmed absent, and whether the public record is
confirmed absent. It SHALL distinguish a total deletion failure from a partial
result where private material is gone but public-record cleanup failed, without
requiring or returning the private-key passphrase.

#### Scenario: Complete deletion returns confirmed absence

- **GIVEN** a local PGP key has public and managed private records
- **WHEN** deletion removes both records
- **THEN** the bridge returns the canonical fingerprint with private and public
  absence confirmed
- **AND** it returns no deletion error

#### Scenario: Private deletion failure is not reported as success

- **GIVEN** the backend cannot remove a local managed private record
- **WHEN** the bridge maps the deletion outcome
- **THEN** it returns a typed PGP deletion failure
- **AND** it does not claim that private material is absent

#### Scenario: Public cleanup failure preserves the private-absent result

- **GIVEN** the backend has removed and verified absence of the private record
- **WHEN** its public-record removal fails
- **THEN** the bridge returns a result with private absence confirmed and public
  absence unconfirmed
- **AND** it returns a typed public-cleanup error suitable for localized GUI
  messaging

## Needs Verification

- The onboarding did not inspect generated FRB files exhaustively; bridge API
  facts are taken from source API, tooling config, and smoke tests.
- Clipboard semantics differ by layer: bridge `copy_entry_password` returns a
  password string, while Flutter UI writes it to the system clipboard.
