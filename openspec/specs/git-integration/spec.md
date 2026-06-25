# git-integration Specification

## Purpose

Document implemented Git behavior in CLI, core GUI API, bridge, and Flutter
repository layers.

## Requirements

### Requirement: CLI mutating password-store commands SHALL automatically commit

CLI commands that mutate the password store SHALL run `git add -A` and
`git commit -m <message>` after successful mutation. Implemented commands are
init, insert, generate, remove, move, copy, and edit when edit content changed.

Sources: `cli/src/command/init.rs`, `cli/src/command/insert.rs`,
`cli/src/command/generate.rs`, `cli/src/command/rm.rs`,
`cli/src/command/mv.rs`, `cli/src/command/cp.rs`,
`cli/src/command/edit.rs`, `core/src/git/mod.rs`,
`core/src/git/commit.rs`

#### Scenario: Insert commits on success

- GIVEN insert writes an encrypted entry
- WHEN the command wrapper receives a successful insert result
- THEN it commits with message `Insert password <path>`

#### Scenario: Edit skips commit when content unchanged

- GIVEN edit returns `false`
- WHEN the command wrapper completes
- THEN it does not call Git commit

### Requirement: CLI init SHALL initialize Git repository when missing

After initializing a password store, CLI init SHALL run `git init` when the
store root has no `.git` directory, then commit the init change.

Sources: `cli/src/command/init.rs`, `core/src/git/mod.rs`,
`core/src/git/commit.rs`

#### Scenario: First init creates Git repository

- GIVEN the store root does not contain `.git`
- WHEN CLI init completes entry initialization
- THEN it runs `git init`
- AND commits with an init message containing configured key fingerprints

### Requirement: CLI `git` command SHALL execute Git in the password store root

The CLI `git` subcommand SHALL pass all trailing args to the configured Git
executable and set the password store root as current directory.

Sources: `cli/src/parser/sub_command.rs`, `cli/src/command/git.rs`,
`core/src/operation/git.rs`

#### Scenario: Git passthrough inherits stdio

- WHEN `pars git <args>` is executed
- THEN the configured Git executable runs with `<args>`
- AND stdin, stdout, and stderr are inherited
- AND failure returns a Git error

### Requirement: GUI Git API SHALL reject shell syntax in arbitrary Git args

GUI-facing Git args SHALL be non-empty, SHALL not include the literal `git`
program name, and SHALL reject shell syntax such as `$(`, `;`, `|`, `&`, `>`,
`<`, backticks, or newlines.

Sources: `core/src/gui/mod.rs`, `core/tests/gui_api_test.rs`,
`bridge/src/api.rs`

#### Scenario: Plain Git args are accepted

- WHEN args are `pull --rebase`
- THEN a `GitOperationRequest` is created successfully

#### Scenario: Shell syntax is rejected

- WHEN args contain `;`, `|`, `&&`, `>`, or `$()`
- THEN validation fails with a shell-syntax error

### Requirement: GUI Git API SHALL preserve command output and status

GUI-facing Git execution SHALL return the command string, stdout, stderr,
process exit code, and success flag rather than failing solely because Git
returns a non-zero status.

Sources: `core/src/gui/mod.rs`, `core/tests/gui_api_test.rs`,
`bridge/src/api.rs`

#### Scenario: Failed Git status returns output object

- GIVEN the selected directory is not a Git repository
- WHEN `git status` is executed through GUI Git args
- THEN the response includes `success=false`
- AND stderr contains Git's failure output

### Requirement: Bridge SHALL expose standard Git operations

The bridge SHALL expose `git_status`, `git_pull`, `git_push`, `git_commit`, and
`run_git_args`. Standard methods SHALL expand to `status --short --branch`,
`pull`, `push`, and `commit -m <message>` respectively.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/lib/services/bridge_backed_repository.dart`

#### Scenario: Git status command is fixed

- WHEN bridge `git_status` is called
- THEN it executes `git status --short --branch`

#### Scenario: Git commit command uses supplied message

- WHEN bridge `git_commit` is called with `Sync passwords`
- THEN it executes `git commit -m "Sync passwords"`

### Requirement: Flutter repository SHALL derive Git status and remote operations

The Flutter bridge-backed repository SHALL classify Git status as clean,
need-pull, uncommitted, or sync-failed based on bridge status output. It SHALL
list remotes by parsing `git remote -v` output and expose add/edit/remove remote
operations through arbitrary Git args.

Sources: `gui/lib/services/bridge_backed_repository.dart`,
`gui/lib/services/git_repository.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Uncommitted status is detected

- GIVEN `git status --short --branch` stdout includes a non-branch line
- WHEN repository refresh parses status
- THEN `RepoGitStatus.uncommitted` is set

#### Scenario: Remote push URL defaults to fetch URL when absent

- GIVEN parsed remote output has no push URL for a remote
- WHEN remotes are returned
- THEN push URL equals fetch URL

## Needs Verification

- CLI auto-commit behavior assumes Git user config and repository state allow
  committing; failure handling is categorized as Git error but end-to-end CLI
  tests are limited.
- GUI/bridge Git commands use literal `git`, while CLI Git commands use
  configured `executable_config.git_executable`. Intended consistency needs
  verification.
