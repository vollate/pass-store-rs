## ADDED Requirements

### Requirement: Structured GUI and mobile Git SHALL use libgit2 without emulating arbitrary args

GUI/mobile repository discovery, validation, initialization, clone, status, remotes, commit, pull, and push SHALL use Rust libgit2 when a system Git executable is unavailable. CLI behavior and working desktop system-Git execution SHALL remain unchanged. HTTPS operations SHALL preserve default certificate verification. SSH operations SHALL use explicit app-managed private-key paths through credential callbacks and SHALL NOT log key material or passphrases. Arbitrary `run_git_args` SHALL return a typed Unsupported result on Android and iOS, and Flutter SHALL not expose an enabled Advanced Git args action there.

#### Scenario: Mobile structured status does not spawn system Git

- **GIVEN** the GUI runs on Android or iOS with a valid repository
- **WHEN** status is requested
- **THEN** libgit2 inspects the repository
- **AND** no system `git` executable is required

#### Scenario: HTTPS clone keeps certificate verification

- **GIVEN** the user clones an HTTPS remote on mobile
- **WHEN** libgit2 establishes transport
- **THEN** default certificate verification remains enabled
- **AND** no callback accepts an invalid certificate unconditionally

#### Scenario: SSH clone uses app-managed key path

- **GIVEN** an SSH remote and an explicitly selected app-managed private-key path
- **WHEN** libgit2 requests credentials
- **THEN** the credential callback uses that key path
- **AND** logs and errors contain no private key material or passphrase

#### Scenario: Arbitrary args are unsupported on mobile

- **GIVEN** the GUI runs on Android or iOS
- **WHEN** arbitrary Git args are requested
- **THEN** the bridge returns a typed Unsupported result
- **AND** Flutter does not present the action as executable

### Requirement: GUI password stores SHALL support disabled, local, remote, and invalid Git modes

GUI lifecycle and repository layers SHALL distinguish an intentional password store without Git, a valid local Git work tree without a remote, valid Git with a remote, and present-but-invalid Git metadata. Store readiness SHALL NOT require Git or a remote. Git commands and optional mutation commits SHALL NOT be dispatched while Git is disabled.

#### Scenario: No Git is a valid local-only mode

- **GIVEN** the canonical password store contains no `.git`
- **WHEN** GUI Git capability is inspected
- **THEN** Git mode is disabled
- **AND** Vault entry operations remain enabled
- **AND** no sync failure is synthesized

#### Scenario: Local Git does not require a remote

- **GIVEN** the canonical store is a valid Git work tree with no remotes
- **WHEN** GUI Git capability is inspected
- **THEN** Git mode is local
- **AND** local status and commit operations may be enabled
- **AND** pull and push remain unavailable until a remote is configured

#### Scenario: Remote Git enables synchronization

- **GIVEN** the canonical store is valid Git with a configured remote
- **WHEN** GUI Git capability is inspected
- **THEN** Git mode is remote
- **AND** supported pull, push, and remote status operations may be enabled

#### Scenario: Invalid Git is not silently disabled

- **GIVEN** `.git` exists but the canonical root is not a valid work tree
- **WHEN** GUI Git capability is inspected
- **THEN** Git mode is invalid
- **AND** the user receives a repairable error instead of a local-only status

### Requirement: Store import SHALL preserve Git or require an explicit missing-Git decision

A staged import with valid Git metadata SHALL preserve it without initialization. If `.git` is absent, the GUI SHALL explain possible local-only or provider-hidden metadata and require Initialize Git, Continue without Git, or Cancel before finalization. If `.git` is present but invalid, Import SHALL fail without running `git init`.

#### Scenario: Existing history is not replaced

- **GIVEN** staged import is a valid Git work tree with commits and a remote
- **WHEN** Import finalizes
- **THEN** no Git initialization command runs
- **AND** the imported history, branch, and remote remain available

#### Scenario: Initialization is explicit and destination-only

- **GIVEN** staged import has no `.git`
- **WHEN** the user chooses Initialize Git
- **THEN** `git init` runs only in the staged destination
- **AND** the selected source folder is not modified
- **AND** no remote or SSH prerequisite is added automatically

#### Scenario: Declining initialization preserves local-only use

- **GIVEN** staged import has no `.git`
- **WHEN** the user chooses Continue without Git
- **THEN** the store is finalized with Git disabled
- **AND** encryption, Vault, and Autofill remain available

#### Scenario: Invalid copied Git is not reinitialized

- **GIVEN** staged import contains invalid `.git` metadata
- **WHEN** Git validation fails
- **THEN** Import aborts
- **AND** `git init` is not offered as a way to overwrite the invalid metadata

### Requirement: Git enablement SHALL be available after local-only setup

Settings SHALL let the user initialize Git for the canonical local-only password store without requiring a remote. Successful initialization SHALL transition Git mode to local; remote and SSH configuration SHALL remain separate optional actions.

#### Scenario: Enable Git creates local mode

- **GIVEN** the canonical store has Git disabled
- **WHEN** the user confirms Enable Git and initialization succeeds
- **THEN** the store becomes a valid local Git work tree
- **AND** Git mode becomes local
- **AND** the user is not required to add a remote

#### Scenario: Failed initialization preserves disabled mode

- **GIVEN** the canonical store has Git disabled
- **WHEN** Git initialization fails
- **THEN** existing password-store files remain usable
- **AND** Git mode remains disabled
- **AND** a sanitized failure is shown

## MODIFIED Requirements

### Requirement: Flutter repository SHALL derive Git status and remote operations

The Flutter bridge-backed repository SHALL first inspect canonical store Git mode. For disabled mode it SHALL skip Git commands and expose a neutral disabled status. For local or remote mode it SHALL classify Git status as clean, need-pull, uncommitted, or sync-failed based on bridge output. It SHALL parse and mutate remotes only for valid Git and SHALL enable pull/push only when a suitable remote exists. Invalid Git SHALL remain distinguishable from disabled Git.

Sources: `gui/lib/services/bridge_backed_repository.dart`, `gui/lib/services/git_repository.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Disabled Git skips status command

- **GIVEN** app-state inspection reports Git mode disabled
- **WHEN** repository refresh runs
- **THEN** no `git status` command is invoked
- **AND** repository status is Git disabled rather than sync failed

#### Scenario: Uncommitted status is detected

- **GIVEN** valid local or remote Git status stdout includes a non-branch line
- **WHEN** repository refresh parses status
- **THEN** `RepoGitStatus.uncommitted` is set

#### Scenario: Remote push URL defaults to fetch URL when absent

- **GIVEN** valid remote output has no push URL for a remote
- **WHEN** remotes are returned
- **THEN** push URL equals fetch URL

#### Scenario: Missing remote disables pull and push without failing local Git

- **GIVEN** Git mode is local
- **WHEN** repository operations are exposed
- **THEN** local status remains available
- **AND** pull and push are unavailable until remote configuration succeeds
