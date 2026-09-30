## Why

Git sync on mobile stops short of what pass users expect from a phone client such as Android Password Store. The status badge reads only local state and never fetches. Commits that have not been pushed still show as clean. A pull fails as soon as local and remote history diverge. GUI edits are left uncommitted unless the user ticks a checkbox. Commits made on mobile fall back to `Pars <pars@localhost>` when the repository has no identity. Private HTTPS remotes and passphrase-protected SSH keys cannot authenticate. Users therefore have to finish sync on a desktop, even though the rest of the store works on the phone.

## What Changes

- Replace porcelain text parsing in Dart with a typed status result from the bridge: branch, upstream, ahead, behind, changed and conflicted counts, repository state, and last fetch time.
- Add a fetch-only remote check. It runs once per app launch (behind a setting that defaults on) and before every sync, so "pull needed" reflects the remote.
- Add Vault Git states for "push needed", "diverged" and "conflicted" beside the existing clean, uncommitted, pull-needed, sync-failed, disabled and invalid states.
- Make pull-to-refresh a full sync: commit pending changes, fetch, fast-forward or integrate diverged history, then push. Diverged history is integrated by rebase by default, or by merge if the user picks that in Git settings. The first push of a branch with no upstream sets the upstream when exactly one remote exists.
- When automatic commits are off and the work tree has changes, sync asks first. The user can commit and sync, or sync only the existing commits. Syncing only existing commits stops if history has diverged.
- On a rebase or merge conflict, abort, leave the branch at its pre-sync commit, and save that commit to a backup branch. Offer two recovery actions: use the remote version, or push the backup branch so a desktop can resolve it.
- **BREAKING (GUI behavior)**: When Git is enabled, commit every GUI mutation automatically, as `pass` and the CLI do. A Git setting controls this and defaults on. The per-operation "commit after operation" checkbox is removed from mutation sheets.
- Add a commit identity setting that writes repository-local `user.name` and `user.email`, prefilled from the store's PGP key identity. If no identity is configured, ask for one before committing instead of silently using `Pars <pars@localhost>`.
- Add Git maintenance actions: read-only recent history, reset to upstream (backing up local work to a branch first), and switching between remote branches when the work tree is clean.
- Add HTTPS username and token authentication on mobile, stored in platform secure storage, and passphrase-protected SSH keys with optional remembered passphrases.
- Tokenize desktop advanced Git args in Rust with quote support. Quoted values containing spaces or shell characters are passed through; unquoted shell operators are still rejected. Git status refreshes after the command runs.
- Regroup the Git settings sheet into Sync, Commits, Remotes and authentication, and Maintenance sections using the shared section and button components.
- Keep arbitrary Git args unsupported on Android and iOS. Mobile gets named operations only.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `git-integration`: Typed status, fetch, full sync with a rebase or merge strategy and conflict backup, automatic GUI commits, commit identity, maintenance operations, HTTPS token and SSH passphrase authentication on mobile, and quote-aware desktop Git args.
- `native-bridge-api`: Structured Git operations add typed status, fetch, sync, reset, history, branch listing and switching, identity read/write, and credential inputs. Advanced args take a raw command line that Rust tokenizes.
- `flutter-vault-and-manage`: Vault shows push-needed, diverged and conflicted states, pull-to-refresh runs a full sync, and mutations follow the auto-commit setting instead of a per-sheet checkbox.
- `flutter-security-and-onboarding`: Git settings are grouped into Sync, Commits, Remotes and authentication, and Maintenance, with integration strategy, identity, auto-commit, remote check, credential, history, reset and branch surfaces.

## Impact

- Rust bridge: `bridge/src/api.rs` Git operations (status, fetch, sync, rebase, reset, log, branches, config identity, credential callbacks), known-hosts and SSH key handling, generated FRB bindings, and bridge smoke tests.
- Core: `core/src/gui/mod.rs` Git args validation and new command-line tokenizer, plus `core/tests/gui_api_test.rs`.
- Flutter: `gui/lib/services/bridge_backed_repository.dart`, `git_repository.dart`, the fake repository, Vault status badge and pull-to-refresh, mutation sheets under `gui/lib/screens/vault/operations/`, the Git settings sheets, secure storage for HTTPS tokens and SSH passphrases, `app_en.arb` and `app_zh.arb`, and the related widget and repository tests.
- Desktop keeps system Git for every operation. Typed results come from parsing machine-readable Git output in Rust (`status --porcelain=v2 --branch`, formatted `log`), not from switching desktop to libgit2.
- No new third-party dependencies are expected. `git2` 0.20 already provides fetch, rebase, merge, reset, revwalk, config and plaintext credentials.
