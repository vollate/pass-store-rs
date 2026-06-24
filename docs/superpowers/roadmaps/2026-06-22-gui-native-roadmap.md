# Pars GUI Native Roadmap

Date: 2026-06-22
Owner: GUI/native integration workstream
Status: completed

This roadmap tracks the remaining work needed to turn the current Flutter GUI shell into a functional mobile password manager. Check each item when it is actually implemented, tested, and merged. The current UI shell is useful, but it is not the product: real functionality must call `pars-core` directly through a native Rust bridge rather than shelling out to `pars-cli`.

## Ground Rules

- [x] Mobile GUI design documented.
- [x] Phase 1 Flutter UI shell implemented with demo data.
- [x] Do not execute `pars-cli` from Flutter for normal product behavior.
- [x] Expose stable Rust APIs from `pars-core` for GUI use.
- [x] Use `flutter_rust_bridge` or an equivalent Flutter/Rust native bridge for Dart-to-Rust calls.
- [x] Keep CLI-specific prompting, terminal I/O, and colorized tree output out of the GUI API.
- [x] Treat bundled GPG/OpenPGP support as a first-class platform packaging problem, not a late afterthought.
- [x] Update this roadmap checkbox-by-checkbox as tasks are completed.

## Milestone 0: Current State Baseline

- [x] `Vault / Manage / Settings` bottom navigation exists.
- [x] Gesture-lock onboarding mock exists.
- [x] Vault list/search/detail bottom sheet exists.
- [x] Pass entry parser demo exists in Dart.
- [x] Manage mock workflows exist.
- [x] Settings mock surfaces for security, keys, store, Git, and advanced Git args exist.
- [x] Flutter widget tests exist for the mock shell.
- [x] `flutter test` and `flutter analyze` passed for phase 1.
- [x] GUI state is backed by real password-store data.
- [x] GUI operations mutate real password-store files.
- [x] GUI operations use real PGP encryption/decryption.
- [x] GUI operations use real Git status/pull/push/commit.
- [x] GUI auth and key storage use real platform APIs.

## Milestone 1: `pars-core` GUI API Boundary

Goal: create a core API layer that is friendly to GUI/native callers and does not depend on terminal streams.

- [x] Audit current `core/src/operation/*` APIs and classify each as GUI-ready, CLI-shaped, or reusable with adapter.
  - GUI-safe boundary lives in `core/src/gui/mod.rs`; Flutter/native bridge code should call this module, not `core/src/operation/*` directly.
  - Reusable through GUI adapters: entry listing/showing, insert, generate, edit, move/copy-style rename, delete, and advanced Git args.
  - CLI-shaped only: `insert_io`, `generate_io`, `remove_io`, `copy_rename_io`, `git_io`, `edit`, `init`, `find_term`, and terminal tree rendering paths because they prompt, inherit stdio, launch editors, print directly, or shape output for terminals.
  - Keep CLI-specific operations for `pars-cli`; add or extend `core::gui` APIs when the GUI needs behavior.
- [x] Add a `core::gui` or `core::api` module for GUI-safe request/response structs.
- [x] Define `CoreError` with typed error categories:
  - [x] `ConfigError`
  - [x] `StoreError`
  - [x] `PgpError`
  - [x] `GitError`
  - [x] `ClipboardError`
  - [x] `ValidationError`
  - [x] `UnsupportedPlatform`
- [x] Define repo/store models:
  - [x] `StoreId`
  - [x] `StoreInfo`
  - [x] `StoreStatus`
  - [x] `GitStatusSummary`
- [x] Define entry models:
  - [x] `EntryRef`
  - [x] `EntrySummary`
  - [x] `EntrySecret`
  - [x] `ParsedEntryFields`
  - [x] `RawEntryNotes`
- [x] Define key models:
  - [x] `PgpKeySummary`
  - [x] `SshKeySummary`
  - [x] `KeyImportResult`
  - [x] `KeyExportResult`
- [x] Define operation request structs:
  - [x] `ListEntriesRequest`
  - [x] `ReadEntryRequest`
  - [x] `InsertEntryRequest`
  - [x] `GenerateEntryRequest`
  - [x] `EditEntryRequest`
  - [x] `MoveEntryRequest`
  - [x] `DeleteEntryRequest`
  - [x] `BatchOperationRequest`
  - [x] `GitOperationRequest`
- [x] Remove interactive stdin/stdout assumptions from GUI-callable operations.
- [x] Replace CLI overwrite prompts with explicit request flags and typed conflicts.
- [x] Add non-interactive `read_entry` GUI API that decrypts and parses entries.
- [x] Add non-interactive `insert_entry` GUI API using explicit `overwrite` flag.
- [x] Add non-interactive `generate_entry` GUI API using explicit `overwrite` flag.
- [x] Add non-interactive `edit_entry` GUI API that re-encrypts confirmed content.
- [x] Add non-interactive `move_entry` GUI API using explicit `overwrite` flag.
- [x] Add non-interactive `delete_entry` GUI API using explicit `recursive` flag.
- [x] Add Rust unit tests for GUI API list/read/insert/generate/delete using temp password stores:
  - [x] list
  - [x] read
  - [x] insert
  - [x] generate
  - [x] delete
