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

## Needs Verification

- Entry detail Edit, Regenerate, and Delete buttons currently have empty
  callbacks in `gui/lib/screens/vault/entry_detail_sheet.dart`.
- Entry detail PGP passphrase session currently gates UI loading, but bridge
  read calls do not receive that passphrase. How passphrase-protected keys are
  unlocked end-to-end needs verification.
- Batch regenerate uses Dart-generated passwords rather than the core password
  generator. Intended generator consistency needs verification.
