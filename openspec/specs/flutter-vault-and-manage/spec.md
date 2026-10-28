# flutter-vault-and-manage Specification

## Purpose

Document implemented Flutter vault, entry detail, metadata, and manage
workflows.

## Requirements

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

- **GIVEN** Vault contains a query, directory, or scroll position
- **WHEN** the user opens Settings and returns without changing the canonical store
- **THEN** that non-secret Vault state is restored
- **AND** decrypted detail content is not retained by destination restoration

#### Scenario: Back navigation returns to Vault before exit

- **GIVEN** a compact authenticated shell is showing Settings with no nested route to pop
- **WHEN** the platform back action is invoked
- **THEN** the shell returns to Vault
- **AND** an open Vault folder is kept until a later back action
- **AND** a later back action at the Vault root may leave the app according to platform convention

#### Scenario: Back navigation leaves the current folder before exit

- **GIVEN** Vault is browsing inside a directory
- **WHEN** the platform back action is invoked
- **THEN** Vault shows that directory's parent, or the store root when it has none
- **AND** the shell stays open

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

### Requirement: Vault SHALL support search, browse, and refresh

Vault SHALL refresh on initial open and explicit pull-to-refresh, search by display name or path, and browse direct children of a directory. Search results SHALL replace Browse while the query is active. Public search, browse, and scroll state SHALL survive a safe destination switch for the same store. Store-scoped query, directory, and scroll state SHALL be cleared when the canonical store is removed or replaced. Vault SHALL NOT expose Favorites or Recent sections or derive Autofill ranking from viewing, decrypting, revealing, or copying an entry.

