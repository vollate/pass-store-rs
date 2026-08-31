## Why

The GUI exposes a multi-repository registry even though users need one immediately available password store, forcing unnecessary switching and leaving the authenticated shell visible after the final store is removed. Store import, onboarding, and key management also treat Git and PGP administration as permanent prerequisites instead of optional or contextual capabilities.

## What Changes

- Adopt a single-password-store GUI model with no store list, store switcher, default-store action, or automatic fallback to another configured repository.
- Migrate legacy multi-store configuration by retaining the current default store as the sole GUI store without deleting any other directories; keep the CLI `-R/--repo` override available for advanced command-line use.
- Derive application routing from separate security, lock, store-availability, and store-repair states so deleting or disconnecting the current store immediately leaves the authenticated shell and opens store setup.
- Keep Create, Import, and Clone as store-setup paths, with Create presented as a secondary path for users without an existing password store.
- Make onboarding store-first after local security setup: inspect the selected store's `.gpg-id`, request only matching private-key repair when required, and request SSH setup only for SSH-based clone or remote operations.
- Remove permanent PGP key CRUD from Settings while retaining PGP passphrase/session controls and contextual missing-key repair; retain SSH key management under Git synchronization.
- Make Git optional: a password store without `.git` remains fully usable for Vault, encryption, and Autofill, while Git and remote actions report an intentional local-only state rather than a failure. Use Rust libgit2 for structured GUI/mobile Git operations where a system `git` executable is unavailable; keep CLI and working desktop system-Git behavior unchanged.
- Make Import copy the complete visible tree atomically, including `.git`, `.gpg-id`, and dotfiles. Preserve valid Git metadata unchanged; when `.git` is absent, ask whether to initialize Git, continue without Git, or cancel; reject present-but-invalid Git metadata instead of silently replacing it.
- Preserve the imported store's `.gpg-id`; do not append an arbitrary onboarding key. Creating a new store may write its selected recipients, while recipient rotation remains a separate explicit migration concern.
- Clear decrypted presentation, store-scoped Favorite metadata, PGP session state, and native/shared Autofill state before completing store removal or replacement.
- **BREAKING**: Replace GUI-facing multi-store bridge contracts (list/select/default fallback semantics) with a single-store lifecycle contract. Generated Flutter bridge APIs and affected DTOs will change; TOML `repos` remains temporarily as a deprecated zero-or-one compatibility mirror so older CLI builds can still resolve the selected path.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `store-lifecycle`: Replace multi-store registration and selection with one optional store, loss-aware import, optional Git, legacy migration, and immediate no-store transitions.
- `configuration-and-runtime`: Make one canonical store path authoritative while normalizing the legacy `repos` list to a zero-or-one compatibility mirror and preserving CLI repository overrides.
- `flutter-security-and-onboarding`: Make setup store-first and contextual, remove permanent PGP key CRUD, retain SSH management under Git, and separate security completion from store readiness.
- `flutter-vault-and-manage`: Route out of the shell when the sole store disappears and present local-only/Git-backed status truthfully.
- `git-integration`: Treat Git as optional, preserve imported Git metadata, and support explicit Git initialization without blocking local-only stores.
- `pgp-and-key-management`: Stop automatically appending arbitrary selected keys to imported stores and constrain GUI PGP import to setup or required-recipient repair.
- `native-bridge-api`: Replace multi-store bridge methods and DTO fields with single-store lifecycle, import inspection, and Git-state results.
- `mobile-system-autofill`: Clear published index and native security state when the sole store is removed or replaced.

## Impact

- Core configuration and migration: `core/src/config/cli.rs`, sample config, CLI config tests, and bridge config mutation helpers.
- Dependencies and transport: add Rust `git2`/libgit2 for structured GUI/mobile repository operations with verified HTTPS certificates and app-managed SSH key callbacks; arbitrary Git args remain unsupported on mobile.
- Rust bridge lifecycle/API: `bridge/src/api.rs`, generated FRB bindings, method declarations, smoke tests, and error/DTO contracts.
- Flutter root routing and repositories: `gui/lib/app/pars_gui_app.dart`, lifecycle/settings/Git/key/autofill repositories, onboarding, Settings, Vault status, localization, and tests.
- Native import and Autofill cleanup: Android managed-store importer and Autofill state, plus iOS shared Autofill state where applicable.
- Existing multi-store directories remain untouched during migration; only the configured GUI selection is collapsed to the prior default store.