- [x] Add Rust tests proving path traversal is rejected through GUI APIs.

## Milestone 2: Flutter/Rust Native Bridge

Goal: connect Flutter to Rust core directly.

- [x] Choose bridge tooling and version, with `flutter_rust_bridge` v2 as the default candidate.
  - Selected milestone-2 tooling: `flutter_rust_bridge` v2.12.0 generates the Dart/Rust bridge surface from `bridge/src/api.rs`.
- [x] Add Rust crate or module for bridge entrypoints:
  - [x] Decide between embedding bridge code inside `gui/` or a separate `pars-bridge` crate.
  - [x] Ensure bridge crate depends on `pars-core`, not `pars-cli`.
- [x] Add bridge code generation configuration.
- [x] Add bridge build scripts for:
  - [x] Android
  - [x] iOS
  - [x] macOS
  - [x] Windows
  - [x] Linux
  - [x] Consolidated scripts to one Unix-like build entrypoint and one Windows entrypoint.
- [x] Expose async Rust functions to Dart:
  - [x] `load_config`
  - [x] `save_config`
  - [x] `list_stores`
  - [x] `list_entries`
  - [x] `read_entry`
  - [x] `copy_entry_password`
  - [x] `insert_entry`
  - [x] `generate_entry`
  - [x] `edit_entry`
  - [x] `move_entry`
  - [x] `delete_entry`
  - [x] `git_status`
  - [x] `git_pull`
  - [x] `git_push`
  - [x] `git_commit`
  - [x] `run_git_args`
- [x] Map Rust errors to Dart typed failures.
- [x] Ensure secrets do not get logged by bridge debug output.
- [x] Add Dart integration tests using mocked bridge implementations.
- [x] Add Rust bridge smoke tests for generated API compilation.

## Milestone 3: Configuration and Store Lifecycle

Goal: replace demo repository state with real config and store discovery.

- [x] Create Flutter repository interface:
  - [x] `VaultRepository`
  - [x] `SettingsRepository`
  - [x] `KeyRepository`
  - [x] `GitRepository`
- [x] Replace `DemoVaultRepository` with bridge-backed implementation.
- [x] Keep a fake implementation for widget tests.
- [x] Implement config load/save through `pars-core`.
- [x] Implement first-run detection:
  - [x] no config
  - [x] config exists but store missing
  - [x] store exists but missing `.gpg-id`
  - [x] Git remote missing
  - [x] PGP key missing
- [x] Implement password store selection.
- [x] Implement local store creation.
- [x] Implement existing local store import.
- [x] Implement Git clone store flow.
- [x] Implement remove-store-from-app flow.
- [x] Implement delete-local-store flow with strong confirmation.
- [x] Add tests for onboarding branches and recovery states.

## Milestone 4: GPG/OpenPGP Backend Strategy and Packaging

Goal: make PGP work on end-user devices without requiring the user to manually install system GPG first.

Decision: support both behind a Rust backend trait. Use system/bundled GPG first on desktop, and target a pure Rust OpenPGP backend first on mobile. Details live in [PGP Backend Strategy](../specs/2026-06-23-pgp-backend-strategy.md).

- [x] Define `PgpBackend` trait in Rust:
  - [x] decrypt file
  - [x] encrypt content
  - [x] generate key
  - [x] import public key
  - [x] import private key
  - [x] export public key
  - [x] export private key
  - [x] list keys
  - [x] inspect fingerprint
  - [x] validate `.gpg-id`
- [x] Add backend selection config:
  - [x] bundled backend
  - [x] system `gpg` backend
  - [x] future pure Rust backend
- [x] Investigate bundled GnuPG feasibility per platform:
  - [x] Android binary/library packaging
  - [x] iOS subprocess and dynamic linking restrictions
  - [x] macOS app bundle packaging
  - [x] Windows app bundle packaging
  - [x] Linux AppImage/Flatpak/deb/rpm packaging
- [x] Decide whether mobile uses bundled GPG or a Rust OpenPGP implementation first.
- [x] If bundling GPG, document required packaging gates:
  - [x] vendor reproducible GPG build scripts
  - [x] add license notices
  - [x] add binary integrity checks
  - [x] add runtime path resolution
  - [x] add sandbox-compatible keyring/home directory handling
- [x] If using pure Rust OpenPGP, document compatibility gates:
  - [x] verify compatibility with existing `pass` stores
  - [x] verify supported key algorithms
  - [x] verify private-key import/export behavior
  - [x] verify `.gpg-id` compatibility
