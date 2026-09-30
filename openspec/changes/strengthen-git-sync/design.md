## Context

Pars has two Git backends behind one bridge. Android and iOS use libgit2 through `git2` 0.20 (`structured_git_*` in `bridge/src/api.rs`). Desktop GUI and the CLI run the system `git` executable. The Flutter layer (`BridgeBackedRepository`) turns bridge output into `RepoGitStatus` and drives the Vault badge, the Git settings sheet, and pull-to-refresh.

Current behavior that this change addresses:

- `git_status` returns `status --short --branch` text, and Dart classifies it: `behind` means pull needed, any non-`##` line means uncommitted, and everything else is clean. `ahead` is ignored, so unpushed commits read as clean. Status never fetches, so `behind` only appears after a pull fetched but could not fast-forward.
- Mobile pull fetches the upstream and only fast-forwards. It fails when history diverges.
- `syncWithRemote` pulls, then pushes only if status says `ahead`. It never commits pending changes.
- Mutation sheets carry a "commit after operation" checkbox that defaults to off.
- `structured_git_commit` uses `repo.signature()`, then falls back to `Pars <pars@localhost>`. Cloned repositories normally have no `user.name`, so mobile commits get the fallback.
- Mobile credentials cover SSH keys only, read with a `None` passphrase. HTTPS works only for remotes that need no authentication.
- Desktop advanced Git args are split on whitespace in Dart, so quoted values cannot be expressed. Core rejects shell operator characters anywhere, even though the command never runs through a shell.
- `autoPullOnOpen` exists but nothing calls it.

Constraints:

- Mobile must not emulate arbitrary Git args (`git-integration`, archived `adopt-single-store-and-optional-git` design).
- Desktop keeps system Git for every operation so user credential helpers, SSH agents, and hooks keep working.
- Logs and user-facing errors must not contain key material, passphrases, tokens, or credentials embedded in URLs.
- GUI surfaces follow `AGENTS.md`: Pars tokens, `AppSectionBox` rows, `ParsButtonGrid`, `ParsDialog`, and strings in both ARB files.

## Goals / Non-Goals

**Goals:**

- The Vault badge reflects the remote, including push-needed, diverged, and conflicted states.
- One user action (pull-to-refresh) takes a store from any ordinary state to in sync with its upstream.
- Divergence and conflicts never leave the repository half-rebased and never lose local commits.
- Commits carry a real author identity chosen by the user.
- Private HTTPS remotes and passphrase-protected SSH keys work on mobile.
- Desktop advanced args accept quoted values.

**Non-Goals:**

- Resolving conflicts per entry inside the app.
- Pushing automatically after an automatic commit. Pushes happen only on sync or an explicit Push.
- Checking the remote when the app returns from the background.
- Arbitrary Git args on Android or iOS.
- HTTP(S) proxy, commit signing, `git gc`, and pushing all branches.
- Generating RSA or ECDSA SSH keys, OpenKeychain, or hardware-backed SSH keys.
- An HTTPS credential UI on desktop (system credential helpers already cover it).
- Managing or deleting backup branches from the app.

## Decisions

### 1. Typed status summary from the bridge

Add `git_status_summary` returning `GitStatusSummaryDto`:

- `branch`: optional; absent for a detached or unborn HEAD.
- `upstream`: optional.
- `ahead`, `behind`, `changed`, `conflicted`: counts.
- `operation`: `none | rebasing | merging | other`.
- `lastFetchedAt`: optional Unix seconds, taken from the `FETCH_HEAD` modification time.

Mobile builds it directly from libgit2: `graph_ahead_behind`, `statuses`, and `repo.state()`. Desktop runs `git status --porcelain=v2 --branch -z` and parses `# branch.head`, `# branch.upstream`, `# branch.ab`, and `1`/`2`/`u`/`?` records in Rust. The operation state comes from `rebase-merge`, `rebase-apply`, and `MERGE_HEAD` under the Git directory.

Dart classifies the summary in this order:

