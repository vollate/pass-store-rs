## Context

Pars currently carries `PathConfig.default_repo` plus `PathConfig.repos`, exposes every configured root through bridge list/select/remove APIs, and renders a password-store list in Settings. Removing the selected root falls back to the first remaining repository, while deleting the final root only refreshes the Settings surface; `ParsGuiApp` computes one `_isOnboardingComplete` boolean at startup and therefore can leave an empty authenticated shell mounted.

The onboarding sequence is also resource-independent: gesture, biometrics, PGP, SSH, then store. That order selects keys before the application knows the imported or cloned store's `.gpg-id`, and the current completion path can append the selected key to an existing store. Android folder import copies the entries exposed by a `DocumentsProvider`, but a provider can omit hidden `.git` data and the importer does not classify the copied result as valid Git, absent Git, or invalid Git.

The desired user model is one password store with optional Git backing. A store without Git is a valid local password store; a valid imported `.git` must be preserved; PGP setup is contextual to `.gpg-id`; and only SSH key management remains as a permanent key-management surface.

## Goals / Non-Goals

**Goals:**

- Present exactly one optional password store in the GUI and remove repository switching.
- Keep security setup, lock state, store availability, and store repair as independent root states.
- Return immediately to store setup after the sole store is disconnected or deleted.
- Preserve valid imported Git metadata and let users explicitly initialize Git or continue locally when it is absent.
- Treat no Git and no remote as intentional modes rather than onboarding failures.
- Make imported `.gpg-id` authoritative and expose PGP import/create only when setup or required-recipient repair needs it.
- Preserve older configuration compatibility without deleting unselected legacy directories.
- Fail closed for secrets and Autofill data while lifecycle transitions are in progress.

**Non-Goals:**

- Reintroducing profiles, accounts, or another form of multi-store switcher.
- Deleting legacy directories that are no longer selected by the GUI.
- Designing PGP recipient rotation or bulk re-encryption; that requires a separate explicit migration.
- Implementing hosted repository creation or interpreting arbitrary Git command arguments through a library backend. Structured GUI/mobile Git operations use libgit2; CLI and working desktop system-Git behavior remain unchanged.
- Adding ZIP/TAR repository import in this change. Clone remains the history-preserving fallback when an Android provider does not expose `.git`.
- Removing the CLI `-R/--repo` override.

## Decisions

### 1. The GUI has one canonical store, with a compatibility-only `repos` mirror

`path_config.default_repo` remains the canonical path because CLI execution already resolves it and existing configs contain it. `path_config.repos` remains serializable for a compatibility window, but normalized GUI writes SHALL contain either no paths or exactly `[default_repo]`; it is no longer a user-visible registry.

When loading a legacy config, a non-empty `default_repo` wins even if other `repos` entries exist. If it is empty, the first non-empty legacy entry may seed the canonical path. Other paths are ignored by the GUI and never deleted. The next successful lifecycle/config write normalizes the mirror to zero or one element.

This retains rollback compatibility with older CLI builds while removing list, selection, and fallback semantics from the product. Removing the TOML field immediately was rejected because an older build could then resolve the wrong default after rollback.

### 2. Root routing is derived from orthogonal state

The root controller derives one presentation state from current repository and security snapshots:

```text
needsSecuritySetup
locked
needsStore
needsStoreRepair
ready
```

Precedence is security setup, lock, store availability, store repair, then ready. Deleting a store while already unlocked therefore enters `needsStore` immediately; restarting after deletion still requires normal unlock before store setup.

`SettingsRepository` (or a dedicated lifecycle controller) SHALL publish lifecycle changes rather than relying on a one-time `_isOnboardingComplete` field. `MobileShell` reports successful disconnect/delete to that controller, and the root removes the shell once the refreshed snapshot has no store. Security onboarding completion is never reset solely because a store disappears.

Using a callback that simply sets onboarding to incomplete was rejected because it conflates local authentication with store availability and would replay unrelated setup steps.

### 3. Store setup starts with Create, Import, or Clone

After initial local security setup, the user first chooses a store source. Import and Clone are primary actions; Create remains a secondary action for new users.

- **Create:** choose, import, or generate a private PGP key as part of creating `.gpg-id`; Git initialization is optional and no remote is required. Create rejects every existing file, directory, or symlink, prepares the new store in unique sibling staging, exclusively reserves the final root without replacement, and removes only its own new tree on preparation or config failure.
- **Import:** stage the selected tree, classify Git, finalize the user's Git decision, then inspect `.gpg-id` and matching local private material.
- **Clone:** request SSH setup only for an SSH-form remote (`ssh://` or scp-like syntax). HTTPS clone does not require SSH setup. After clone, inspect `.gpg-id` before entering Vault.

An existing `.gpg-id` is never changed merely to match a locally selected key. If it names no locally available private key, the repair UI accepts only private material matching one of its recipients. If `.gpg-id` is absent, setup asks the user to choose/create/import recipients because the store cannot safely encrypt new entries.

