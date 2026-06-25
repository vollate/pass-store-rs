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

The bridge SHALL expose key listing, key material detection, PGP key
generate/import/export, `.gpg-id` append, SSH key generate/import/export, and a
GitHub SSH settings URL.

Sources: `bridge/src/api.rs`, `core/src/key_management.rs`,
`bridge/tests/bridge_smoke_test.rs`

#### Scenario: GitHub SSH settings returns fixed URL

- WHEN `open_github_ssh_settings` is called
- THEN the response URL is `https://github.com/settings/keys`

### Requirement: Bridge tooling config SHALL mark secret fields

Bridge tooling config SHALL identify secret fields so request/response payload
logging can avoid password, content, armored text, and private key fields.

Sources: `gui/bridge/bridge_config.toml`

#### Scenario: Secret fields are configured

- WHEN bridge tooling config is inspected
- THEN `secret_fields` includes `password`, `content`, `armored_text`, and
  `private_key`

## Needs Verification

- The onboarding did not inspect generated FRB files exhaustively; bridge API
  facts are taken from source API, tooling config, and smoke tests.
- Clipboard semantics differ by layer: bridge `copy_entry_password` returns a
  password string, while Flutter UI writes it to the system clipboard.
