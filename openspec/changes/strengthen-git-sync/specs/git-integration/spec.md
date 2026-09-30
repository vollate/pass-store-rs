## MODIFIED Requirements

### Requirement: GUI Git API SHALL reject shell syntax in arbitrary Git args

GUI-facing arbitrary Git args SHALL arrive as one command line that Rust tokenizes. Whitespace SHALL separate tokens, single quotes SHALL be literal, double quotes SHALL allow `\"` and `\\` escapes, and a backslash outside quotes SHALL escape the next character. The tokenized args SHALL be non-empty and SHALL NOT start with the literal `git` program name. Tokenization SHALL reject unterminated quotes, newlines, carriage returns, and NUL anywhere, and SHALL reject unquoted shell syntax such as `$(`, `;`, `|`, `&`, `>`, `<`, or backticks. The same characters inside quotes SHALL be passed through as part of the argument.

Sources: `core/src/gui/mod.rs`, `core/tests/gui_api_test.rs`,
`bridge/src/api.rs`

#### Scenario: Plain Git args are accepted

- **WHEN** the command line is `pull --rebase`
- **THEN** a `GitOperationRequest` is created with args `pull` and `--rebase`

#### Scenario: Quoted values keep spaces

- **WHEN** the command line is `config user.name "Ada Lovelace"`
- **THEN** the args are `config`, `user.name`, and `Ada Lovelace`

#### Scenario: Quoted shell characters are literal

- **WHEN** the command line is `commit -m 'Fix A & B'`
- **THEN** the args are `commit`, `-m`, and `Fix A & B`

#### Scenario: Unquoted shell syntax is rejected

- **WHEN** the command line contains unquoted `;`, `|`, `&&`, `>`, or `$()`
- **THEN** validation fails with a shell-syntax error

#### Scenario: Unterminated quote is rejected

- **WHEN** the command line is `commit -m "unfinished`
- **THEN** validation fails and no Git process is started

### Requirement: Bridge SHALL expose standard Git operations

The bridge SHALL expose `git_status`, `git_status_summary`, `git_fetch`, `git_pull`, `git_push`, `git_commit`, `git_sync`, `git_reset_to_upstream`, `git_log`, `git_list_remote_branches`, `git_switch_branch`, `git_identity`, `git_set_identity`, and `run_git_args`. On desktop, `git_status` SHALL run `status --short --branch` for display only, `git_status_summary` SHALL run `status --porcelain=v2 --branch -z`, and `git_commit` SHALL run `commit -m <message>`. Desktop network operations SHALL name the remote explicitly and SHALL NOT depend on the user's `pull.rebase` setting.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/lib/services/bridge_backed_repository.dart`

#### Scenario: Git status command is fixed

- **WHEN** bridge `git_status` is called on desktop
- **THEN** it executes `git status --short --branch`

#### Scenario: Git commit command uses supplied message

- **WHEN** bridge `git_commit` is called with `Sync passwords` on desktop
- **THEN** it executes `git commit -m "Sync passwords"`

#### Scenario: Desktop summary uses porcelain v2

- **WHEN** bridge `git_status_summary` is called on desktop
- **THEN** it executes `git status --porcelain=v2 --branch -z`
- **AND** returns branch, upstream, ahead, behind, changed, and conflicted values parsed in Rust

### Requirement: Flutter repository SHALL derive Git status and remote operations

The Flutter bridge-backed repository SHALL first inspect canonical store Git mode. For disabled mode it SHALL skip Git commands and expose a neutral disabled status. For local or remote mode it SHALL classify the typed status summary, checking in this order: conflicted, uncommitted, diverged, need-pull, need-push, clean. A failed summary SHALL be classified as sync-failed. It SHALL NOT classify status from porcelain text. It SHALL parse and mutate remotes only for valid Git and SHALL enable pull, push, fetch, and sync only when a suitable remote exists. Invalid Git SHALL remain distinguishable from disabled Git.

