# flutter-vault-and-manage Specification

## Purpose

Document implemented Flutter vault, entry detail, metadata, and manage
workflows.

## Requirements

### Requirement: Flutter app SHALL route between onboarding, lock screen, and main shell

The app SHALL render onboarding until security onboarding and store readiness
are satisfied, render lock screen when locked, and otherwise render a mobile
shell with Vault, Manage, and Settings tabs.

Sources: `gui/lib/main.dart`, `gui/lib/app/pars_gui_app.dart`,
`gui/lib/screens/shell/mobile_shell.dart`

#### Scenario: Main shell exposes three tabs

- WHEN the app is onboarded and unlocked
- THEN the main shell shows Vault, Manage, and Settings tabs

### Requirement: Bridge-backed repository SHALL refresh app, key, entry, and Git state

Repository refresh SHALL call bridge app-state inspection, key listing, entry
listing for the selected existing store, and Git status. If no selected
existing store is available, it SHALL clear entries and mark Git sync failed.

Sources: `gui/lib/services/bridge_backed_repository.dart`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Refresh loads selected store entries

- GIVEN bridge app state has a selected existing store
- WHEN repository `refresh` runs
- THEN it loads keys
- AND recursively lists entries for that store
- AND updates Git status

### Requirement: Vault SHALL support search, browse, recent, favorites, and refresh

The Vault screen SHALL refresh on open and pull-to-refresh, search by display
name or path, browse direct children of a directory, show recent entries, and
toggle favorites through repository metadata.

Sources: `gui/lib/screens/vault/vault_screen.dart`,
`gui/lib/services/bridge_backed_repository.dart`,
`gui/lib/services/vault_metadata_store.dart`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Search matches name or path

- WHEN a query is entered
- THEN entries whose display name or path contains the query case-insensitively
  are returned

#### Scenario: Recent metadata persists

- GIVEN an entry is read
- WHEN repository metadata is saved
- THEN a later repository instance using the same metadata store returns that
  entry in recent entries

### Requirement: Entry detail SHALL gate secret loading on active PGP session when security is provided

The entry detail sheet SHALL ask for a PGP passphrase before loading the secret
when a security repository is provided and no active PGP session exists.
Starting a session SHALL then load the entry.

Sources: `gui/lib/screens/vault/entry_detail_sheet.dart`,
`gui/lib/services/security_repository.dart`

#### Scenario: Missing session prompts for passphrase

- GIVEN entry detail has a security repository
- AND no active PGP session exists
- WHEN the sheet is opened
- THEN it shows a PGP passphrase prompt

### Requirement: Entry detail SHALL reveal, copy, QR, URL, field, and favorite entry data

The entry detail sheet SHALL show a masked password by default. It SHALL
support reveal/hide, copying the password and parsed fields, QR code display
for the password, opening URL/website fields with a URI scheme, and toggling
favorites.

Sources: `gui/lib/screens/vault/entry_detail_sheet.dart`,
`gui/lib/services/pass_entry_parser.dart`

#### Scenario: Clipboard is cleared after delay

- WHEN entry detail copies text
- AND `clipboardClearDelay` is greater than zero
- THEN a timer writes an empty string to the same clipboard writer after the
  delay

#### Scenario: URL action requires scheme

- GIVEN parsed entry fields include `url` or `website`
- WHEN the value parses as a URI with a scheme
- THEN Open URL action is available
- OTHERWISE it is not available

### Requirement: Manage screen SHALL expose single-entry and batch workflows

Manage SHALL expose generated password save, manual password save, edit,
move/rename, delete, batch move, batch rename, batch delete, and batch
regenerate workflows. Optional commit checkboxes SHALL call repository commit
when available.

Sources: `gui/lib/screens/manage/manage_screen.dart`,
`gui/lib/services/vault_repository.dart`,
`gui/lib/services/bridge_backed_repository.dart`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Generated entry can be saved and optionally committed

- WHEN the generate sheet submits an entry path
- THEN repository `generateEntry` is called with length `24`
- AND optional commit uses message `Generate password <path>`

