## 1. Characterization and Test Fixtures

- [x] 1.1 Add legacy configuration fixtures covering multiple `repos`, a valid `default_repo`, an empty default, missing roots, and ignored directories that must remain untouched.
- [x] 1.2 Add a synthetic password-store Git fixture containing `.gpg-id`, encrypted entry placeholders, multiple commits, a named branch, refs, objects, config, and a remote.
- [x] 1.3 Add synthetic local-only and invalid-Git store fixtures that distinguish absent `.git` from present-but-unusable `.git` metadata.
- [x] 1.4 Add characterization tests for the current final-store deletion, app routing, import registration, PGP recipient attachment, and Git-status behavior before replacing those contracts.

## 2. Canonical Store Configuration and Lifecycle Model

- [x] 2.1 Make `path_config.default_repo` the canonical GUI store path and normalize compatibility `repos` writes to zero or one matching path.
- [x] 2.2 Load legacy multi-store config by retaining the non-empty prior default, or the first non-empty legacy path only when the default is empty, without touching other directories.
- [x] 2.3 Update sample config, serialization, equality, and config round-trip tests for the zero-or-one `repos` compatibility mirror.
- [x] 2.4 Add a singular lifecycle snapshot with one optional canonical store instead of selected IDs plus a store list.
- [x] 2.5 Add typed store Git modes for disabled, local, remote, and invalid, separate from operational Git status.
- [x] 2.6 Derive no-store, missing-`.gpg-id`, missing-private-key, invalid-Git, and ready lifecycle states from the singular snapshot.
- [x] 2.7 Add migration tests proving the former default is retained, ignored roots are not deleted, and deleting the canonical root never falls back to another legacy path.

## 3. Singular Rust Bridge Contracts

- [x] 3.1 Replace multi-store app-state DTO fields with one optional `StoreStatusDto`, typed Git mode, issues, and derived lifecycle state.
- [x] 3.2 Refactor app-state inspection to normalize legacy config in memory and inspect only the canonical store.
- [x] 3.3 Refactor Create, registration-only Import, and Clone requests to establish the sole canonical root and remove `set_default` parameters.
- [x] 3.4 Add a singular Disconnect operation that clears canonical config without deleting an externally owned directory.
- [x] 3.5 Harden app-managed Delete local copy by verifying the canonical root is inside the supplied managed-store base before recursive deletion.
- [x] 3.6 Preserve delete-first/config-second retry semantics while clearing both canonical path and compatibility mirror after success.
- [x] 3.7 Remove list-stores, select-store, and automatic default-fallback methods from the GUI bridge and `SUPPORTED_METHODS`.
- [x] 3.8 Remove general Flutter PGP export, delete, and arbitrary append-to-`.gpg-id` methods while retaining contextual list/inspect/import/generate/prepare and SSH CRUD methods.
- [x] 3.9 Regenerate Rust and Dart FRB bindings, update bridge tooling declarations, and remove obsolete request/response adapters.
- [x] 3.10 Update bridge smoke and unit tests for singular lifecycle methods, removed methods, typed Git mode, compatibility config, and sanitized failures.
- [x] 3.11 Add Rust `git2`/libgit2 structured GUI/mobile repository discovery, validation, init, clone, status, remotes, commit, pull, and push with default HTTPS verification and app-managed SSH key callbacks; keep CLI/desktop system Git where already working.

## 4. Staged Loss-Aware Store Import

