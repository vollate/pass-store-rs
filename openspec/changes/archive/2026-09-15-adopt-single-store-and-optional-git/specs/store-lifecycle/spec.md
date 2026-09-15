## ADDED Requirements

### Requirement: App-state inspection SHALL report one optional store and derived lifecycle state

Bridge app-state inspection SHALL return config existence, one optional canonical store status, aggregate issues, and a lifecycle state derived from store availability, `.gpg-id`, required private material, and Git validity. It SHALL NOT return selected-store identifiers plus a selectable store list.

#### Scenario: Missing config returns no config

- **GIVEN** the config path does not exist
- **WHEN** app state is inspected
- **THEN** config existence is false
- **AND** the canonical store is absent
- **AND** lifecycle state requires store setup

#### Scenario: Empty canonical path requires store setup

- **GIVEN** config exists with no canonical store path
- **WHEN** app state is inspected
- **THEN** the canonical store is absent
- **AND** lifecycle state requires store setup

#### Scenario: Existing usable store is ready without a selection step

- **GIVEN** the canonical store exists
- **AND** its required private material is available
- **AND** its Git metadata is absent or valid
- **WHEN** app state is inspected
- **THEN** lifecycle state is ready
- **AND** no store-selection action is required

### Requirement: Legacy multi-store configuration SHALL collapse without deleting directories

GUI lifecycle loading SHALL treat `default_repo` as the sole canonical store when a legacy config contains multiple `repos`. If `default_repo` is empty, it MAY recover the first non-empty legacy path. A later successful config write SHALL normalize `repos` to zero or one canonical path and SHALL NOT delete, move, or rewrite ignored store directories.

#### Scenario: Prior default wins over other valid directories

- **GIVEN** a legacy config names `personal` as `default_repo`
- **AND** `repos` also contains `work`
- **WHEN** the GUI loads lifecycle state
- **THEN** only `personal` is exposed as the password store
- **AND** `work` is not automatically selected or deleted

#### Scenario: Missing prior default does not fall back after deletion

- **GIVEN** the canonical store was removed successfully
- **AND** an ignored legacy directory still exists
- **WHEN** lifecycle state refreshes
- **THEN** the canonical store is absent
- **AND** the app requires store setup instead of selecting the ignored directory

### Requirement: Create, import, and clone SHALL establish the sole configured store

Create SHALL require an absent target, prepare `.gpg-id` and optional Git metadata in a unique sibling staging directory, reserve the final root without replacing any raced file, directory, or symlink, and remove only the newly created tree if preparation or config persistence fails. Import SHALL register only a finalized staged store. Clone SHALL reject an existing target, run Git clone, and register the result only after clone and store inspection succeed. Each successful operation SHALL replace the empty canonical path and normalize the compatibility `repos` mirror to that one path; none SHALL add another selectable store.

#### Scenario: Create supports a store without Git

- **GIVEN** no canonical store is configured
- **WHEN** Create receives valid PGP recipients and Git initialization is declined
- **THEN** the root and `.gpg-id` are created
- **AND** no `.git` directory is required
- **AND** the new root becomes the sole canonical store

#### Scenario: Create never overwrites an existing recipient policy

- **GIVEN** the requested Create target already exists as a file, directory, or symlink
- **WHEN** Create is submitted with different PGP recipients
- **THEN** Create fails without changing the existing target or `.gpg-id`
- **AND** no staging directory remains

#### Scenario: Create failure cleans only the new tree

- **GIVEN** the requested Create target is initially absent
- **WHEN** Git preparation, final-name reservation, or canonical config persistence fails
- **THEN** the staged or newly installed tree is removed
- **AND** any concurrently created target remains untouched

#### Scenario: Clone establishes one Git-backed store

- **GIVEN** no canonical store is configured
- **WHEN** Clone completes into a new target and required key inspection succeeds
- **THEN** the cloned root becomes the sole canonical store
- **AND** its cloned Git metadata is preserved

#### Scenario: Setup cannot add a second store

- **GIVEN** a canonical store is already configured
- **WHEN** a create, import, or clone request attempts to register another root
- **THEN** the request is rejected or requires the existing store to be disconnected first
- **AND** the current canonical path remains unchanged

### Requirement: Store import SHALL stage the complete visible tree and classify Git metadata

App-managed Import SHALL copy every provider-visible file and directory, including dotfiles such as `.git` and `.gpg-id`, into staging before changing the canonical store. It SHALL reject path overlap/escape, cycles, unsupported links, duplicate names, and unsafe entries. Before filesystem installation it SHALL classify Git as valid, absent, or invalid. Installation SHALL retain any prior-destination backup until registration and atomic config persistence succeed; registration failure SHALL trigger verified rollback. An externally owned desktop folder MAY be inspected and registered directly without copying.

