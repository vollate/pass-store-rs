# Pars GUI Native Roadmap

Date: 2026-06-22
Owner: GUI/native integration workstream
Status: active roadmap

This roadmap tracks the remaining work needed to turn the current Flutter GUI shell into a functional mobile password manager. Check each item when it is actually implemented, tested, and merged. The current UI shell is useful, but it is not the product: real functionality must call `pars-core` directly through a native Rust bridge rather than shelling out to `pars-cli`.

## Ground Rules

- [x] Mobile GUI design documented.
- [x] Phase 1 Flutter UI shell implemented with demo data.
- [ ] Do not execute `pars-cli` from Flutter for normal product behavior.
- [ ] Expose stable Rust APIs from `pars-core` for GUI use.
- [x] Use `flutter_rust_bridge` or an equivalent Flutter/Rust native bridge for Dart-to-Rust calls.
- [ ] Keep CLI-specific prompting, terminal I/O, and colorized tree output out of the GUI API.
- [ ] Treat bundled GPG/OpenPGP support as a first-class platform packaging problem, not a late afterthought.
- [ ] Update this roadmap checkbox-by-checkbox as tasks are completed.

## Milestone 0: Current State Baseline

- [x] `Vault / Manage / Settings` bottom navigation exists.
- [x] Gesture-lock onboarding mock exists.
- [x] Vault list/search/detail bottom sheet exists.
- [x] Pass entry parser demo exists in Dart.
- [x] Manage mock workflows exist.
- [x] Settings mock surfaces for security, keys, store, Git, and advanced Git args exist.
- [x] Flutter widget tests exist for the mock shell.
- [x] `flutter test` and `flutter analyze` passed for phase 1.
- [ ] GUI state is backed by real password-store data.
- [ ] GUI operations mutate real password-store files.
- [ ] GUI operations use real PGP encryption/decryption.
- [ ] GUI operations use real Git status/pull/push/commit.
- [ ] GUI auth and key storage use real platform APIs.

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
- [ ] Store gesture verifier securely.
- [x] Implement app lock state.
- [x] Implement lock on app resume option.
- [x] Implement auto-lock timeout.
- [ ] Add biometric unlock support:
  - [ ] Android
  - [ ] iOS
  - [x] desktop fallback or disabled state
- [ ] Add KMS/Keychain storage for PGP passphrase:
  - [ ] Android Keystore
  - [ ] iOS Keychain/Secure Enclave where available
  - [ ] macOS Keychain
  - [ ] Windows Credential Manager or DPAPI
  - [ ] Linux Secret Service fallback
- [ ] Implement optional one-step unlock:
  - [ ] biometric unlock opens app
  - [ ] if enabled, retrieve PGP passphrase from platform secret storage
  - [ ] start PGP session without asking passphrase again
- [ ] Implement PGP session auth expiration:
  - [ ] immediately
  - [ ] 5 minutes
  - [ ] 15 minutes
  - [ ] 1 hour
  - [ ] until app exit
- [ ] Clear decrypted secrets when:
  - [ ] app locks
  - [ ] session expires
  - [ ] detail sheet closes
  - [ ] app goes background if configured
- [x] Add widget and unit tests for lock/session state transitions.

## Milestone 7: Vault Real Data

Goal: make Vault operate on real password-store entries.

- [ ] Replace demo entries with bridge-backed entry list.
- [ ] Implement directory tree browsing from store paths.
- [ ] Implement search by entry name/path.
- [ ] Implement recent entries persistence.
- [ ] Implement favorites persistence.
- [ ] Implement Git status indicator from real Git state.
- [ ] Implement pull-to-refresh sync.
- [ ] Implement entry detail decrypt flow.
- [ ] Implement passphrase prompt when PGP session is locked.
- [ ] Implement decrypt failure recovery actions:
  - [ ] retry
  - [ ] choose/import key
  - [ ] open key management
- [ ] Move Dart parser responsibility to shared Rust core or ensure Rust/Dart parser behavior is identical.
- [ ] Implement copy password with clipboard timeout.
- [ ] Implement copy parsed fields.
- [ ] Implement open URL action.
- [ ] Implement QR code display.
- [ ] Add tests for real bridge-backed Vault states using fake bridge.

## Milestone 8: Manage Real Operations

Goal: make Manage create, modify, delete, and batch-update real entries.

- [ ] Implement generate-and-save flow.
- [ ] Implement save-existing-password flow.
- [ ] Implement edit-entry flow.
- [ ] Implement raw notes editor.
- [ ] Implement replace-first-line password while preserving notes.
- [ ] Implement move entry.
- [ ] Implement rename entry.
- [ ] Implement delete entry with full-path confirmation.
- [ ] Implement batch selection mode.
- [ ] Implement batch move.
- [ ] Implement batch rename where applicable.
- [ ] Implement batch delete with preview.
- [ ] Implement batch regenerate with preview.
- [ ] Implement conflict handling:
  - [ ] target exists
  - [ ] invalid path
  - [ ] path traversal attempt
  - [ ] missing `.gpg-id`
- [ ] Implement optional Git commit after Manage operation.
- [ ] Show operation result summary.
- [ ] Add Rust tests for each core operation through GUI API.
- [ ] Add Flutter tests for each Manage flow with fake bridge.