- [x] 4.1 Define a platform/Dart staged-import transaction with opaque handle, explicit Git decisions, and commit/rollback around Rust registration.
- [x] 4.2 Stage app-managed non-Android folder imports with all visible files/dotfiles; inspect and directly register externally owned desktop folders without copying them.
- [x] 4.3 Refactor Android `ManagedStoreImporter` to return staged import state without finalizing the destination before Flutter resolves Git mode.
- [x] 4.4 Preserve provider-visible `.git`, `.gpg-id`, refs, objects, config, and other dotfiles while retaining path-escape, depth, cycle, duplicate-name, link, and cancellation defenses.
- [x] 4.5 Validate staged Git with Git itself and classify valid work tree, absent `.git`, and present-but-invalid `.git` without relying only on directory existence.
- [x] 4.6 For valid Git, finalize atomically without running `git init` and verify history, branch, status, and remotes remain available.
- [x] 4.7 For absent Git, present Initialize Git, Continue without Git, and Cancel before finalization, including the Android hidden-metadata warning.
- [x] 4.8 Run `git init` only inside staging after explicit consent and finalize only after initialization succeeds, without adding a remote or SSH prerequisite.
- [x] 4.9 Finalize an explicitly local-only import with Git disabled and keep Vault, encryption, and Autofill available.
- [x] 4.10 Abort present-but-invalid Git without reinitializing, discarding metadata, replacing the destination, or registering the store.
- [x] 4.11 Replace import merge behavior with atomic Replace or Cancel and restore the prior destination if finalization fails.
- [x] 4.12 Delete staging and backup artifacts on cancel, failure, or completed replacement without exposing private app paths in ordinary errors.
- [x] 4.13 Add Dart import tests for valid Git preservation, each absent-Git decision, invalid Git, replacement rollback, dotfiles, and source immutability.
- [x] 4.14 Add Android instrumented synthetic-provider tests covering actual nested `.git` copying, absent-Git decisions, finalization rollback, loading retries, and cancellation cleanup.

## 5. Optional Git Repository Behavior

- [x] 5.1 Extend Flutter Git models and localized status mapping to represent disabled, local, remote, and invalid modes independently from clean/uncommitted/pull-needed/busy/failed status.
- [x] 5.2 Skip status, remote, pull, push, advanced-args, and optional commit dispatch when Git mode is disabled.
- [x] 5.3 Keep Vault mutations successful without Git warnings when Git is disabled, while preserving durable post-mutation warnings when enabled Git commits fail.
- [x] 5.4 Treat valid local Git without a remote as neutral local mode and disable only remote-dependent actions.
- [x] 5.5 Add Settings Enable Git for a local-only canonical store and transition to local mode without requiring a remote.
- [x] 5.6 Keep failed Git initialization non-destructive and leave the password store usable in disabled mode.
- [x] 5.7 Gate SSH setup and management on SSH-form clone or remote configuration while allowing HTTPS and no-remote operation.
- [x] 5.8 Add repository and widget tests proving disabled Git dispatches no commands, local Git is not sync failure, remote Git enables sync, and invalid Git remains an error.
- [x] 5.9 Return typed Unsupported for arbitrary Git args on Android/iOS and hide or clearly disable the Flutter Advanced Git args action there; do not emulate arbitrary args through libgit2.

## 6. Store-First Onboarding and Contextual Keys

- [x] 6.1 Replace the fixed Gesture/Biometrics/PGP/SSH/Store/Review sequence with required local security followed by primary Import/Clone and secondary Create actions.
- [x] 6.2 Make Create choose, import, or generate recipients only while creating the new `.gpg-id`, with optional Git initialization and no required remote.
- [x] 6.3 Make Import and Clone inspect the finalized store's `.gpg-id` before showing any PGP repair UI.
- [x] 6.4 Filter contextual repair to usable private material matching a required `.gpg-id` recipient and reject public-only or unrelated keys as readiness evidence.
- [x] 6.5 Remove automatic onboarding calls that append a selected local key to an imported or cloned store's `.gpg-id`.
- [x] 6.6 Preserve the shared Text/File PGP inspection, exact-key protected import, transactional preparation, sanitized feedback, fingerprint-bound session, and opt-in durable passphrase behavior inside contextual setup/repair.
- [x] 6.7 Show SSH import/generation only when an SSH clone or remote needs it; allow HTTPS Clone without SSH.
- [x] 6.8 Enter Vault as soon as security and canonical store readiness are satisfied without requiring a fixed Review step.
- [x] 6.9 Remove the permanent Settings PGP key list and PGP create/import/export/delete/add-recipient actions while retaining PGP session/passphrase security controls.
- [x] 6.10 Move complete SSH key management under Git synchronization and preserve human-readable destructive confirmation for SSH deletion.
- [x] 6.11 Add onboarding and Settings tests for store-first ordering, Create/Import/Clone branches, matching-key repair, no `.gpg-id` mutation, HTTPS/SSH behavior, and absence of permanent PGP CRUD.

