## MODIFIED Requirements

### Requirement: Flutter app SHALL route between onboarding, lock screen, and main shell

The app SHALL derive presentation from independent security-setup, lock, removal-transition, canonical-store, and store-repair state. It SHALL render initial security setup when local unlock is not configured, the lock screen when locking is required, a non-secret transition surface while removal cleanup is in progress, store setup when no canonical store exists, contextual repair for missing `.gpg-id`, missing required private material, or invalid Git, and otherwise an adaptive authenticated shell with Vault and Settings as durable destinations. Starting removal SHALL unmount the shell and secret routes before bridge mutation without resetting completed local security setup.

Sources: `gui/lib/main.dart`, `gui/lib/app/pars_gui_app.dart`, `gui/lib/screens/shell/mobile_shell.dart`

#### Scenario: Main shell exposes two destinations

- **GIVEN** local security is configured
- **AND** the app is unlocked
- **AND** the canonical store is ready
- **WHEN** the authenticated shell renders
- **THEN** it exposes Vault and Settings destinations
- **AND** it does not expose Manage as an equal top-level destination

#### Scenario: No store routes to store setup

- **GIVEN** local security setup is complete and the app is unlocked
- **AND** no canonical store exists
- **WHEN** root presentation is derived
- **THEN** store setup is rendered instead of the authenticated shell
- **AND** security onboarding is not repeated

#### Scenario: Deleting the sole store removes the shell before mutation

- **GIVEN** the authenticated shell is visible for an app-managed canonical store
- **WHEN** confirmed deletion begins
- **THEN** decrypted detail and the shell are removed before bridge deletion
- **AND** a non-secret removing surface is shown during cleanup and mutation
- **WHEN** deletion succeeds
- **THEN** Create, Import, and Clone setup actions are shown

#### Scenario: Destination switch preserves safe state

- **GIVEN** Vault contains a query, directory, selection, or scroll position
- **WHEN** the user opens Settings and returns without changing the canonical store
- **THEN** that non-secret Vault state is restored
- **AND** decrypted detail content is not retained by destination restoration

#### Scenario: Back navigation returns to Vault before exit

- **GIVEN** a compact authenticated shell is showing Settings with no nested route to pop
- **WHEN** the platform back action is invoked
- **THEN** the shell returns to Vault
- **AND** a later back action may leave the app according to platform convention

### Requirement: Bridge-backed repository SHALL refresh app, key, entry, and Git state

Repository refresh SHALL call singular bridge app-state inspection and list entries only for the existing canonical store. Store-scoped refresh side effects SHALL be serialized with canonical removal so no earlier metadata or Autofill operation can finish after removal's final clear, and refresh SHALL NOT start while removal is in progress. It SHALL list or prepare PGP keys only when unlock or contextual repair requires them. For a store with Git disabled it SHALL skip Git commands; for valid local or remote Git it SHALL refresh supported status. If no canonical store is available, it SHALL clear entries, store-scoped metadata presentation, and Git state without classifying absence as sync failure.

Sources: `gui/lib/services/bridge_backed_repository.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Refresh loads canonical store entries

- **GIVEN** bridge app state has an existing canonical store
- **WHEN** repository `refresh` runs
- **THEN** it recursively lists entries for that store
- **AND** it refreshes Git only when Git mode is local or remote

#### Scenario: Refresh skips Git for a local-only store

- **GIVEN** the canonical store exists with Git mode disabled
- **WHEN** repository `refresh` runs
- **THEN** entries are loaded normally
- **AND** no Git status command is dispatched
- **AND** Git state remains neutral disabled

#### Scenario: Refresh clears data when store is absent

- **GIVEN** a prior repository snapshot contained entries
- **WHEN** singular app state reports no canonical store
- **THEN** entry and Git presentation state is cleared
- **AND** the repository does not expose stale entries or `syncFailed`

### Requirement: Vault SHALL support search, browse, recent, favorites, and refresh

Vault SHALL refresh on initial open and explicit pull-to-refresh, search by display name or path, browse direct children of a directory, present visible Favorites and bounded Recent sections, and display current favorite state on credential rows or detail headers. Recent SHALL contain only recorded metadata and SHALL NOT fall back to every non-directory entry. Search results SHALL replace home sections while the query is active. Public search, browse, section, selection, and scroll state SHALL survive a safe destination switch for the same store. Store-scoped Recent, Favorite, query, selection, directory, and scroll state SHALL be cleared when the canonical store is removed or replaced.

Sources: `gui/lib/screens/vault/vault_screen.dart`, `gui/lib/services/bridge_backed_repository.dart`, `gui/lib/services/vault_metadata_store.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Search matches name or path

- **WHEN** a query is entered
- **THEN** entries whose display name or path contains the query case-insensitively are returned
- **AND** Search results replace Favorites, Recent, and Browse while the query is active

#### Scenario: Recent metadata persists and is bounded