## Milestone 9: Git Real Operations

Goal: make Git settings and sync work safely.

- [ ] Implement real Git status summary.
- [ ] Implement pull.
- [ ] Implement push.
- [ ] Implement commit.
- [ ] Implement remote list.
- [ ] Implement remote add/edit/remove.
- [ ] Implement auto pull on app open.
- [ ] Implement optional push after commit.
- [ ] Implement re-clone/re-pull store recovery flow.
- [ ] Implement delete local repo with strong confirmation.
- [ ] Implement advanced Git args runner:
  - [x] only accepts args after `git`
  - [x] rejects shell separators
  - [x] rejects pipes
  - [x] rejects redirection
  - [x] rejects command substitution patterns
  - [x] runs only in selected store path
  - [x] core returns full command, stdout, stderr, and exit status
  - [ ] displays full command before execution
  - [ ] displays stdout/stderr/exit status after execution
- [x] Add tests proving shell syntax is rejected.
- [ ] Add tests for failed Git command output rendering.

## Milestone 10: Onboarding Completion

Goal: make first-run setup functional end-to-end.

- [ ] Implement complete onboarding state machine.
- [ ] Step 1: gesture lock setup.
- [ ] Step 2: optional biometric setup.
- [ ] Step 3: choose/create/clone store.
- [ ] Step 4: choose/create/import PGP key.
- [ ] Step 5: optional SSH key setup for GitHub.
- [ ] Step 6: review and confirm.
- [ ] Persist onboarding completion.
- [ ] Support resuming interrupted onboarding.
- [ ] Support resetting onboarding from Settings.
- [ ] Add tests for each onboarding branch.

## Milestone 11: Platform Packaging

Goal: produce installable apps with native Rust and crypto dependencies included.

- [ ] Define supported phase-1 platforms:
  - [ ] Android
  - [ ] iOS
  - [ ] macOS
  - [ ] Windows
  - [ ] Linux
- [ ] Add CI jobs for Flutter/Rust bridge builds.
- [ ] Add Android Rust target setup.
- [ ] Add iOS Rust target setup.
- [ ] Add desktop Rust target setup.
- [ ] Package native Rust library with Flutter app.
- [ ] Package GPG/OpenPGP backend artifacts.
- [ ] Include license notices for bundled crypto/Git components.
- [ ] Add runtime diagnostics screen:
  - [ ] bridge loaded
  - [ ] core version
  - [ ] PGP backend
  - [ ] Git backend
  - [ ] key storage backend
- [ ] Add smoke tests for release builds.

## Milestone 12: Security Review and Hardening

Goal: make the app acceptable for real password-manager use.

- [ ] Threat model local attacker scenarios.
- [ ] Threat model compromised clipboard scenarios.
- [ ] Threat model malicious password-store path scenarios.
- [ ] Threat model malicious Git remote scenarios.
- [ ] Audit logging to ensure no secrets are printed.
- [ ] Audit bridge serialization for secret leakage.
- [ ] Ensure private keys and passphrases are zeroized where possible.
- [ ] Ensure decrypted entry content has bounded lifetime.
- [ ] Review platform secure storage usage.
- [ ] Review bundled GPG/OpenPGP update story.
- [ ] Add security regression tests for path traversal and shell injection.

## Milestone 13: UX Polish After Real Logic

Goal: refine experience once real operations exist.

- [ ] Add loading states for every bridge-backed screen.
- [ ] Add empty states for no store/no entries/no keys.
- [ ] Add recoverable error states.
- [ ] Add operation progress for Git and PGP operations.
- [ ] Add accessibility labels for icon-only buttons.
- [ ] Add compact mobile layout audit.
- [ ] Add dark mode if needed.
- [ ] Add localization-ready strings if needed.
- [ ] Run app manually on phone-sized devices.

## Execution Order

Recommended implementation order:

1. [x] `pars-core` GUI API boundary.
2. [x] Flutter/Rust native bridge.
3. [ ] Config and store lifecycle.
4. [x] PGP backend strategy and packaging decision.
5. [x] Key management.
6. [ ] Local unlock, biometrics, and secret storage.
7. [ ] Vault real data.
8. [ ] Manage real operations.
9. [ ] Git real operations.
10. [ ] Full onboarding.
11. [ ] Platform packaging.
12. [ ] Security review and hardening.
13. [ ] UX polish.

## Definition of Done

The GUI is no longer "just a shell" when all of the following are checked:

- [ ] Fresh install can complete onboarding on a supported mobile platform.
- [ ] User can create/import PGP keys.
- [ ] User can clone or create a password store.
- [ ] User can list real entries from the store.
- [ ] User can decrypt and copy a real password.
- [ ] User can generate and save a new password.
- [ ] User can edit and delete real entries.
- [ ] User can sync with Git.
- [ ] User can configure SSH keys for GitHub.
- [ ] User can unlock with gesture and optionally biometrics.
- [ ] Optional KMS/Keychain PGP passphrase storage works.
- [ ] PGP session expiration works.
- [ ] Bundled or configured OpenPGP backend works on target platforms.
- [ ] `flutter test`, `flutter analyze`, Rust tests, and bridge build checks pass.