#### Scenario: Valid Git metadata is preserved

- **GIVEN** the selected tree exposes a valid `.git` work tree with branch, refs, objects, config, and remote metadata
- **WHEN** Import stages and validates the tree
- **THEN** all exposed Git metadata is copied unchanged
- **AND** Import does not run `git init`
- **AND** Git status, history, branch, and remote remain available after finalization

#### Scenario: Missing Git asks before finalization

- **GIVEN** the staged tree contains no `.git`
- **WHEN** Import classifies Git metadata
- **THEN** the user is told that the source may be local-only or the provider may have hidden Git metadata
- **AND** the user can initialize Git, continue without Git, or cancel

#### Scenario: User continues without Git

- **GIVEN** staged import contains no `.git`
- **WHEN** the user declines Git initialization and chooses Continue
- **THEN** the staged password store is finalized and registered
- **AND** its Git mode is disabled rather than failed

#### Scenario: User initializes Git only in staging

- **GIVEN** staged import contains no `.git`
- **WHEN** the user chooses Initialize Git
- **THEN** `git init` runs in staging and not in the source tree
- **AND** the initialized tree is finalized only after initialization succeeds

#### Scenario: User cancels missing-Git import

- **GIVEN** staged import contains no `.git`
- **WHEN** the user chooses Cancel
- **THEN** staging is deleted
- **AND** no destination is replaced or registered

#### Scenario: Present but invalid Git aborts import

- **GIVEN** staged import contains `.git`
- **AND** Git cannot validate the staged root as a usable work tree
- **WHEN** Import classifies the result
- **THEN** Import reports invalid Git metadata
- **AND** it does not discard, reinitialize, finalize, or register the staged tree

#### Scenario: Registration failure restores the prior destination

- **GIVEN** an app-managed import has installed staging and retained the prior destination backup
- **WHEN** Rust registration or config persistence fails
- **THEN** the installed tree is removed and the backup is restored and verified
- **AND** the failed import is not reported as complete

#### Scenario: Full-store import does not merge repositories

- **GIVEN** the derived app-managed destination already exists
- **WHEN** Import resolves the conflict
- **THEN** it offers atomic replacement or cancellation
- **AND** it does not merge two `.git` trees

### Requirement: Disconnecting the sole store SHALL leave no configured fallback

Disconnect SHALL clear the canonical store path and compatibility mirror without deleting an externally owned root. It SHALL NOT select an ignored legacy path. A successful disconnect SHALL publish lifecycle state requiring store setup.

#### Scenario: External store disconnect preserves files

- **GIVEN** the canonical store root is not app-managed
- **WHEN** the user confirms Disconnect
- **THEN** config contains no canonical store
- **AND** the external directory remains unchanged
- **AND** lifecycle state requires store setup

#### Scenario: Disconnect never falls back to a legacy path

- **GIVEN** a legacy config once contained another repository path
- **WHEN** the canonical store is disconnected
- **THEN** no other path becomes canonical
- **AND** Create, Import, and Clone are presented

## MODIFIED Requirements

### Requirement: Store inspection SHALL detect missing store, missing `.gpg-id`, missing remote, and missing private key

