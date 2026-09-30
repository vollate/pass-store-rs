## 1. Typed status summary

- [x] 1.1 Add `GitStatusSummaryDto` (branch, upstream, ahead, behind, changed, conflicted, operation, last-fetch time) and `git_status_summary` to `bridge/src/api.rs`, plus the method list and smoke test
- [x] 1.2 Build the summary from libgit2 on mobile (`graph_ahead_behind`, `statuses`, `repo.state()`, `FETCH_HEAD` mtime) with Rust tests for clean, dirty, ahead, behind, diverged, no upstream, unborn, and rebasing repositories
- [x] 1.3 Parse `git status --porcelain=v2 --branch -z` into the same DTO on desktop, with parser unit tests covering each record type and the operation-state files
- [x] 1.4 Regenerate FRB bindings and add `needPush`, `diverged`, and `conflicted` to `RepoGitStatus`
- [x] 1.5 Replace `_gitStatusFromBridge` text parsing with summary classification in the documented order, and update `bridge_backed_repository_test.dart`
- [x] 1.6 Add the new badge labels, icons, and kinds to `vault_screen.dart` and both ARB files, run `flutter gen-l10n`, and extend `vault_redesign_test.dart`

## 2. Remote check

- [x] 2.1 Add `git_fetch` on mobile (libgit2, upstream remote or the only remote, existing callbacks) and on desktop (`git fetch <remote>`), with tests showing branches and work tree stay unchanged
- [x] 2.2 Add the persisted "Check remote on launch" setting (default on) and keep the last check result in memory for the details sheet
- [x] 2.3 Run the check once per app launch, the first time Vault shows a remote store, and never on resume; keep the local status and record a failed check when a background fetch fails
- [x] 2.4 Remove the unused `autoPullOnOpen` from `GitOperationsRepository`, the bridge-backed repository, and the fakes

## 3. Commit identity