#### Scenario: Batch operations collect per-entry failures

- WHEN bridge-backed repository runs a batch operation
- THEN successful result paths are collected
- AND caught per-entry errors are returned as batch failures

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

The entry detail sheet SHALL derive PGP passphrase input and masked or revealed
password surface colors from the active Flutter theme. These surfaces SHALL
remain visually appropriate and their text and icons SHALL remain legible in
both light and dark modes without a hard-coded light-only fill overriding dark
mode.

#### Scenario: Password surface is rendered in dark mode

- **WHEN** an entry detail sheet displays a masked or revealed password while
  the active theme uses dark brightness
- **THEN** the password surface uses the configured dark theme surface
  treatment
- **AND** it does not use the light theme's hard-coded input fill
- **AND** the password text and reveal icon remain legible

#### Scenario: Passphrase input is rendered in either theme

- **WHEN** an entry requires a PGP passphrase in light or dark mode
- **THEN** the passphrase input derives its fill and foreground treatment from
  the active input decoration theme

### Requirement: Entry detail SHALL preserve modal width across asynchronous states

The entry detail sheet SHALL occupy the available width permitted by its modal
route constraints in passphrase, decrypting, decryption-error, empty, and
loaded-content states. Transitioning between these states SHALL NOT collapse
the modal to the intrinsic width of a progress indicator or other compact
child.

#### Scenario: Entry is being decrypted

- **WHEN** the entry detail modal is waiting for an asynchronous secret read
- **THEN** the loading presentation occupies the available modal width
- **AND** the modal does not shrink to the loading indicator's intrinsic width

#### Scenario: Decryption completes

- **WHEN** an entry detail modal transitions from decrypting to loaded content
  or a decryption error
- **THEN** its width remains stable within the same route constraints

#### Scenario: Passphrase unlock starts secret loading

- **WHEN** a user submits a valid PGP passphrase and the sheet transitions from
  the passphrase prompt to decrypting and then loaded content
- **THEN** each state uses the same available modal width

### Requirement: Entry detail SHALL expose working single-entry mutation actions

When the loaded entry-detail sheet is backed by a `ManageRepository`, Edit, Regenerate, and Delete SHALL invoke focused workflows for the displayed entry. The detail sheet SHALL clear its decrypted content before a mutation workflow is presented. Successful mutations SHALL use existing repository semantics and SHALL produce a visible result notification; cancellation SHALL perform no mutation.

#### Scenario: Edit opens the displayed entry

- **GIVEN** entry detail is displaying a decrypted entry
- **AND** the vault repository supports manage operations
- **WHEN** the user selects Edit
- **THEN** the detail sheet closes and clears its secret
- **AND** a focused edit workflow loads that same entry
- **AND** saving uses the existing edit or first-line replacement operation

#### Scenario: Regenerate replaces one entry password

- **GIVEN** entry detail is displaying an entry with parsed fields or raw notes
- **WHEN** the user selects Regenerate and confirms the focused workflow
- **THEN** regeneration targets exactly that entry
- **AND** the existing replacement behavior preserves parsed fields and raw notes
- **AND** the result is visibly reported

#### Scenario: Delete requires the existing human-readable confirmation

- **GIVEN** entry detail is displaying an entry
- **WHEN** the user selects Delete
- **THEN** the detail sheet closes and a focused delete workflow displays the full path
- **AND** deletion is blocked until confirmation equals the entry display label
- **AND** successful deletion is visibly reported

#### Scenario: Mutation workflow is cancelled

- **WHEN** the user closes an Edit, Regenerate, or Delete workflow without submitting it
- **THEN** no repository mutation is performed
- **AND** the user returns to Vault with no success notification

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

## Needs Verification

- Entry detail PGP passphrase session currently gates UI loading, but bridge
  read calls do not receive that passphrase. How passphrase-protected keys are
  unlocked end-to-end needs verification.
- Batch regenerate uses Dart-generated passwords rather than the core password
  generator. Intended generator consistency needs verification.
