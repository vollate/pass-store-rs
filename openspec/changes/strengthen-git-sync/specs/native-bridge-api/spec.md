## MODIFIED Requirements

### Requirement: Bridge Git methods SHALL return command output DTOs

Bridge Git methods that run a Git command for display SHALL return `GitCommandOutputDto` containing command, stdout, stderr, exit code, and success flag when Git execution reaches the process boundary. Status summary, sync, history, branch listing, and identity methods SHALL return typed DTOs instead of text that Flutter parses. `run_git_args` SHALL accept one `command_line` string and SHALL tokenize and validate it in Rust.

Sources: `bridge/src/api.rs`, `core/src/gui/mod.rs`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Run arbitrary Git args uses validation

- **WHEN** `run_git_args` receives a command line
- **THEN** Rust tokenizes it and `GitOperationRequest::new` validates the tokens before execution

#### Scenario: Flutter does not split command lines

- **WHEN** the desktop advanced Git args sheet runs `config user.name "Ada Lovelace"`
- **THEN** Flutter sends the unsplit command line to the bridge
- **AND** the bridge runs Git with the argument `Ada Lovelace`

### Requirement: Bridge SHALL expose structured libgit2 operations for mobile Git

The bridge SHALL use libgit2-backed structured repository discovery, validation, initialization, clone, status, status summary, fetch, remote management, commit, pull, push, sync with in-memory rebase or merge, reset to upstream, history, remote branch listing and switching, and identity read and write on Android and iOS. It SHALL preserve existing CLI and working desktop system-Git paths. Mobile network operations SHALL accept optional HTTPS username and token and optional SSH key passphrase inputs. Mobile arbitrary Git args SHALL return `UnsupportedPlatform`; they SHALL NOT be interpreted as a partial libgit2 command language.

#### Scenario: Mobile arbitrary args are typed unsupported

- **GIVEN** target platform is Android or iOS
- **WHEN** `run_git_args` is called
- **THEN** the response contains an `UnsupportedPlatform` failure
- **AND** no system process is spawned

#### Scenario: Structured mobile Git returns normal DTOs

- **GIVEN** target platform is Android or iOS
- **WHEN** a supported status, summary, fetch, remote, commit, pull, push, sync, reset, history, branch, identity, init, or clone operation runs
- **THEN** the bridge returns the same sanitized result shape used on desktop
- **AND** transport credentials are not included in output

#### Scenario: Mobile sync does not spawn system Git

- **GIVEN** target platform is Android or iOS
- **WHEN** `git_sync` runs
- **THEN** commit, fetch, rebase or merge, and push use libgit2
- **AND** no system `git` executable is required

## ADDED Requirements

### Requirement: Bridge SHALL return typed Git status and sync outcomes

`git_status_summary` SHALL return optional branch, optional upstream, ahead, behind, changed, and conflicted counts, an operation state of none, rebasing, merging, or other, and an optional last-fetch time. `git_sync` SHALL accept a commit message, whether to commit pending changes, and an integration strategy of rebase or merge. It SHALL return whether it committed, the number of commits pulled, whether it pushed, whether uncommitted changes blocked integration, an optional conflict with backup branch name and conflicting paths, and the summary afterwards. Typed failures SHALL include `IdentityRequired`, `AuthenticationRequired`, and `SshPassphraseRequired` categories in addition to existing categories.

#### Scenario: Summary reports ahead and behind

- **GIVEN** the local branch is one commit ahead and two behind its upstream
- **WHEN** `git_status_summary` runs
- **THEN** it returns `ahead = 1` and `behind = 2`

#### Scenario: Conflict outcome names the backup branch

- **WHEN** `git_sync` stops on a rebase conflict
- **THEN** the result contains the backup branch name and the conflicting paths
- **AND** the error field is empty because a conflict is an outcome, not a failure

#### Scenario: Missing identity is a typed failure

- **GIVEN** no commit identity is configured
- **WHEN** `git_sync` needs to commit pending changes
- **THEN** it returns an `IdentityRequired` failure
- **AND** no fetch or push runs

### Requirement: Bridge Git credential inputs SHALL NOT be logged or returned

HTTPS usernames, tokens, and SSH key passphrases passed to bridge Git methods SHALL be used only for the operation's credential callbacks. They SHALL NOT appear in logs, returned command strings, stdout, stderr, or failure messages, and SHALL NOT be persisted by the bridge.

#### Scenario: Failed push hides the token

- **GIVEN** an HTTPS push with a token fails
- **WHEN** the failure is returned
- **THEN** the message contains the sanitized Git reason
- **AND** it does not contain the token

#### Scenario: Bridge does not persist credentials

- **WHEN** a Git operation with HTTPS credentials completes
- **THEN** the bridge has written no file containing the token