- [x] 3.1 Add `git_identity` and `git_set_identity` (libgit2 local config on mobile, `git config --local` on desktop) with tests showing global config is not touched
- [x] 3.2 Remove the `Pars <pars@localhost>` fallback from `structured_git_commit` and return a typed `IdentityRequired` failure; add the failure category to the bridge and Dart error mapping
- [x] 3.3 Build the identity sheet (name and email, prefilled from the store's PGP key user ID) and the pre-commit identity check shared by every GUI commit path
- [x] 3.4 Widget tests: missing identity opens the sheet before commit, cancel leaves the mutation uncommitted, and saving retries the commit

## 4. Automatic commits

- [x] 4.1 Add the persisted "Commit every change" setting (default on) next to the selected SSH key preference
- [x] 4.2 Route every successful mutation in `vault_operations.dart` through the setting instead of the sheet checkbox, keeping the existing messages and durable failure warning
- [x] 4.3 Remove `_CommitCheckbox`, the `_commit` state in every mutation sheet, and the `commitAfterOperation` string from both ARB files; run `flutter gen-l10n`
- [x] 4.4 Update `vault_entry_actions_test.dart` and `mobile_gui_smoke_test.dart` for default-on commits, setting off, and Git-disabled stores

## 5. Sync

- [x] 5.1 Add `GitSyncRequest` (message, commit pending, strategy) and `GitSyncResultDto` (committed, pulled count, pushed, blocked by changes, optional conflict with backup branch and paths, summary) and `git_sync` to the bridge
- [x] 5.2 Implement mobile sync: refuse on an in-progress operation, optionally commit pending changes, fetch, fast-forward with safe checkout, stop with blocked-by-changes on a dirty diverged tree, compare-and-swap branch update, push, and first-push upstream setup
- [x] 5.3 Implement mobile in-memory rebase with conflict detection per step, and in-memory merge (`merge_commits`, conflict check, two-parent merge commit)
- [x] 5.4 Create the `pars/backup-<UTC timestamp>` branch on conflict for both strategies and return conflicting paths without logging them
- [x] 5.5 Implement desktop sync with explicit commands and `GIT_EDITOR=true`, choosing `rebase @{u}` or `merge --no-edit @{u}`, and calling `rebase --abort` or `merge --abort` before creating the backup branch on failure
- [x] 5.6 Rust tests with local bare remotes: pending edit pushed, fast-forward around an uncommitted edit, overlapping uncommitted edit blocks fast-forward, dirty diverged tree blocked, rebase with no merge commit, merge with two parents, conflict under each strategy leaves the branch unchanged with a backup, first push sets upstream, desktop ignores `pull.rebase=false`
- [x] 5.7 Add the persisted integration strategy preference (default rebase)
- [x] 5.8 Replace `syncWithRemote` in Dart with `git_sync`: decide commit-pending from "Commit every change", ask with the "Commit and sync" / "Sync without committing" `ParsDialog` when the setting is off and the tree is dirty, run the identity check before committing, and map outcomes to status and a single notification
- [x] 5.9 Make Vault pull-to-refresh sync only in remote mode, and add widget tests for the remote, local, ask-before-commit, blocked, and conflict cases

## 6. Recovery and maintenance

- [x] 6.1 Add `git_reset_to_upstream` (fetch, commit pending changes, backup branch when ahead, hard reset) on both platforms with Rust tests for unpushed commits, dirty work tree, and the no-backup case
- [x] 6.2 Add a push-backup operation that pushes only the named `pars/backup-` branch
- [x] 6.3 Build the conflict recovery `ParsDialog` (secondary Push backup, destructive primary Use remote) opened from the conflicted and diverged badge
- [x] 6.4 Add `git_log` (mobile revwalk, desktop `log -z --format`) returning up to 50 entries, with tests for limit, order, and unborn branch
- [x] 6.5 Build the read-only History list with a scrollable `AppSectionBox`
- [x] 6.6 Add `git_list_remote_branches` and `git_switch_branch` gated on a clean, pushed summary, with Rust tests for the allowed and blocked cases
- [x] 6.7 Build the Switch branch picker and the "sync first" message

## 7. Mobile credentials

- [x] 7.1 Add optional HTTPS username and token fields to clone, fetch, pull, push, sync, reset, and branch requests; answer `USER_PASS_PLAINTEXT` once per operation and return `AuthenticationRequired` on a repeat request
- [x] 7.2 Store, look up, and delete HTTPS credentials in `FlutterSecureStorage`, keyed by the sanitized remote URL; prompt on `AuthenticationRequired`, save after success, delete after rejection
- [x] 7.3 Accept encrypted OpenSSH keys on import (encrypted PEM keys are rejected with a conversion hint), mark them encrypted in key listings, and pass an optional passphrase to `Cred::ssh_key_from_memory`
- [x] 7.4 Return `SshPassphraseRequired` for a missing or wrong passphrase; add the prompt with "Remember on this device", and delete the remembered passphrase with its key
- [x] 7.5 Tests that tokens and passphrases never appear in logs, command strings, output, or failure messages, and that the bridge writes no file containing them

## 8. Desktop advanced args

- [x] 8.1 Add `parse_git_command_line` to `core/src/gui/mod.rs` with the quoting and rejection rules, and move operator rejection out of `validate_git_args`
- [x] 8.2 Change `GitArgsRequest` to carry `command_line`, regenerate bindings, and remove `_parseGitArgs` from the settings screen
- [x] 8.3 Refresh the status summary after every advanced command
- [x] 8.4 Core tests for quoted spaces, quoted shell characters, escapes, unterminated quotes, unquoted operators, newlines, and a leading `git`; update the settings widget tests

## 9. Git settings layout

- [x] 9.1 Rebuild the Git sheet as Sync, Commits, Remotes and authentication, and Maintenance sections with `AppSectionBox`, `ParsSectionRow`, `ParsButtonGrid`, and `ParsDialog`
- [x] 9.2 Add all new strings to `app_en.arb` and `app_zh.arb`, run `flutter gen-l10n`, and remove keys that became unused
- [x] 9.3 Widget tests for remote and local modes, the integration strategy choice, the identity row, and forgetting HTTPS credentials, plus `expectNoFlutterOverflow` at 200% text scale

## 10. Specs and verification

- [x] 10.1 Run `cargo test` for core and bridge, the Android `cargo ndk` build, `flutter analyze`, and `flutter test`
- [x] 10.2 Render the Vault badge states, the conflict dialog, and the Git settings sheet at phone width, inspect them, then delete temporary previews and restore `gui/test/failures`
- [ ] 10.3 On an Android device, check clone over HTTPS with a token, sync with a diverged remote under both strategies, conflict recovery, and reset to remote
- [x] 10.4 Record results and remaining limits in `verification.md`