1. conflicted (any conflicted entry, or an operation in progress)
2. uncommitted (`changed > 0`)
3. diverged (`ahead > 0` and `behind > 0`)
4. pull needed (`behind > 0`)
5. push needed (`ahead > 0`, or remote mode with a local branch but no upstream)
6. clean

`git_status` keeps returning text for the details panel only; nothing parses it any more.

- Alternative: keep parsing porcelain text in Dart and add `ahead`. Rejected because the `##` sanitizer bug showed how fragile text passing through redaction is. A typed DTO also lets desktop and mobile share one classifier.
- Alternative: use libgit2 for read-only status on desktop too. Rejected to keep one backend per platform. Porcelain v2 is stable, machine-readable, and needs Git 2.11 or later.

### 2. Fetch-only remote check

Add `git_fetch`. It fetches the upstream's remote, or the only remote when there is no upstream, with the same credential callbacks as pull. It never moves local branches or the work tree.

Vault runs it once per app process, the first time it shows a remote store. Returning from the background does not trigger it. This is controlled by a "Check remote on launch" setting, which defaults on. A failed background check keeps the local status and records that the check failed; the badge does not turn into a sync failure. An explicit sync that fails does set sync failed.

- Alternative: auto-sync on launch, as APS 1.13.0 did. Rejected because APS withdrew it in 1.13.1, and mutating history without user action is surprising.
- Alternative: also check on resume, throttled. Rejected to keep network use predictable; pull-to-refresh already fetches on demand.

### 3. One bridge call for sync

Add `git_sync(request)` so that commit, fetch, integration, and push run under one credential session and one lock on the repository:

The request carries a commit message, `commitPending`, and `strategy` (`rebase` or `merge`).

1. If an operation is in progress or conflicts exist, stop with outcome `conflicted`.
2. If `commitPending` is true and the work tree has changes, stage everything and commit with the request's message. This needs an identity (decision 5).
3. Fetch the upstream.
4. Integrate:
   - With `behind == 0` there is nothing to do.
   - With `ahead == 0`, fast-forward. Checkout is safe rather than forced, so uncommitted edits to entries the upstream did not touch survive. An overlapping edit fails the step with `blockedByChanges`.
   - Otherwise history has diverged. If the work tree still has changes, stop with `blockedByChanges`. If not, integrate using `strategy`.
5. Push when `ahead > 0` after integration. If there is no upstream and exactly one remote exists, push the current branch to `<remote>/<branch>` and set it as upstream.

The result is `GitSyncResultDto`: whether a commit was made, commits pulled, whether a push happened, an optional conflict (backup branch name and conflicting paths), whether uncommitted changes blocked integration, and the summary after sync.

Mobile integration never writes rebase or merge state to disk:

- **Rebase** uses libgit2's in-memory rebase (`RebaseOptions::inmemory(true)`). Each step's index is checked for conflicts before its commit is created.
- **Merge** uses `merge_commits` into an in-memory index. If that index has no conflicts, the bridge writes its tree and creates a merge commit with the local and upstream commits as parents, using the message `Merge <upstream> into <branch>`.

Only after integration succeeds does the bridge move the branch reference, using a compare-and-swap against the pre-sync commit, and check out the new tree. The work tree is clean at that point, because a dirty tree stops before diverged integration. If anything conflicts, the result is dropped and nothing on disk has changed.

Desktop runs explicit commands with `GIT_EDITOR=true`: `add -A`, `commit -m`, `fetch <remote>`, `merge --ff-only @{u}`, then `rebase @{u}` or `merge --no-edit @{u}` according to `strategy`, then `push`. On failure it runs `rebase --abort` or `merge --abort` before creating the backup branch. It never relies on the user's `pull.rebase` or `pull.ff` settings.

The strategy is a persisted Git preference that defaults to rebase. Rebase suits pass stores, which are usually linear. `.gpg` files cannot be merged textually, so both strategies conflict in the same cases; merge exists for users who do not want local commits rewritten.

Flutter decides `commitPending` before calling sync:

- **"Commit every change" on**: always true. Leftover changes, such as an earlier failed automatic commit, are committed without asking.
- **Setting off, with changes**: Flutter asks first in a `ParsDialog`. The primary action, "Commit and sync", sends true. The secondary action, "Sync without committing", sends false. Closing the dialog cancels sync.
- **Setting off, no changes**: sync runs directly with false.

- Alternative: always commit on sync regardless of the setting. Rejected; users who turned automatic commits off want control over what gets committed.
- Alternative: rebase or merge on disk and leave the repository mid-operation for the user. Rejected because the phone has no tool to finish it, which is the state APS needed "abort rebase" for.

### 4. Conflicts produce a backup branch, then two recovery actions

On a rebase or merge conflict, sync creates `pars/backup-<UTC yyyyMMdd-HHmmss>` at the pre-sync commit, which already includes any commit sync just made. The current branch stays at that same commit. The Vault offers recovery through a `ParsDialog` with two actions:

- Secondary, "Push backup": push the backup branch to the remote, so a desktop can merge it.
- Primary, destructive, "Use remote": reset to the upstream (decision 6). The backup branch keeps the local commits.

Conflicting paths are returned so the dialog can name the affected entries. They are never written to logs.

### 5. Commit identity is explicit

Add `git_identity(root)` and `git_set_identity(root, name, email)`. Get returns the effective name and email, and whether they come from repository-local config or elsewhere. Set always writes repository-local `user.name` and `user.email`: libgit2 config on mobile, `git config --local` on desktop.

`structured_git_commit` drops the `Pars <pars@localhost>` fallback and returns a typed `IdentityRequired` failure. Before any GUI commit, Dart checks the identity. When it is missing, Dart opens the identity sheet and retries once the user saves.

The sheet is prefilled from the canonical store's PGP key user ID (`Name <email>`) when that key is available locally.

- Alternative: keep the fallback and only show it. Rejected because commits pushed under a placeholder author cannot be fixed without rewriting history.

### 6. Reset to upstream always keeps a backup first

Add `git_reset_to_upstream`:

1. Fetch.
2. If the work tree has changes, commit them (this needs an identity).
3. If HEAD has commits not on the upstream, create `pars/backup-<timestamp>` at HEAD.
4. Hard-reset the branch and work tree to the upstream.

The confirmation is a plain destructive yes/no `ParsDialog` that names the backup branch. Typed confirmation stays reserved for deleting a store and exporting private keys.

### 7. History and branch switching

- `git_log(root, limit)` returns up to 50 entries: short id, summary line, author name, and commit time. Mobile uses revwalk; desktop uses `log -z --format=%h%x00%s%x00%an%x00%at -n <limit>`. The list is read-only and shows no diffs.
- `git_list_remote_branches(root)` lists branches of the upstream remote after a fetch. `git_switch_branch(root, remote_branch)` is allowed only when the summary is clean with `ahead == 0`. It creates or fast-forwards a local tracking branch and checks it out. Otherwise the UI asks the user to sync first.

### 8. Automatic commits for GUI mutations

A persisted Git preference, "Commit every change", defaults on and is stored next to the selected SSH key preference. When it is on and Git mode is local or remote, every successful mutation calls `commitChanges` with the operation's existing message, such as `Delete 3 passwords`.

The mutation sheets lose their checkbox, and `_CommitCheckbox` plus `commitAfterOperation` are removed. Commit failure keeps today's durable warning that the mutation was not rolled back. Automatic commits do not push; the badge shows push needed until the next sync.

- Alternative: keep the checkbox but default it on. Rejected because a per-sheet control for a store-wide policy is noise, and the CLI already commits every change.

### 9. Mobile HTTPS credentials

Clone, fetch, pull, push, sync, and reset requests gain optional `httpsUsername` and `httpsToken` fields. The credential callback answers `USER_PASS_PLAINTEXT` once per operation. A second request within the same operation returns a typed `AuthenticationRequired` failure instead of looping, because libgit2 would otherwise retry the callback indefinitely.

Dart stores credentials in `FlutterSecureStorage`. The key is the remote URL without userinfo, query, or fragment. A username embedded in the URL prefills the prompt. Credentials are saved only after an operation succeeds and deleted on an authentication failure.