- [x] Add migration path for users who already have system GPG.
- [x] Add tests for backend selection, `.gpg-id` validation, and backend trait coverage. Generated-key/encrypted-entry integration continues to be covered by existing GPG tests.

## Milestone 5: Key Management

Goal: make PGP and SSH keys real, not just settings UI.

- [x] Implement PGP key list screen with real data.
- [x] Implement PGP key generation.
- [x] Implement PGP public key import.
- [x] Implement PGP private key import from file.
- [x] Implement PGP private key import from pasted armored text.
- [x] Implement PGP public key export/copy.
- [x] Implement PGP private key export with strong confirmation.
- [x] Implement add selected PGP public key to `.gpg-id`.
- [x] Implement SSH key list screen with real data.
- [x] Implement SSH ed25519 key generation.
- [x] Implement SSH private key import from file.
- [x] Implement SSH private key import from pasted text.
- [x] Implement SSH public key copy/export.
- [x] Implement SSH private key export with strong confirmation.
- [x] Implement open GitHub SSH settings action.
- [x] Add tests for key import detection:
  - [x] PGP public key
  - [x] PGP private key
  - [x] SSH private key
  - [x] invalid pasted text
- [x] Ensure private key material is never printed in logs or crash text.

## Milestone 6: Local Unlock, Biometrics, and Secret Storage

Goal: protect local app access and optional PGP passphrase caching.

- [x] Implement 9-dot gesture capture widget.
- [x] Implement gesture confirmation flow.
- [x] Store gesture verifier securely.
- [x] Implement app lock state.
- [x] Implement lock on app resume option.
- [x] Implement auto-lock timeout.
- [x] Add biometric unlock support:
  - [x] Android
  - [x] iOS
  - [x] desktop fallback or disabled state
- [x] Add KMS/Keychain storage for PGP passphrase:
  - [x] Android Keystore
  - [x] iOS Keychain/Secure Enclave where available
  - [x] macOS Keychain
  - [x] Windows Credential Manager or DPAPI
  - [x] Linux Secret Service fallback
- [x] Implement optional one-step unlock:
  - [x] biometric unlock opens app
  - [x] if enabled, retrieve PGP passphrase from platform secret storage
  - [x] start PGP session without asking passphrase again
- [x] Implement PGP session auth expiration:
  - [x] immediately
  - [x] 5 minutes
  - [x] 15 minutes
  - [x] 1 hour
  - [x] until app exit
- [x] Clear decrypted secrets when:
  - [x] app locks
  - [x] session expires
  - [x] detail sheet closes
  - [x] app goes background if configured
- [x] Add widget and unit tests for lock/session state transitions.

## Milestone 7: Vault Real Data

Goal: make Vault operate on real password-store entries.

- [x] Replace demo entries with bridge-backed entry list.
- [x] Implement directory tree browsing from store paths.
- [x] Implement search by entry name/path.
- [x] Implement recent entries persistence.
- [x] Implement favorites persistence.
- [x] Implement Git status indicator from real Git state.
- [x] Implement pull-to-refresh sync.
- [x] Implement entry detail decrypt flow.
- [x] Implement passphrase prompt when PGP session is locked.
- [x] Implement decrypt failure recovery actions:
  - [x] retry
  - [x] choose/import key
  - [x] open key management
- [x] Move Dart parser responsibility to shared Rust core or ensure Rust/Dart parser behavior is identical.
- [x] Implement copy password with clipboard timeout.
- [x] Implement copy parsed fields.
- [x] Implement open URL action.
- [x] Implement QR code display.
- [x] Add tests for real bridge-backed Vault states using fake bridge.

## Milestone 8: Manage Real Operations

Goal: make Manage create, modify, delete, and batch-update real entries.

- [x] Implement generate-and-save flow.
- [x] Implement save-existing-password flow.
- [x] Implement edit-entry flow.
- [x] Implement raw notes editor.
- [x] Implement replace-first-line password while preserving notes.
- [x] Implement move entry.
- [x] Implement rename entry.
- [x] Implement delete entry with full-path confirmation.
- [x] Implement batch selection mode.
- [x] Implement batch move.
- [x] Implement batch rename where applicable.
- [x] Implement batch delete with preview.
- [x] Implement batch regenerate with preview.
- [x] Implement conflict handling:
  - [x] target exists
  - [x] invalid path
  - [x] path traversal attempt
  - [x] missing `.gpg-id`
- [x] Implement optional Git commit after Manage operation.
- [x] Show operation result summary.
- [x] Add Rust tests for each core operation through GUI API.
- [x] Add Flutter tests for each Manage flow with fake bridge.

## Milestone 9: Git Real Operations

Goal: make Git settings and sync work safely.