- **GIVEN** an entry is read or copied
- **WHEN** repository metadata is saved
- **THEN** a later repository instance for the same canonical store returns that entry in bounded recency order
- **AND** visible recent rows are capped by the shared UI limit

#### Scenario: No history does not relabel all entries as recent

- **GIVEN** the canonical store contains entries
- **AND** recent metadata is empty
- **WHEN** Vault renders
- **THEN** Recent shows a localized empty state or is collapsed according to shared policy
- **AND** ordinary entries remain available through Browse or Search

#### Scenario: Favorite is visible and discoverable

- **GIVEN** an entry is marked favorite
- **WHEN** Vault renders home or the entry row/detail
- **THEN** the entry appears in Favorites subject to the shared visible bound
- **AND** its favorite state is visually and semantically exposed

#### Scenario: Browse distinguishes directories and credentials

- **WHEN** Vault renders direct children of the current directory
- **THEN** directory and credential rows have distinct semantics and actions
- **AND** rows expose authoritative display name and parent or service context without network identity lookup

#### Scenario: Store removal clears store-scoped presentation metadata

- **GIVEN** the canonical store has Recent, Favorite, query, selection, or navigation state
- **WHEN** that store is deleted or disconnected successfully
- **THEN** those store-scoped values are cleared before store setup is shown
- **AND** a later replacement store cannot inherit them

### Requirement: Vault SHALL expose contextual single-entry and batch management workflows

Vault SHALL expose generated-password creation and manual credential creation through a prominent create action. It SHALL expose edit, move, rename, regenerate, and delete beside the relevant credential, and SHALL expose batch move, batch rename, batch regenerate, and batch delete only after entering explicit multi-select mode. All workflows SHALL reuse existing repository mutation semantics. Optional Git commits SHALL run only when Git mode is local or remote; Git-disabled mutations SHALL remain successful without a Git warning.

#### Scenario: Create action offers existing creation workflows

- **WHEN** the user invokes Create from Vault
- **THEN** generated-password and manual-existing-password workflows are available
- **AND** they call the same repository operations and overwrite handling as before

#### Scenario: Explicit selection mode exposes batch actions

- **GIVEN** Vault is not in selection mode
- **WHEN** the user invokes Select or long-presses a selectable credential
- **THEN** Vault enters selection mode and shows selected count
- **AND** only supported batch actions are enabled

#### Scenario: Leaving selection mode clears selection

- **GIVEN** one or more credentials are selected
- **WHEN** the user cancels selection mode or changes destination
- **THEN** public selection state is cleared or safely preserved according to shell state policy
- **AND** no repository mutation occurs

#### Scenario: Batch operation preserves per-entry outcomes

- **WHEN** a contextual batch operation runs
- **THEN** successful paths and per-entry failures are collected through existing batch semantics
- **AND** the result surface distinguishes complete success, partial success, and failure

#### Scenario: Optional Git commit failure is durable

- **GIVEN** a contextual mutation succeeds with Git enabled
- **AND** its optional Git commit fails
- **WHEN** the result is presented
- **THEN** the warning states that the Vault mutation was not rolled back
- **AND** it remains available long enough to inspect or recover

#### Scenario: Git-disabled mutation does not report sync failure

- **GIVEN** the canonical store has Git disabled
- **WHEN** a contextual mutation succeeds
- **THEN** no Git commit is attempted
- **AND** the mutation is reported as successful without a Git failure warning

### Requirement: Vault SHALL present repository and Git status with truthful semantics

Vault SHALL present canonical password-store state separately from optional Git state. Git-disabled, local Git without remote, remote Git, failed, warning, busy, uncommitted, pull-needed, and clean states SHALL have localized labels, icons, tooltips, and semantic states appropriate to their actual meaning. Git disabled and missing remote SHALL NOT be presented as failures. Status details and recovery actions SHALL remain reachable without placing raw command or parser output in the header.

#### Scenario: Git-disabled store is neutral

- **GIVEN** the canonical password store has no `.git`
- **WHEN** Vault renders status
- **THEN** password-store readiness remains successful
- **AND** Git is shown as disabled/local-only rather than failed

#### Scenario: Local Git without remote is not sync failure

- **GIVEN** the canonical store is a valid Git repository without a remote
- **WHEN** Vault renders status
- **THEN** it identifies local Git or remote-not-configured neutrally
- **AND** it does not show a failed-sync icon

#### Scenario: Sync failure is not shown as success

- **GIVEN** remote Git status is `syncFailed`
- **WHEN** Vault renders the status control
- **THEN** it uses an error or warning icon and localized failure semantics
- **AND** it does not display a success check icon

#### Scenario: Status details are progressively disclosed

- **WHEN** the user activates a non-clean or configurable status
- **THEN** Pars presents a concise explanation and available recovery action
- **AND** bounded diagnostic details are separate from the header label