Desktop ignores these fields and keeps system credential helpers.

### 10. Passphrase-protected SSH keys on mobile

SSH import accepts encrypted OpenSSH keys and records that the key is encrypted in the key listing, without decrypting it. The OpenSSH format stores the public key in the clear, so the stored private text stays byte-for-byte unchanged and only the public half is written. Encrypted PEM keys stay rejected: their public key cannot be derived without the passphrase, and the RSA crate cannot read legacy PEM encryption. The error tells users to convert with `ssh-keygen -p`. Requests gain an optional `sshPassphrase`, which is passed to `Cred::ssh_key_from_memory`. A missing or wrong passphrase returns a typed `SshPassphraseRequired` failure.

The prompt offers "Remember on this device", which stores the passphrase in secure storage under the key name. Deleting the key deletes the stored passphrase.

### 11. Quote-aware desktop args tokenized in Rust

Add `parse_git_command_line(&str)` to `core/src/gui`. The bridge's `GitArgsRequest` takes `command_line` instead of a token list, and Dart no longer splits it. Rules:

- Whitespace separates tokens.
- Single quotes are literal.
- Double quotes allow `\"` and `\\`.
- A backslash outside quotes escapes the next character.

It rejects the following:

- An unterminated quote.
- Newlines, carriage returns, and NUL anywhere.
- A first token of `git`.
- Unquoted `;`, `|`, `&`, `>`, `<`, backticks, and `$(`.

These characters are allowed inside quotes. The rejection exists to tell users this is not a shell, not for safety, because `Command` never runs a shell. After the command runs, Flutter refreshes Git status.

### 12. Git settings layout

The Git sheet becomes four `AppSectionBox` groups:

- **Sync**: status summary, Sync, "Check remote on launch", and the integration strategy (Rebase or Merge).
- **Commits**: identity, "Commit every change", and Commit now.
- **Remotes and authentication**: remotes, SSH key, and stored HTTPS credentials with Forget.
- **Maintenance**: History, Switch branch, and Reset to remote.

Pull and Push stay as a `ParsButtonGrid` pair in Sync for users who want single steps. Desktop advanced args stay under Advanced/support.

## Risks / Trade-offs

- [Another writer moves the branch while sync is running] → Update the reference by compare-and-swap against the pre-sync commit, and fail with sync failed if it moved.
- [Commit messages reveal entry names] → Same as `pass` and the existing CLI messages. No new message content is introduced.
- [Background fetch uses network and battery] → Once per launch, a setting to turn it off, and no retry loop.
- [A long-running app shows a stale badge] → Pull-to-refresh always fetches, and the details sheet shows the last fetch time.
- [Merge commits in a store synced by other pass clients] → Merge is opt-in; the default stays rebase.
- [libgit2 retries credential callbacks] → Answer each credential type once per operation, then return a typed failure.
- [Tokens and passphrases in memory] → Never logged or returned; errors go through the existing sanitizer; request strings are dropped right after the operation.
- [Backup branches accumulate] → They are local-only unless pushed, and names are timestamped. A management UI is out of scope.
- [Users who liked the unchecked commit checkbox] → "Commit every change" can be turned off. Sync then asks before committing.
- [Syncing without committing on diverged history] → Stops with `blockedByChanges` instead of guessing; the user commits or resets.
- [Desktop parser depends on Git 2.11+ porcelain v2] → If parsing fails, return sync failed with the raw stderr in diagnostics rather than a wrong clean state.

## Migration Plan

- No data migration. "Check remote on launch" and "Commit every change" default on, and the integration strategy defaults to rebase, at first read.
- Stores that already have uncommitted GUI edits get them committed on the next explicit sync, once an identity is set.
- The `GitArgsRequest` bridge DTO changes shape; FRB bindings are regenerated in the same change.
- Rollback is a code revert. Backup branches and local identity config written in the meantime are ordinary Git data and stay harmless.

## Open Questions

- None. Automatic push, check timing, integration strategy, auto-commit default, sync behavior with automatic commits off, identity handling, scope, and branch switching were confirmed on 2026-09-30.