Sources: `gui/lib/screens/vault/vault_screen.dart`, `gui/lib/services/bridge_backed_repository.dart`, `gui/lib/services/vault_metadata_store.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Search matches name or path

- **WHEN** a query is entered
- **THEN** entries whose display name or path contains the query case-insensitively are returned
- **AND** Search results replace Browse while the query is active

#### Scenario: Vault access does not create ranking history

- **GIVEN** a credential is visible in Vault
- **WHEN** the user opens, decrypts, reveals, or copies it
- **THEN** no recent-use metadata is written
- **AND** no Autofill completion ranking update is requested

#### Scenario: Browse distinguishes directories and credentials

- **WHEN** Vault renders direct children of the current directory
- **THEN** directory and credential rows have distinct semantics and actions
- **AND** rows expose authoritative display name and parent or service context without network identity lookup

#### Scenario: Store removal clears store-scoped presentation metadata

- **GIVEN** the canonical store has query or navigation state
- **WHEN** that store is deleted or disconnected successfully
- **THEN** those store-scoped values are cleared before store setup is shown
- **AND** a later replacement store cannot inherit them

### Requirement: Entry detail SHALL gate secret loading on active PGP session when security is provided

The entry-detail surface SHALL ask for a PGP passphrase before loading the secret when a security repository is provided and no active PGP session exists. Starting a session SHALL await existing private-key preparation before loading the entry. Leaving detail, locking, changing destination, or entering a protected background state SHALL clear loaded secret content.

Sources: `gui/lib/screens/vault/entry_detail_sheet.dart`, `gui/lib/services/security_repository.dart`

#### Scenario: Missing session prompts for passphrase
- **GIVEN** entry detail has a security repository
- **AND** no active PGP session exists
- **WHEN** the detail surface is opened
- **THEN** it shows a localized PGP passphrase prompt
- **AND** it does not load the entry before the session starts

#### Scenario: Leaving detail disposes decrypted content
- **GIVEN** entry detail has loaded a secret
- **WHEN** detail is closed, Vault is left, or the app locks
- **THEN** the decrypted content is cleared
- **AND** reopening detail requires the normal gated read path

### Requirement: Entry detail SHALL reveal, copy, QR, URL, and field data

Entry detail SHALL show a masked password by default and SHALL expose exactly one reveal/hide control whose label, icon, tooltip, and semantics track the current obscured state. Password Copy SHALL be the primary secret action. URL opening and field copy SHALL remain adjacent to the related data. QR, edit, move, rename, regenerate, and delete SHALL be grouped as secondary or overflow actions, with Delete using destructive semantics. Unsupported actions SHALL be disabled, omitted, or explicitly explained rather than silently enabled.

Sources: `gui/lib/screens/vault/entry_detail_sheet.dart`, `gui/lib/services/pass_entry_parser.dart`

#### Scenario: Reveal control toggles both state and label
- **GIVEN** the password is masked
- **WHEN** the user activates Reveal
- **THEN** the password becomes visible
- **AND** the same control becomes Hide with matching icon and semantics
- **WHEN** Hide is activated
- **THEN** the password is masked again

#### Scenario: Detail does not duplicate reveal actions
- **WHEN** loaded entry detail renders
- **THEN** only one actionable reveal/hide control is present
- **AND** a second Reveal button is not rendered beside it

#### Scenario: Clipboard is cleared after delay
- **WHEN** entry detail copies a password or parsed secret field
- **AND** the configured clipboard-clear delay is greater than zero
- **THEN** the shared sensitive clipboard service clears the same clipboard after that delay

#### Scenario: URL action requires scheme
- **GIVEN** parsed entry fields include `url` or `website`
- **WHEN** the value parses as a URI with a scheme
- **THEN** Open URL is available beside the URL data
- **OTHERWISE** it is not available

#### Scenario: Delete is separated from routine actions
- **WHEN** entry detail exposes Delete
- **THEN** Delete uses the shared destructive visual and semantic treatment
- **AND** it retains the existing human-readable confirmation workflow

### Requirement: Batch regenerate SHALL preserve parsed fields and raw notes

Bridge-backed batch regenerate SHALL generate a new password in Dart and call
replace-entry-password, preserving existing parsed fields and raw notes.

Sources: `gui/lib/services/bridge_backed_repository.dart`,
`gui/lib/services/pass_entry_parser.dart`

#### Scenario: Replace password preserves metadata

- GIVEN an existing entry has parsed fields and raw notes
- WHEN replace-entry-password runs
- THEN the first line is replaced
- AND parsed fields and raw notes are reconstructed after the password line

### Requirement: Entry detail SHALL honor the active color theme

Entry detail SHALL derive passphrase input, password, field, status, overflow, and action treatments from the active Flutter theme and shared design tokens. These surfaces SHALL remain visually appropriate and legible in light and dark modes, including error and destructive states, without hard-coded light-only fills or fixed low-contrast section text.

#### Scenario: Password surface is rendered in dark mode
- **WHEN** entry detail displays a masked or revealed password while the active theme is dark
- **THEN** the password surface uses the configured dark semantic surface
- **AND** password text and the reveal/hide control remain legible

#### Scenario: Passphrase input is rendered in either theme
- **WHEN** an entry requires a PGP passphrase in light or dark mode
- **THEN** the passphrase input derives fill, foreground, validation, and busy treatment from the active theme

#### Scenario: Destructive detail action uses dark-theme error roles
- **WHEN** Delete is rendered in dark mode
- **THEN** its foreground, focus, and disabled states use the configured error roles
- **AND** they remain distinguishable from primary and secondary actions

### Requirement: Entry detail SHALL expose working single-entry mutation actions

When loaded entry detail is backed by a `ManageRepository`, Edit, Move, Rename, Regenerate, and Delete SHALL invoke focused workflows for the displayed entry through contextual or overflow actions. Entry detail SHALL clear and close its decrypted content before a mutation workflow is presented. Successful mutations SHALL use existing repository semantics and produce severity-appropriate visible results; cancellation SHALL perform no mutation.

#### Scenario: Edit opens the displayed entry
- **GIVEN** entry detail is displaying a decrypted entry
- **AND** the vault repository supports manage operations
- **WHEN** the user selects Edit
- **THEN** detail closes and clears its secret
- **AND** a focused edit workflow loads that same entry
- **AND** saving uses the existing edit or first-line replacement operation

#### Scenario: Regenerate replaces one entry password
- **GIVEN** entry detail is displaying an entry with parsed fields or raw notes
- **WHEN** the user selects Regenerate and confirms the focused workflow
- **THEN** regeneration targets exactly that entry
- **AND** existing replacement behavior preserves parsed fields and raw notes
- **AND** the result is visibly reported

#### Scenario: Delete requires the existing human-readable confirmation
- **GIVEN** entry detail is displaying an entry
- **WHEN** the user selects Delete
- **THEN** detail closes and the focused delete workflow displays the full path
- **AND** deletion is blocked until confirmation equals the entry display label
- **AND** successful deletion is visibly reported

#### Scenario: Mutation workflow is cancelled
- **WHEN** the user closes an Edit, Move, Rename, Regenerate, or Delete workflow without submitting it
- **THEN** no repository mutation is performed
- **AND** the user returns to Vault with no success notification

#### Scenario: Unsupported mutation is not presented as working
- **GIVEN** the supplied repository lacks the required manage capability
- **WHEN** entry detail renders mutation actions
- **THEN** unsupported actions are disabled, omitted, or explained
- **AND** no literal no-op callback is assigned

### Requirement: Production GUI actions SHALL NOT silently invoke empty handlers

Every rendered production GUI control that appears actionable SHALL either invoke a concrete callback, be disabled, or present an explicit unavailable-state explanation. Production action properties SHALL NOT be assigned literal empty callbacks. Framework lifecycle rebuild closures, unknown platform-channel method responses, generated code, and test fixtures are not user-action implementations and SHALL be classified separately during audits.

#### Scenario: Supported action is tapped

- **GIVEN** a production control is enabled and appears actionable
- **WHEN** the user taps the control
- **THEN** it invokes a concrete operation or navigation callback
- **AND** it does not silently return from a literal empty handler

#### Scenario: Repository lacks an optional capability

- **GIVEN** a screen is supplied a repository that lacks an optional operation interface
- **WHEN** the related control is rendered or opened
- **THEN** the control is disabled or the screen explains that the operation is unavailable
- **AND** the screen does not present mocked-future copy as though the operation were active

#### Scenario: New empty action callback is introduced

- **WHEN** production GUI source assigns a literal empty closure to an action property such as `onPressed` or `onTap`
- **THEN** automated regression validation fails
- **AND** the finding must be implemented, disabled, or explicitly classified before validation passes

### Requirement: Vault SHALL expose contextual single-entry management workflows

Vault SHALL expose generated-password creation and manual credential creation through a prominent create action. It SHALL expose edit, move, rename, regenerate, and delete beside the relevant credential. Vault SHALL NOT expose multi-select or batch move, rename, regenerate, or delete. All workflows SHALL reuse existing repository mutation semantics. Git commits after a mutation SHALL follow the "Commit every change" setting and SHALL run only when Git mode is local or remote. Mutation sheets SHALL NOT show a per-operation commit control. Git-disabled mutations SHALL remain successful without a Git warning.

#### Scenario: Create action offers existing creation workflows

- **WHEN** the user invokes Create from Vault
- **THEN** generated-password and manual-existing-password workflows are available
- **AND** they call the same repository operations and overwrite handling as before

#### Scenario: Vault does not offer multi-select

- **WHEN** Vault renders the credential list
- **THEN** it does not show a selection control, selection mode, or batch actions

#### Scenario: Focused single-entry workflow does not ask for an entry again

- **GIVEN** the user invokes Edit, Move, Rename, Regenerate, or Delete from a credential detail
- **WHEN** the focused workflow opens
- **THEN** it is bound to the displayed credential
- **AND** it does not show a secondary entry picker

#### Scenario: Mutation sheets have no commit checkbox

- **WHEN** any single-entry mutation sheet opens
- **THEN** it does not show a "commit after operation" control

#### Scenario: Automatic Git commit failure is durable

- **GIVEN** a contextual mutation succeeds with Git enabled and "Commit every change" on
- **AND** its automatic Git commit fails
- **WHEN** the result is presented
- **THEN** the warning states that the Vault mutation was not rolled back
- **AND** it remains available long enough to inspect or recover

#### Scenario: Missing identity pauses the automatic commit

- **GIVEN** a contextual mutation succeeds and no commit identity is configured
- **WHEN** the automatic commit is about to run
- **THEN** the identity sheet opens
- **AND** cancelling it leaves the mutation in place, uncommitted

#### Scenario: Git-disabled mutation does not report sync failure

- **GIVEN** the canonical store has Git disabled
- **WHEN** a contextual mutation succeeds
- **THEN** no Git commit is attempted
- **AND** the mutation is reported as successful without a Git failure warning

### Requirement: Vault SHALL present repository and Git status with truthful semantics

Vault SHALL present canonical password-store state separately from optional Git state. Git-disabled, local Git without remote, remote Git, failed, warning, busy, uncommitted, pull-needed, push-needed, diverged, conflicted, and clean states SHALL have localized labels, icons, tooltips, and semantic states appropriate to their actual meaning. The header badge SHALL show only the short state word, never a Git mode sentence. Git disabled and missing remote SHALL NOT be presented as failures. Diverged and conflicted SHALL use warning semantics and SHALL offer recovery. Status details and recovery actions SHALL remain reachable without placing raw command or parser output in the header.

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

#### Scenario: Unpushed commits are not shown as clean

- **GIVEN** remote Git status is `needPush`
- **WHEN** Vault renders the status control
- **THEN** it shows the localized push-needed label
- **AND** it does not display a success check icon

#### Scenario: Conflict offers recovery

- **GIVEN** the last sync returned a conflict with a backup branch
- **WHEN** the user activates the conflicted badge
- **THEN** a dialog offers Push backup as the secondary action and Use remote as the destructive primary action
- **AND** the dialog names the backup branch

#### Scenario: Status details are progressively disclosed

- **WHEN** the user activates a non-clean or configurable status
- **THEN** Pars presents a concise explanation and available recovery action
- **AND** bounded diagnostic details are separate from the header label

### Requirement: Every secret-copy entry point SHALL use the same privacy policy

Direct Vault-row copy, entry-detail password copy, and parsed secret-field copy SHALL use one sensitive clipboard service. The service SHALL apply the configured clear delay consistently, mark clipboard content sensitive where supported, replace or cancel earlier clear timers safely, and provide localized feedback that does not reveal the copied value.

#### Scenario: Vault-row copy clears like detail copy
- **WHEN** a password is copied from a Vault row
- **THEN** it is scheduled for clearing under the same policy as entry-detail copy
- **AND** supported platforms receive sensitive clipboard metadata

#### Scenario: Copy feedback contains no secret
- **WHEN** any secret-copy operation succeeds or fails
- **THEN** feedback identifies the entry or field without including its value

### Requirement: Entry detail SHALL preserve stable geometry across asynchronous states

The entry-detail route, pane, dialog, or sheet SHALL occupy stable constraints appropriate to the current width class during passphrase, decrypting, error, empty, and loaded states. Asynchronous transitions SHALL NOT collapse the surface to the intrinsic size of a spinner or compact error child.

#### Scenario: Entry is being decrypted
- **WHEN** entry detail waits for an asynchronous secret read
- **THEN** its loading presentation occupies the expected detail surface constraints
- **AND** it exposes a localized busy indication

#### Scenario: Decryption completes
- **WHEN** detail transitions from decrypting to loaded content or a decryption error
- **THEN** its outer geometry remains stable for the same route and width class

#### Scenario: Passphrase unlock starts loading
- **WHEN** a valid PGP passphrase transitions detail from passphrase prompt to decrypting and loaded content
- **THEN** each state uses the same adaptive detail framing

### Requirement: Vault pull-to-refresh SHALL run a full Git sync

When Git mode is remote, Vault pull-to-refresh SHALL run Git sync: commit pending changes according to the "Commit every change" setting or the user's answer, fetch, fast-forward or integrate with the configured strategy, then push. It SHALL then reload entries. When Git mode is local or disabled, pull-to-refresh SHALL only reload entries and status. Sync results SHALL be summarized in one localized notification. Conflicts SHALL set the conflicted state instead of a generic failure, and a sync blocked by uncommitted changes SHALL keep the uncommitted state and say that a commit is needed.

#### Scenario: Pull-to-refresh pushes pending edits

- **GIVEN** Git mode is remote, "Commit every change" is on, and the work tree has one changed entry
- **WHEN** the user pulls to refresh
- **THEN** the change is committed and pushed
- **AND** the badge shows clean

#### Scenario: Pull-to-refresh asks when automatic commits are off

- **GIVEN** Git mode is remote, "Commit every change" is off, and the work tree has one changed entry
- **WHEN** the user pulls to refresh
- **THEN** a dialog asks whether to commit before syncing
- **AND** no Git operation runs until the user chooses

#### Scenario: Pull-to-refresh on a local-only store does not sync

- **GIVEN** Git mode is local
- **WHEN** the user pulls to refresh
- **THEN** no fetch, commit, or push runs
- **AND** entries and status are reloaded

#### Scenario: Conflict during pull-to-refresh is not sync failed

- **WHEN** sync during pull-to-refresh returns a conflict
- **THEN** the badge shows conflicted
- **AND** it does not show sync failed

## Needs Verification

- Entry detail PGP passphrase session currently gates UI loading, but bridge
  read calls do not receive that passphrase. How passphrase-protected keys are
  unlocked end-to-end needs verification.
- Batch regenerate uses Dart-generated passwords rather than the core password
  generator. Intended generator consistency needs verification.