The fixed PGP → SSH → Store → Review wizard was rejected because it asks for credentials without resource context and adds steps unrelated to HTTPS or local-only use.

### 4. Import is staged, loss-aware, and explicitly finalized

Import remains a two-phase app-managed operation:

1. Copy every provider-visible file and directory into a unique staging directory, preserving dot names such as `.git` and `.gpg-id`; reject links, cycles, path escape, duplicate names, and unsupported entries as today.
2. Inspect the staged result before replacing or registering the destination.

Git classification has three outcomes:

- **Valid Git:** Git recognizes the staged root as a work tree. Preserve `.git`, branch, refs, objects, config, and remote data byte-for-byte and finalize without running `git init`.
- **Absent Git:** no `.git` entry is present. Explain that the source may be local-only or the Android provider may have hidden metadata, and offer `Initialize Git`, `Continue without Git`, and `Cancel`. Initialization runs only inside staging; continuing records an intentional no-Git mode.
- **Invalid Git:** `.git` is present but Git cannot validate it, including copied worktree pointers that refer outside the import. Abort without replacing the destination or registering the store. Do not silently discard or reinitialize damaged metadata.

The user's decision occurs before the staged tree is atomically renamed into place. Cancel deletes staging. Replace uses an opaque platform transaction bound to the exact staging and destination paths. The backup remains until Rust registration and atomic config persistence succeed; registration failure triggers verified rollback, while success irrevocably marks the installed tree committed before backup cleanup. A cleanup-only failure may retry deleting the backup but can never restore it over the registered store. Merge is not offered because merging two `.git` trees cannot preserve coherent history. On desktop, an externally owned folder may be registered directly after inspection instead of copied; app-managed non-Android imports use the same staging transaction.

A strict requirement that every import contain Git was rejected because valid local-only password stores must remain usable. Automatically initializing whenever `.git` is absent was rejected because it can hide provider data loss and manufacture unrelated history.

### 5. Git capability and sync status are separate from store readiness

Bridge inspection returns a store Git mode such as `disabled`, `local`, `remote`, or `invalid`, separately from operational status such as clean, uncommitted, pull-needed, busy, or failed.

- `disabled` is a neutral local-only state. Repository refresh skips Git commands, mutation wrappers skip optional commits without warnings, and Vault remains fully usable.
- `local` means valid Git with no remote. Local status and commits may be used; missing remote is not an onboarding issue.
- `remote` enables pull, push, and remote status.
- `invalid` is a repair/error state and is never collapsed into disabled.

Settings presents `Enable Git` for disabled stores, remote configuration for local Git, and SSH key management only under Git synchronization. Advanced Git commands are unavailable when Git is disabled. This is preferable to mapping `git status` failure to `syncFailed`, which makes an intentional local store look broken.

### 6. Structured GUI/mobile Git uses Rust libgit2

GUI/mobile repository discovery, validation, initialization, clone, status, remotes, commit, pull, and push SHALL use Rust `git2`/libgit2 where a system `git` executable is not available. Existing CLI behavior and working desktop system-Git execution remain unchanged. HTTPS SHALL retain default certificate verification. SSH transport SHALL use explicit app-managed private-key paths through credential callbacks and SHALL NOT log key material or passphrases.

Arbitrary `run_git_args` remains a system-Git-only advanced operation. Android and iOS SHALL return a typed Unsupported result for it, and Flutter SHALL hide or clearly disable Advanced Git args on those platforms. Parsing arbitrary argument vectors into libgit2 operations was rejected because it would create a partial shell emulator with ambiguous behavior and security boundaries.

If libgit2 cannot be cross-compiled or a requested secure transport cannot be configured, implementation SHALL stop with exact build/transport evidence rather than silently falling back to nonexistent mobile system Git or disabling Clone.

### 7. PGP administration becomes contextual

The durable Settings PGP key list and its create/import/export/delete actions are removed. Internal key listing, inspection, protected import, and private-key preparation remain because setup, unlock, and repair need them. PGP passphrase/session settings remain under Security and bind only to a private key that satisfies the current store.

Contextual PGP UI appears only when:

- Create needs recipients for a new `.gpg-id`;
- Import/Clone finds `.gpg-id` recipients without matching private material;
- an imported store is missing `.gpg-id`; or
- runtime inspection detects required-key repair.

Singular store inspection returns the normalized `.gpg-id` recipients needed for UI-side exact-match filtering. A dedicated contextual bridge operation may create `.gpg-id` only when it is absent on the canonical store; it refuses to overwrite an existing recipient file. General PGP export, deletion, type-specific legacy import, and arbitrary recipient append remain outside the generated Flutter bridge.

Deleting arbitrary PGP key material is no longer exposed through Flutter Settings. SSH key create/import/export/delete remains available because remote access can be changed independently of password encryption.

Keeping the general PGP CRUD sheet was rejected because it allows users to remove active material or mutate recipient state without an entry re-encryption plan.

### 8. Store removal is fail-closed and has no fallback selection