- [x] Implement real Git status summary.
- [x] Implement pull.
- [x] Implement push.
- [x] Implement commit.
- [x] Implement remote list.
- [x] Implement remote add/edit/remove.
- [x] Implement auto pull on app open.
- [x] Implement optional push after commit.
- [x] Implement re-clone/re-pull store recovery flow.
- [x] Implement delete local repo with strong confirmation.
- [x] Implement advanced Git args runner:
  - [x] only accepts args after `git`
  - [x] rejects shell separators
  - [x] rejects pipes
  - [x] rejects redirection
  - [x] rejects command substitution patterns
  - [x] runs only in selected store path
  - [x] core returns full command, stdout, stderr, and exit status
  - [x] displays full command before execution
  - [x] displays stdout/stderr/exit status after execution
- [x] Add tests proving shell syntax is rejected.
- [x] Add tests for failed Git command output rendering.

## Milestone 10: Onboarding Completion

Goal: make first-run setup functional end-to-end.

- [x] Implement complete onboarding state machine.
- [x] Step 1: gesture lock setup.
- [x] Step 2: optional biometric setup.
- [x] Step 3: choose/create/clone store.
- [x] Step 4: choose/create/import PGP key.
- [x] Step 5: optional SSH key setup for GitHub.
- [x] Step 6: review and confirm.
- [x] Persist onboarding completion.
- [x] Support resuming interrupted onboarding.
- [x] Support resetting onboarding from Settings.
- [x] Add tests for each onboarding branch.

## Milestone 11: Platform Packaging

Goal: produce installable apps with native Rust and crypto dependencies included.

- [x] Define supported phase-1 platforms:
  - [x] Android
  - [x] iOS
  - [x] macOS
  - [x] Windows
  - [x] Linux
- [x] Add CI jobs for Flutter/Rust bridge builds.
- [x] Add Android Rust target setup.
- [x] Add iOS Rust target setup.
- [x] Add desktop Rust target setup.
- [x] Package native Rust library with Flutter app.
- [x] Package GPG/OpenPGP backend artifacts.
- [x] Include license notices for bundled crypto/Git components.
- [x] Add runtime diagnostics screen:
  - [x] bridge loaded
  - [x] core version
  - [x] PGP backend
  - [x] Git backend
  - [x] key storage backend
- [x] Add smoke tests for release builds.

## Milestone 12: Security Review and Hardening

Goal: make the app acceptable for real password-manager use.

- [x] Threat model local attacker scenarios.
- [x] Threat model compromised clipboard scenarios.
- [x] Threat model malicious password-store path scenarios.
- [x] Threat model malicious Git remote scenarios.
- [x] Audit logging to ensure no secrets are printed.
- [x] Audit bridge serialization for secret leakage.
- [x] Ensure private keys and passphrases are zeroized where possible.
- [x] Ensure decrypted entry content has bounded lifetime.
- [x] Review platform secure storage usage.
- [x] Review bundled GPG/OpenPGP update story.
- [x] Add security regression tests for path traversal and shell injection.

## Milestone 13: UX Polish After Real Logic

Goal: refine experience once real operations exist.

- [x] Add loading states for every bridge-backed screen.
- [x] Add empty states for no store/no entries/no keys.
- [x] Add recoverable error states.
- [x] Add operation progress for Git and PGP operations.
- [x] Add accessibility labels for icon-only buttons.
- [x] Add compact mobile layout audit.
- [x] Add dark mode if needed.
- [x] Add localization-ready strings if needed.
- [x] Run app manually on phone-sized devices.

## Execution Order

Recommended implementation order:

1. [x] `pars-core` GUI API boundary.
2. [x] Flutter/Rust native bridge.
3. [x] Config and store lifecycle.
4. [x] PGP backend strategy and packaging decision.
5. [x] Key management.
6. [x] Local unlock, biometrics, and secret storage.
7. [x] Vault real data.
8. [x] Manage real operations.
9. [x] Git real operations.
10. [x] Full onboarding.
11. [x] Platform packaging.
12. [x] Security review and hardening.
13. [x] UX polish.

## Definition of Done

The GUI is no longer "just a shell" when all of the following are checked:

- [x] Fresh install can complete onboarding on a supported mobile platform.
- [x] User can create/import PGP keys.
- [x] User can clone or create a password store.
- [x] User can list real entries from the store.
- [x] User can decrypt and copy a real password.
- [x] User can generate and save a new password.
- [x] User can edit and delete real entries.
- [x] User can sync with Git.
- [x] User can configure SSH keys for GitHub.
- [x] User can unlock with gesture and optionally biometrics.
- [x] Optional KMS/Keychain PGP passphrase storage works.
- [x] PGP session expiration works.
- [x] Bundled or configured OpenPGP backend works on target platforms.
- [x] `flutter test`, `flutter analyze`, Rust tests, and bridge build checks pass.
