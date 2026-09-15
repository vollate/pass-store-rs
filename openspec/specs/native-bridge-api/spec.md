# native-bridge-api Specification

## Purpose

Document the Flutter/Rust bridge API surface and error/response conventions.

## Requirements

### Requirement: Bridge SHALL expose the declared method table

The bridge SHALL expose methods listed in `SUPPORTED_METHODS`, including config, singular store lifecycle, entry, optional Git, app-state, contextual PGP setup, SSH management, and external URL operations. It SHALL omit multi-store list/select/default-fallback methods and general Flutter PGP export, append-to-`.gpg-id`, and delete methods.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`, `gui/bridge/bridge_config.toml`, `gui/lib/bridge/pars_bridge_api.dart`

#### Scenario: Method table matches generated API surface

- **WHEN** bridge smoke tests compare `SUPPORTED_METHODS`
- **THEN** the table equals the expected generated method list
- **AND** removed multi-store and permanent PGP-management methods are absent

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

The bridge SHALL expose contextual PGP key listing, material inspection from text and file sources, exact-key protected import, generation for new-store setup, fingerprint-bound private-key preparation, and one operation that initializes `.gpg-id` only when it is absent on the canonical store. Singular store status SHALL expose normalized recipient identifiers for exact-match repair filtering. It SHALL expose SSH key generate/import/export/delete and a GitHub SSH settings URL. PGP inspection and import SHALL return typed key kind, protection state, canonical fingerprint, and sanitized failures without returning secret material. The GUI bridge SHALL NOT expose general PGP export, deletion, legacy type-specific import, or arbitrary existing `.gpg-id` append.

Sources: `bridge/src/api.rs`, `core/src/key_management.rs`, `bridge/tests/bridge_smoke_test.rs`

#### Scenario: GitHub SSH settings returns fixed URL

- **WHEN** `open_github_ssh_settings` is called
- **THEN** the response URL is `https://github.com/settings/keys`

#### Scenario: PGP file inspection reads key bytes in Rust

- **GIVEN** a selected local file contains supported armored or binary PGP key material
- **WHEN** Flutter requests PGP file inspection
- **THEN** the bridge reads and inspects the file without returning key bytes to Flutter
- **AND** returns typed key metadata

#### Scenario: PGP import response identifies the imported key

- **GIVEN** inspected PGP material has canonical fingerprint `ABC`
- **WHEN** the corresponding contextual text or file import succeeds
- **THEN** the response contains a key record for fingerprint `ABC`
- **AND** identifies whether public or private material was imported

#### Scenario: PGP passphrase failure is typed and sanitized

- **GIVEN** a protected private PGP key is submitted with an incorrect passphrase
- **WHEN** the bridge validates contextual import
- **THEN** the response contains a passphrase validation failure kind
- **AND** contains neither the passphrase nor private key material

#### Scenario: Missing recipient file can be initialized contextually

- **GIVEN** the canonical store exists without `.gpg-id`
- **WHEN** contextual setup supplies one or more usable private-key fingerprints
- **THEN** the bridge writes the normalized recipients once
- **AND** a later call refuses to overwrite the existing recipient file

#### Scenario: Permanent PGP administration methods are absent

- **WHEN** generated Flutter key methods are inspected
- **THEN** they do not include PGP public/private export, PGP deletion, legacy type-specific import, or arbitrary recipient append
- **AND** SSH management methods remain available

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

### Requirement: Bridge SHALL expose structured libgit2 operations for mobile Git

The bridge SHALL use libgit2-backed structured repository discovery, validation, initialization, clone, status, remote management, commit, pull, and push on Android and iOS. It SHALL preserve existing CLI and working desktop system-Git paths. Mobile arbitrary Git args SHALL return `UnsupportedPlatform`; they SHALL NOT be interpreted as a partial libgit2 command language.

#### Scenario: Mobile arbitrary args are typed unsupported

- **GIVEN** target platform is Android or iOS
- **WHEN** `run_git_args` is called
- **THEN** the response contains an `UnsupportedPlatform` failure
- **AND** no system process is spawned

#### Scenario: Structured mobile Git returns normal DTOs

- **GIVEN** target platform is Android or iOS
- **WHEN** a supported status, remote, commit, pull, push, init, or clone operation runs
- **THEN** the bridge returns the same sanitized structured result shape used by Flutter
- **AND** transport credentials are not included in output

### Requirement: Bridge store lifecycle APIs SHALL use one optional canonical store

The bridge SHALL expose singular app-state inspection plus create, registration-only import, clone, disconnect, and app-managed delete operations for one canonical store. Platform/Dart code SHALL own the rollback-capable staged filesystem transaction and explicit Git decision; Rust Import SHALL inspect and register only the finalized root and SHALL NOT initialize Git. App-state DTOs SHALL contain one optional store status and SHALL NOT expose selected-store IDs or a list of selectable stores. Store mutation requests SHALL NOT accept `set_default`.

#### Scenario: App state returns no canonical store

- **GIVEN** config contains no canonical store path
- **WHEN** singular app-state inspection runs
- **THEN** the store field is absent
- **AND** lifecycle state requires store setup

#### Scenario: Store mutation establishes one canonical root

- **GIVEN** config contains no canonical store
- **WHEN** Create, Import registration, or Clone succeeds for root `/vault`
- **THEN** singular app state reports `/vault`
- **AND** no alternate selectable store is returned

#### Scenario: Disconnect clears without deleting external files

- **GIVEN** `/external/vault` is the canonical externally owned root
- **WHEN** bridge disconnect succeeds
- **THEN** config has no canonical root
- **AND** the external directory is not recursively deleted

#### Scenario: Multi-store bridge operations are absent

- **WHEN** generated bridge methods are inspected
- **THEN** list-stores and select-store operations are absent
- **AND** no operation automatically chooses another configured root

### Requirement: Bridge store inspection SHALL return typed Git capability

Canonical store and staged import inspection SHALL return typed Git mode distinguishing disabled, local, remote, and invalid metadata. The platform/Dart staged transaction SHALL consume an explicit decision for absent Git and SHALL return typed validation failures without raw shell output or private paths in ordinary user messages. Rust registration SHALL accept only `config_path` and finalized `root`.

#### Scenario: Missing Git is typed as disabled

- **GIVEN** a valid password-store root contains no `.git`
- **WHEN** bridge store inspection runs
- **THEN** Git mode is disabled
- **AND** store readiness can still be true

#### Scenario: Valid Git without remote is typed as local

- **GIVEN** a valid Git work tree has no remotes
- **WHEN** bridge store inspection runs
- **THEN** Git mode is local
- **AND** missing remote is not returned as an onboarding failure

#### Scenario: Invalid Git remains distinguishable

- **GIVEN** `.git` is present but the root is not a usable work tree
- **WHEN** bridge store or staged-import inspection runs
- **THEN** Git mode is invalid
- **AND** the response does not classify it as disabled

## Needs Verification

- The onboarding did not inspect generated FRB files exhaustively; bridge API
  facts are taken from source API, tooling config, and smoke tests.
- Clipboard semantics differ by layer: bridge `copy_entry_password` returns a
  password string, while Flutter UI writes it to the system clipboard.