Canonical store inspection SHALL detect a missing directory, missing `.gpg-id`, missing matching private PGP material, absent Git, valid local Git, valid Git with a remote, and present-but-invalid Git metadata. Missing Git and missing remote SHALL be intentional non-blocking modes; missing `.gpg-id`, missing required private material, and invalid Git SHALL require contextual repair or a clear failure state.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`

#### Scenario: Non-Git local store can be ready

- **GIVEN** a local store exists
- **AND** it has `.gpg-id` with matching private material
- **AND** it is not a Git repository
- **WHEN** app state is inspected
- **THEN** lifecycle state can be ready
- **AND** Git mode is disabled
- **AND** no sync failure is reported

#### Scenario: Git repository without remote is local Git

- **GIVEN** a store exists
- **AND** it is a valid Git repository
- **AND** `git remote` returns no remotes
- **WHEN** app state is inspected
- **THEN** Git mode is local
- **AND** missing remote does not block store readiness

#### Scenario: Git repository with remote enables remote mode

- **GIVEN** a store is a valid Git repository with at least one remote
- **WHEN** app state is inspected
- **THEN** Git mode is remote
- **AND** remote synchronization actions may be enabled

#### Scenario: Invalid Git is not treated as disabled

- **GIVEN** a store contains `.git` that cannot be validated
- **WHEN** app state is inspected
- **THEN** Git mode is invalid
- **AND** the problem is not presented as an intentional local-only store

#### Scenario: Missing recipient private key requires repair

- **GIVEN** `.gpg-id` contains one or more recipients
- **AND** no listed local private key matches any usable recipient
- **WHEN** app state is inspected
- **THEN** lifecycle state requires key repair
- **AND** a public-only match does not satisfy readiness

### Requirement: Delete local store SHALL require exact confirmation and configured root

Delete-local-store SHALL require confirmation equal to the final store name derived from the normalized canonical root basename, require that root to be the configured canonical store, refuse filesystem-root deletion, and physically delete only an app-managed directory. It SHALL delete app-owned files before clearing configuration so an interrupted failure remains retryable. On success it SHALL clear the canonical path and compatibility mirror without choosing a fallback. User-facing confirmation SHALL display the full root as read-only context but require only the final store name.

Sources: `bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`, `gui/lib/screens/settings/widgets/settings_store_widgets.dart`

#### Scenario: Confirmation must match store name

- **GIVEN** canonical app-managed root `/data/user/0/top.vollate.pars_gui/files/stores/work`
- **WHEN** delete-local-store receives confirmation `work`
- **THEN** validation succeeds and the directory tree is deleted
- **AND** config contains no canonical store

#### Scenario: Full path is not required for confirmation

- **GIVEN** canonical root `/data/user/0/top.vollate.pars_gui/files/stores/work`
- **WHEN** the delete confirmation UI is shown
- **THEN** the full root is displayed as read-only context
- **AND** the confirmation field asks for `work`

#### Scenario: Mismatched store name is rejected

- **GIVEN** canonical root `/data/user/0/top.vollate.pars_gui/files/stores/work`
- **WHEN** confirmation is `stores/work` or any value other than `work`
- **THEN** validation fails without deleting files or changing config

#### Scenario: External root cannot be physically deleted

- **GIVEN** the canonical root is not app-managed
- **WHEN** Settings presents its removal action
- **THEN** it offers Disconnect instead of Delete local copy
- **AND** no GUI operation recursively deletes that external directory

#### Scenario: Failed physical deletion preserves canonical config

- **GIVEN** an app-managed store remains configured
- **WHEN** recursive deletion fails
- **THEN** the canonical path remains configured for retry
- **AND** the app reports failure without claiming rollback or successful removal

### Requirement: Onboarding store actions SHALL offer create, import, and clone paths

Whenever lifecycle state has no canonical store, Flutter setup SHALL offer Import and Clone as primary actions and Create as a secondary action. App-managed roots SHALL be derived from the selected folder, store name, or remote URL. Setup SHALL inspect the resulting `.gpg-id` after Import or Clone and SHALL request SSH setup only when an SSH-form clone requires it.

Sources: `gui/lib/screens/onboarding/onboarding_screen.dart`, `gui/lib/services/bridge_backed_repository.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Remote URL derives app-managed store root

- **GIVEN** managed store base `/app/support/stores`
- **WHEN** remote URL is `git@example.com:org/passwords.git`
- **THEN** derived root is `/app/support/stores/passwords`

#### Scenario: HTTPS clone does not require SSH setup

- **GIVEN** no SSH key is configured
- **WHEN** the user chooses an HTTPS remote URL
- **THEN** Clone can proceed without an SSH setup step

#### Scenario: SSH clone requests SSH capability contextually

- **GIVEN** the user chooses an SSH-form remote
- **AND** no usable SSH key is configured
- **WHEN** Clone validates prerequisites
- **THEN** it offers SSH key import or generation before cloning
- **AND** unrelated PGP administration is not shown first

#### Scenario: Store setup completes without a review rail

- **GIVEN** local security is configured
- **AND** a created, imported, or cloned store passes required repair
- **WHEN** lifecycle state becomes ready
- **THEN** setup enters Vault
- **AND** the user is not required to traverse a fixed PGP, SSH, Store, and Review sequence

## REMOVED Requirements

### Requirement: App-state inspection SHALL report config, selected store, stores, issues, and onboarding state

**Reason**: The GUI no longer has selected-store IDs or a selectable store list.

**Migration**: Use the singular optional store and derived lifecycle state returned by app-state inspection.

### Requirement: List stores SHALL derive store info from config repos

**Reason**: Multiple configured GUI stores and store-list presentation are removed.

**Migration**: Read the one canonical store from normalized lifecycle state.

### Requirement: Store selection SHALL require configured store root

**Reason**: There is no GUI store switcher or alternate configured root to select.

**Migration**: Disconnect or delete the current store, then Create, Import, or Clone the replacement.

### Requirement: Create, import, and clone SHALL add stores to config

**Reason**: Setup no longer appends paths to a multi-store registry.

**Migration**: Create, Import, and Clone establish the sole canonical store using the added singular lifecycle requirement.

### Requirement: Remove store SHALL update config without deleting files

**Reason**: Generic removal with automatic fallback is replaced by explicit single-store Disconnect and app-managed Delete local copy.

**Migration**: Use Disconnect for externally owned roots or Delete local copy for app-managed roots; both transition to store setup with no fallback.