## 7. Root State, Removal, and Privacy Cleanup

- [x] 7.1 Introduce a root presentation state derived from security setup, lock requirement, canonical store availability, and required repair instead of one mutable onboarding-complete boolean.
- [x] 7.2 Add lifecycle notifications so successful store mutation refreshes can unmount `MobileShell` immediately.
- [x] 7.3 Preserve routing precedence for initial security setup, lock, no-store setup, store repair, and ready shell across startup, resume, unlock, and deletion.
- [x] 7.4 Present Delete local copy only for verified app-managed roots and Disconnect for externally owned roots.
- [x] 7.5 Before completing store removal presentation, close decrypted entry detail and clear query, selection, directory, scroll, and Favorite state belonging to the removed store.
- [x] 7.6 Clear the active PGP session and republish native Autofill security state without a store-bound passphrase while retaining durable preferences only in secure storage.
- [x] 7.7 Remove the shared Autofill index, enrichment metadata, Android candidates, and iOS credential identities when the canonical store is deleted, disconnected, or replaced.
- [x] 7.8 Require an explicit non-decrypting Autofill rebuild for a replacement store and prove it cannot inherit old paths, aliases, or ranking metadata.
- [x] 7.9 Preserve retryable canonical config when physical deletion fails and report the failure without claiming rollback or successful removal.
- [x] 7.10 Add app, repository, metadata, security, and Autofill tests for deletion-to-setup routing, lock precedence, external disconnect, cleanup ordering, failure retry, and replacement isolation.

## 8. Single-Store Settings and Vault Presentation

- [x] 8.1 Replace Password stores list/switch/default UI with one canonical Password store summary and contextual Disconnect or Delete local copy action.
- [x] 8.2 Remove alternate-store fallback labels, menus, and repository-selection state from Settings and repository models.
- [x] 8.3 Present password-store readiness separately from optional Git mode in Vault and Settings with neutral disabled/local states and truthful remote failures.
- [x] 8.4 Add concise progressively disclosed repair actions for missing `.gpg-id`, missing required private material, invalid Git, and failed import finalization.
- [x] 8.5 Localize all new single-store, Git-mode, import-decision, hidden-metadata warning, disconnect, cleanup, and repair strings in English and Chinese, including native resources where used.
- [x] 8.6 Add semantics, focus order, keyboard-safe layout, large-text behavior, and screen-reader labels for store-source actions, import decisions, Git mode, SSH management, and destructive confirmation.
- [x] 8.7 Update deterministic compact/expanded, light/dark, English/Chinese golden baselines affected by store-first onboarding and single-store Settings.
- [x] 8.8 Extend source audits to reject reintroduced store switchers, permanent PGP Settings CRUD, raw private paths, unlocalized strings, and empty production handlers.

## 9. End-to-End Verification

- [x] 9.1 Run Rust formatting, workspace Clippy, core tests, bridge unit tests, and bridge smoke tests including configuration migration and singular APIs.
- [x] 9.2 Run Dart formatting, Flutter Analyze, configured Dart LSP diagnostics, all Flutter tests, localization completeness, accessibility matrix, and golden verification.
- [x] 9.3 Run Android Kotlin/JUnit and instrumented import/Autofill tests and produce a release APK without replacing installed application data.
- [x] 9.4 Run the iOS simulator build and native tests covering shared Autofill cleanup and localized store states.
- [x] 9.5 On a synthetic-data Android emulator, verify valid `.git` import preserves log/branch/remote, missing `.git` supports Initialize/Continue/Cancel, and invalid `.git` never replaces the destination.
- [x] 9.6 On the emulator, delete the sole app-managed store and verify decrypted UI, metadata, Autofill candidates, and native passphrase publication clear before store setup appears.
- [x] 9.7 Verify legacy multi-store config selects only the prior default, preserves ignored directories, writes zero-or-one mirror, and never falls back after removal.
- [x] 9.8 Run strict OpenSpec validation for the change and all main specs, run `git diff --check`, and record commands, results, artifacts, residual risks, and APK hash in `verification.md`.