Only app-managed roots expose physical `Delete local copy`; externally owned roots expose `Disconnect`. Both require explicit confirmation and, on success, produce an empty canonical path and empty compatibility mirror. They never select another legacy root.

Before invoking Rust Disconnect or Delete, the app enters a non-secret removing state, unmounts the authenticated shell and secret routes, serializes against in-flight refresh side effects, clears store-scoped Recent/Favorite metadata, clears the active PGP session, and disables native Autofill with a durable tombstone before attempting shared-index and credential-identity cleanup. Each enabled native publication uses an unguessable generation carried by candidates and identities; Android and iOS revalidate generation/root/index after native query or decryption so an in-flight old publication cannot return after tombstoning or same-root replacement. Durable local key records and secure-storage passphrase preferences are not deleted automatically; native publication remains disabled unless the current lifecycle is ready and the remembered fingerprint satisfies the current `.gpg-id`.

Physical deletion continues to delete app-owned files before clearing configuration. Only bridge success publishes no-store setup. If deletion fails, the store remains configured so the user can retry, but cleared presentation/session/index state remains fail-closed and the shell returns only after a non-decrypting refresh; Autofill requires an explicit rebuild. Replacement reconciliation is store-ID/root bound and can never carry old aliases or ranking into another root.

### 9. Bridge APIs become singular

The generated GUI bridge removes list/select/default-fallback semantics and exposes singular inspection plus create/import/clone/disconnect/delete operations. App-state DTOs carry one optional `StoreStatusDto` rather than selected IDs plus a list. Store mutation requests no longer accept `set_default`.

Platform/Dart import owns typed staging, Git classification, Preserve/Initialize/Continue/Cancel, commit, and rollback. Rust `import_local_store` is registration/inspection only and does not initialize Git. PGP `.gpg-id` append is removed from ordinary Flutter key management; new-store recipient writing remains part of Create, and existing-store repair imports matching private material without changing the recipient file.

Low-level CLI repository overrides and core PGP primitives remain available outside the GUI bridge where still required.

## Risks / Trade-offs

- **[Android provider hides `.git`]** → Warn before Git initialization, preserve staging until the user chooses, and direct users who need history to Clone rather than pretending history was imported.
- **[Large `.git` trees contain many small files]** → Keep bounded parallel copy, cancellation cleanup, depth/cycle limits, and atomic staging; validate with a synthetic repository containing refs and objects.
- **[Legacy users expect another store to become active]** → Keep the prior default only, never delete other roots, and make store setup explicit instead of silently switching context.
- **[Older builds read normalized config]** → Continue writing `repos = [default_repo]` during the compatibility window.
- **[No-Git stores trigger command failures]** → Represent disabled Git explicitly and prevent Git command dispatch rather than parsing failure text.
- **[libgit2 cross-compilation or transport support fails]** → Use vendored libgit2/OpenSSL where required, validate Android/iOS builds, preserve certificate verification and SSH key callbacks, and stop with evidence instead of falling back to broken mobile system Git.
- **[Removing PGP Settings reduces recovery discoverability]** → Surface repair directly when `.gpg-id` cannot be satisfied and retain bounded diagnostics describing the required recipient.
- **[Cleanup succeeds before store deletion fails]** → Keep the store configured, report the deletion failure, and allow non-decrypting Autofill rebuild after the user returns to the recovered store.
- **[External path deletion could destroy user data]** → Never physically delete non-app-managed roots from the GUI; disconnect them only.

## Migration Plan

1. Add single-store config normalization and DTOs while legacy config can still be read.
2. Update bridge lifecycle/import APIs and regenerate Rust/Dart bindings.
3. Add Rust `git2`/libgit2 for structured GUI/mobile repository discovery, validation, init, clone, status, remotes, commit, pull, and push; keep arbitrary args unsupported on mobile and preserve existing CLI/desktop system Git.
4. Introduce explicit Git mode and teach repositories, Vault, and mutation wrappers to skip Git when disabled.
5. Replace the root boolean with derived state and add lifecycle notifications.
6. Rebuild onboarding around store-source actions and contextual PGP/SSH repair.
7. Replace Settings store list and PGP CRUD with one store summary, optional Git controls, and SSH management.
8. Add rollback-capable Android and non-Android app-managed import transactions; keep inspected externally owned desktop folders as direct registrations.
9. Add removal cleanup across metadata, PGP session, and native/shared Autofill state.
10. On first load of legacy multi-store config, use `default_repo` only; on the next successful write, normalize `repos` to zero or one without touching ignored directories.
11. Validate migration, import, deletion, lock, Autofill, localization, accessibility, Flutter, Kotlin, iOS, bridge, core, and strict OpenSpec suites.

Rollback remains possible because normalized config still writes the selected path to both `default_repo` and the compatibility `repos` list. A rollback does not restore ignored multi-store registrations automatically, but no ignored directory is deleted.

## Open Questions

None required before implementation. Archive import and explicit PGP recipient rotation are intentionally deferred to separate changes.