Sources: `gui/lib/services/bridge_backed_repository.dart`, `gui/lib/services/git_repository.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Disabled Git skips status command

- **GIVEN** app-state inspection reports Git mode disabled
- **WHEN** repository refresh runs
- **THEN** no Git status operation is invoked
- **AND** repository status is Git disabled rather than sync failed

#### Scenario: Uncommitted status is detected

- **GIVEN** the status summary reports `changed > 0`
- **WHEN** repository refresh classifies status
- **THEN** `RepoGitStatus.uncommitted` is set

#### Scenario: Unpushed commits need push

- **GIVEN** the status summary reports `ahead = 1` and `behind = 0` with no changes
- **WHEN** repository refresh classifies status
- **THEN** `RepoGitStatus.needPush` is set
- **AND** it is not reported as clean

#### Scenario: Diverged history is distinct from pull needed

- **GIVEN** the status summary reports `ahead = 1` and `behind = 2`
- **WHEN** repository refresh classifies status
- **THEN** `RepoGitStatus.diverged` is set

#### Scenario: Operation in progress is conflicted

- **GIVEN** the status summary reports operation `rebasing`
- **WHEN** repository refresh classifies status
- **THEN** `RepoGitStatus.conflicted` is set

#### Scenario: Remote branch without upstream needs push

- **GIVEN** Git mode is remote and the current branch has commits but no upstream
- **WHEN** repository refresh classifies status
- **THEN** `RepoGitStatus.needPush` is set

#### Scenario: Remote push URL defaults to fetch URL when absent

- **GIVEN** valid remote output has no push URL for a remote
- **WHEN** remotes are returned
- **THEN** push URL equals fetch URL

#### Scenario: Missing remote disables pull and push without failing local Git

- **GIVEN** Git mode is local
- **WHEN** repository operations are exposed
- **THEN** local status remains available
- **AND** fetch, pull, push, and sync are unavailable until remote configuration succeeds

## ADDED Requirements

### Requirement: Remote check SHALL fetch without changing local branches

A remote check SHALL fetch the upstream's remote, or the only remote when the current branch has no upstream, using the same credential handling as pull. It SHALL NOT move local branches, the index, or the work tree. Vault SHALL run it once per app launch, the first time it shows a remote store, when the "Check remote on launch" setting is on. Returning the app from the background SHALL NOT trigger it. The setting SHALL default on. A failed background check SHALL keep the previous local classification and SHALL NOT set sync-failed.

#### Scenario: Remote check reveals pull needed

- **GIVEN** the remote has one commit that the local branch does not
- **WHEN** the remote check completes
- **THEN** the status summary reports `behind = 1`
- **AND** the local branch and work tree are unchanged

#### Scenario: Offline check keeps local status

- **GIVEN** the local status is clean
- **WHEN** a background remote check fails because the network is unavailable
- **THEN** the status stays clean
- **AND** the failure is recorded as a failed check, not as sync failed

#### Scenario: Resume does not check the remote

- **GIVEN** the remote check already ran in this app launch
- **WHEN** the app returns from the background
- **THEN** no fetch runs

#### Scenario: Setting off skips the launch check

- **GIVEN** "Check remote on launch" is off
- **WHEN** the app launches and Vault shows a remote store
- **THEN** no fetch runs

### Requirement: Git sync SHALL commit, integrate, and push in one operation

Sync SHALL stop with a conflicted outcome if a rebase or merge is already in progress or conflicts exist. Otherwise it SHALL:

1. Commit all pending changes with the supplied message when the request asks it to.
2. Fetch the upstream.
3. Fast-forward when no local commits are ahead, keeping uncommitted edits to entries the upstream did not change.
4. If both sides have commits, integrate them using the persisted integration strategy. That strategy SHALL default to rebase and MAY be set to merge. Desktop SHALL ignore the user's `pull.rebase` and `pull.ff` settings.
5. Push when local commits remain ahead. When the branch has no upstream and exactly one remote exists, push the branch to that remote and set it as upstream.

If uncommitted changes remain and history has diverged, or a fast-forward would overwrite an uncommitted edit, sync SHALL stop before changing the branch and report that uncommitted changes blocked it.

Flutter SHALL ask the sync to commit whenever "Commit every change" is on. When the setting is off and the work tree has changes, Flutter SHALL ask the user before syncing. The primary action SHALL be "Commit and sync", the secondary action SHALL be "Sync without committing", and closing the dialog SHALL cancel the sync.

Sync SHALL return whether it committed, how many commits it pulled, whether it pushed, whether uncommitted changes blocked it, and the status summary afterwards.

#### Scenario: Pending edits are committed and pushed

- **GIVEN** "Commit every change" is on
- **AND** the work tree has one changed entry and the upstream has no new commits
- **WHEN** sync runs
- **THEN** a commit is created with the supplied message
- **AND** that commit is pushed to the upstream
- **AND** the resulting summary is clean

#### Scenario: Divergent history is rebased by default

- **GIVEN** the integration strategy has never been changed
- **AND** the local branch has one commit the upstream lacks, the upstream has one commit the local branch lacks, and they change different entries
- **WHEN** sync runs
- **THEN** the local commit is replayed on top of the upstream commit
- **AND** the result is pushed
- **AND** no merge commit is created

#### Scenario: Merge strategy creates a merge commit

- **GIVEN** the integration strategy is merge
- **AND** local and upstream history have diverged on different entries
- **WHEN** sync runs
- **THEN** a merge commit with the local and upstream commits as parents is created and pushed
- **AND** the original local commit keeps its id

#### Scenario: Automatic commits off asks before committing

- **GIVEN** "Commit every change" is off and the work tree has one changed entry
- **WHEN** the user starts a sync
- **THEN** a dialog offers "Commit and sync" and "Sync without committing"
- **AND** closing the dialog runs no Git operation

#### Scenario: Sync without committing fast-forwards around edits

- **GIVEN** the user chose "Sync without committing"
- **AND** the upstream has one new commit touching a different entry than the uncommitted edit
- **WHEN** sync runs
- **THEN** the branch fast-forwards
- **AND** the uncommitted edit is still present and uncommitted

#### Scenario: Sync without committing stops on divergence

- **GIVEN** the user chose "Sync without committing"
- **AND** local and upstream history have diverged
- **WHEN** sync runs
- **THEN** the branch is not changed and nothing is pushed
- **AND** the result reports that uncommitted changes blocked sync

#### Scenario: First push sets upstream

- **GIVEN** the branch `main` has commits, no upstream, and the repository has one remote `origin`
- **WHEN** sync runs
- **THEN** `main` is pushed to `origin/main`
- **AND** `origin/main` becomes the upstream of `main`

#### Scenario: Desktop sync ignores pull.rebase

- **GIVEN** desktop Git has `pull.rebase=false` configured and the integration strategy is rebase
- **WHEN** sync integrates diverged history
- **THEN** it rebases local commits and does not create a merge commit

### Requirement: Sync conflicts SHALL leave the branch unchanged and keep a backup

When rebasing or merging during sync hits a conflict, sync SHALL abandon the operation, leave the current branch at its pre-sync commit with a clean work tree, and create a local branch named `pars/backup-<UTC yyyyMMdd-HHmmss>` at that commit. It SHALL return the backup branch name and the conflicting paths. Conflicting paths SHALL NOT be written to logs. On mobile, rebase and merge SHALL run in memory so that no rebase or merge state is written to disk.

#### Scenario: Conflict does not leave a rebase in progress

- **GIVEN** the integration strategy is rebase
- **AND** the local and upstream commits both change the same entry
- **WHEN** sync runs
- **THEN** the outcome is conflicted
- **AND** the repository has no rebase in progress
- **AND** the current branch still points at the pre-sync commit

#### Scenario: Conflict does not leave a merge in progress

- **GIVEN** the integration strategy is merge
- **AND** the local and upstream commits both change the same entry
- **WHEN** sync runs
- **THEN** the outcome is conflicted
- **AND** the repository has no merge in progress
- **AND** the current branch still points at the pre-sync commit

#### Scenario: Conflict creates a backup branch

- **WHEN** sync reports a conflict
- **THEN** a `pars/backup-` branch exists at the pre-sync commit
- **AND** its name is returned to Flutter

#### Scenario: Backup branch can be pushed

- **GIVEN** sync reported a conflict with backup branch `pars/backup-20260930-100000`
- **WHEN** the user chooses Push backup
- **THEN** that branch is pushed to the upstream's remote under the same name
- **AND** the current branch is not pushed

### Requirement: GUI mutations SHALL commit automatically when enabled

A persisted "Commit every change" Git setting SHALL default on. When it is on and Git mode is local or remote, every successful GUI mutation SHALL commit all changes with that operation's message. When it is off, mutations SHALL leave changes uncommitted. Automatic commits SHALL NOT push. GUI mutation sheets SHALL NOT offer a per-operation commit control.

#### Scenario: Edit commits by default

- **GIVEN** Git mode is remote and the setting has never been changed
- **WHEN** the user saves an edited entry
- **THEN** a commit is created with the edit's message
- **AND** no push runs

#### Scenario: Disabled setting leaves changes uncommitted

- **GIVEN** "Commit every change" is off
- **WHEN** the user deletes an entry
- **THEN** no commit is created
- **AND** Git status becomes uncommitted

#### Scenario: Git-disabled store does not commit

- **GIVEN** Git mode is disabled
- **WHEN** the user saves an entry
- **THEN** no commit is attempted

### Requirement: GUI commits SHALL use a configured identity

The bridge SHALL report the effective commit name and email, and whether they come from repository-local config. It SHALL write identity only to repository-local `user.name` and `user.email`. Mobile commits SHALL NOT fall back to a built-in placeholder identity; without an identity they SHALL fail with a typed `IdentityRequired` failure. Before any GUI commit, including commits made by sync or reset, Flutter SHALL check the identity. If none is set, it SHALL ask for one, prefilled from the canonical store's PGP key user ID when that key is available, and continue after the user saves it.

#### Scenario: Missing identity is requested before commit

- **GIVEN** the repository has no effective `user.name`
- **WHEN** a GUI commit is about to run
- **THEN** the identity sheet opens
- **AND** no commit is created until the user saves a name and email

#### Scenario: Identity is written locally

- **WHEN** the user saves `Ada Lovelace` and `ada@example.invalid`
- **THEN** the repository's local config contains those values
- **AND** global Git config is not modified

#### Scenario: Mobile commit refuses placeholder identity

- **GIVEN** the GUI runs on mobile and the repository has no identity
- **WHEN** `git_commit` is called directly
- **THEN** it returns `IdentityRequired`
- **AND** no commit authored by `Pars <pars@localhost>` exists

#### Scenario: Identity is prefilled from the store key

- **GIVEN** the store's PGP key user ID is `Ada Lovelace <ada@example.invalid>`
- **WHEN** the identity sheet opens with no identity configured
- **THEN** the name and email fields are prefilled with those values

### Requirement: Reset to upstream SHALL back up local work first

Reset to upstream SHALL fetch. If the work tree has changes, it SHALL commit them, which requires an identity. It SHALL create a `pars/backup-<UTC yyyyMMdd-HHmmss>` branch at HEAD when HEAD has commits not reachable from the upstream. It SHALL then hard-reset the current branch, index, and work tree to the upstream. Flutter SHALL confirm the reset with a destructive yes/no dialog that names the backup branch when one will be created.

#### Scenario: Unpushed commits survive reset

- **GIVEN** the local branch has two commits the upstream lacks
- **WHEN** the user confirms Reset to remote
- **THEN** a `pars/backup-` branch points at the previous HEAD
- **AND** the current branch equals the upstream

#### Scenario: Uncommitted edits survive reset

- **GIVEN** the work tree has one changed entry
- **WHEN** the user confirms Reset to remote
- **THEN** the change is committed and reachable from the backup branch
- **AND** the work tree matches the upstream

#### Scenario: Clean up-to-date reset makes no backup

- **GIVEN** HEAD equals the upstream and the work tree is clean
- **WHEN** reset runs
- **THEN** no backup branch is created

### Requirement: Git history SHALL be viewable read-only

The bridge SHALL return up to 50 recent commits of the current branch, each with short id, summary line, author name, and commit time. Flutter SHALL show them as a read-only list without diffs or actions that change history.

#### Scenario: History lists recent commits

- **GIVEN** the branch has 60 commits
- **WHEN** history is opened
- **THEN** the 50 most recent commits are listed newest first

#### Scenario: Unborn branch shows empty history

- **GIVEN** the repository has no commits
- **WHEN** history is opened
- **THEN** an empty state is shown without an error

### Requirement: Branch switching SHALL require a clean and pushed branch

The bridge SHALL list branches of the upstream's remote. Switching SHALL be allowed only when the status summary shows no changes, no conflicts, and `ahead = 0`. Switching SHALL create or fast-forward a local branch tracking the chosen remote branch and check it out. Otherwise the UI SHALL tell the user to sync first.

#### Scenario: Clean branch can switch

- **GIVEN** the summary is clean and the remote has branch `archive`
- **WHEN** the user switches to `archive`
- **THEN** local `archive` tracks the remote `archive` and is checked out

#### Scenario: Unpushed work blocks switching

- **GIVEN** the summary reports `ahead = 1`
- **WHEN** the user tries to switch branch
- **THEN** no checkout happens
- **AND** the user is asked to sync first

### Requirement: Mobile HTTPS remotes SHALL authenticate with a username and token

On Android and iOS, clone, fetch, pull, push, sync, reset, and branch operations SHALL accept an optional HTTPS username and token. The credential callback SHALL supply them at most once per operation and SHALL return a typed `AuthenticationRequired` failure if the remote asks again. Flutter SHALL keep credentials in platform secure storage, keyed by the remote URL without userinfo, query, or fragment. It SHALL save them only after an operation succeeds and delete them after an authentication failure. Desktop SHALL keep using system Git credential helpers and SHALL ignore these fields.

#### Scenario: Private HTTPS clone asks for a token

- **GIVEN** an HTTPS remote that requires authentication and no stored credentials
- **WHEN** the user clones it on mobile
- **THEN** the user is asked for a username and token
- **AND** after a successful retry the credentials are stored in secure storage

#### Scenario: Rejected credentials are forgotten

- **GIVEN** stored HTTPS credentials that the remote now rejects
- **WHEN** a sync runs
- **THEN** the operation fails with `AuthenticationRequired`
- **AND** the stored credentials are deleted
- **AND** the callback is not retried in a loop

#### Scenario: Tokens are never logged

- **WHEN** any HTTPS operation succeeds or fails
- **THEN** logs, error messages, and returned output contain neither the token nor the password

### Requirement: Mobile SSH keys SHALL support passphrases

SSH key import SHALL accept encrypted OpenSSH private keys without decrypting them, and key listings SHALL mark them as encrypted. Encrypted PEM keys SHALL be rejected with a message explaining how to convert them to the OpenSSH format, because their public key cannot be derived without the passphrase. Operations using an encrypted key SHALL accept a passphrase. A missing or wrong passphrase SHALL return a typed `SshPassphraseRequired` failure. Flutter SHALL let the user remember the passphrase in secure storage for that key, and SHALL delete a remembered passphrase when its key is deleted.

#### Scenario: Encrypted key is imported

- **WHEN** the user imports an OpenSSH private key protected by a passphrase
- **THEN** the import succeeds
- **AND** the key is listed as encrypted

#### Scenario: Encrypted PEM key is rejected with guidance

- **WHEN** the user imports a PEM private key protected by a passphrase
- **THEN** the import fails without writing any file
- **AND** the message explains how to convert the key to the OpenSSH format

#### Scenario: Passphrase is requested at use

- **GIVEN** the selected SSH key is encrypted and no passphrase is remembered
- **WHEN** sync runs
- **THEN** the user is asked for the passphrase
- **AND** the operation continues with it

#### Scenario: Wrong passphrase is typed

- **WHEN** an operation runs with a wrong passphrase
- **THEN** it fails with `SshPassphraseRequired`
- **AND** the passphrase does not appear in logs or errors

### Requirement: Desktop advanced Git args SHALL refresh status after running

After a desktop advanced Git command completes, whether it succeeded or failed, Flutter SHALL refresh the Git status summary so that the Vault badge reflects any change the command made.

#### Scenario: Commit from advanced args updates badge

- **GIVEN** the badge shows uncommitted
- **WHEN** the user runs `commit -am "Update"` from advanced Git args on desktop
- **THEN** the status summary is refreshed
- **AND** the badge no longer shows uncommitted
