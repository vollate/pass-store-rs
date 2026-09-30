# Verification

Recorded 2026-09-30 on macOS (desktop host) with the Android NDK 28.2.13676358 toolchain.

## Automated checks

- `cargo test -p pars-core -p pars-bridge`: all suites pass, including 64 bridge unit tests and 23 bridge smoke tests.
  - Mobile (libgit2) coverage in `bridge/src/git_ops.rs` uses local bare remotes. It covers:
    - pending edit committed and pushed
    - fast-forward that keeps an unrelated uncommitted edit
    - overlapping edit blocks the fast-forward
    - dirty diverged tree is blocked
    - rebase without a merge commit
    - merge with two parents
    - conflicts under both strategies leave the branch unchanged and create a backup branch, which can then be pushed
    - first push sets the upstream
    - reset backs up unpushed and uncommitted work
    - history order and unborn branch
    - branch switching is gated on a clean, pushed summary
    - identity read and write
    - typed `IdentityRequired`
    - credentials never reach results or files
  - Desktop (system Git) coverage runs the same scenarios through `git_ops::sys`, with `pull.rebase=false` configured, plus the porcelain v2 summary.
  - Core adds command-line tokenizer tests and encrypted OpenSSH key import.
- `cargo clippy -p pars-core -p pars-bridge --tests`: one warning, `known_hosts::remote_host_key_is_trusted` unused, which is also present at `HEAD`.
- `cargo ndk -t arm64-v8a check` for `pars-bridge`: compiles; same single pre-existing warning.
- `cargo check --workspace --all-targets`: compiles.
- `flutter analyze`: two `deprecated_member_use` infos in `onboarding_store_setup_widgets.dart`, both present at `HEAD`.
- `flutter test`: every test added or changed by this change passes, including the new `test/git_sync_flow_test.dart`. It covers:
  - pull-to-refresh commits when "Commit every change" is on
  - asks first when the setting is off, and closing the dialog runs no Git operation
  - local-only stores only reload
  - blocked-by-changes message
  - conflict badge and recovery dialog
  - identity prompt prefilled from the PGP key, with retry, and no retry when dismissed
  - new badge labels
  - integration strategy selection
- 11 Flutter tests fail identically on a clean `HEAD` worktree, so they predate this change:
  - two `android_autofill_presentation_test` Kotlin source expectations
  - the `gui_source_audit_test` raw-error baseline (10 findings against a baseline of 6, the same count at `HEAD`)
  - eight `ui_visual_matrix_test` goldens that differ by renderer noise on screens this change does not touch
  - Goldens were not updated. The Vault goldens also differ by the shorter status badge from the earlier badge fix.

## Visual inspection

Temporary goldens with a real font were rendered at 390 px width and inspected, then deleted:

- the Vault conflict badge
- the conflict recovery dialog
- the Git settings sheet in English, Chinese, and English at 200% text scale

The sheet shows four sections: Sync, Commits, Remotes and authentication, and Maintenance. Rows are one line each with ellipsis. Pull and Push are a pair with Sync spanning below. There was no overflow at 200%. `gui/test/failures` was restored.

## Not verified

- Task 10.3 (on-device HTTPS token clone, diverged sync under both strategies, conflict recovery, and reset) was not run. The only connected device holds the user's real password store, and these checks push to its remote. They need a disposable remote.
- The HTTPS credentials row and Forget action only render on Android and iOS, so widget tests on the desktop host do not reach them. The credential store itself is unit-tested.

## Deviations from the proposal

- Encrypted PEM SSH keys are still rejected, now with a conversion hint (`ssh-keygen -p`). Only encrypted OpenSSH keys are accepted: a PEM key's public half cannot be derived without the passphrase, and the RSA crate cannot read legacy PEM encryption. The spec, design, and task 7.3 were updated to match.
- The bridge's logging helper was renamed from `git_log` to `trace_git` so the new history method could use the `git_log` name.
