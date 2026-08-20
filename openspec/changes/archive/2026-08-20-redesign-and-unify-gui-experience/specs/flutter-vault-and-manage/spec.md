## MODIFIED Requirements

### Requirement: Flutter app SHALL route between onboarding, lock screen, and main shell

The app SHALL render onboarding until security onboarding and store readiness are satisfied, render the lock screen while locked, and otherwise render an adaptive authenticated shell with Vault and Settings as durable destinations. The shell SHALL use compact or wide navigation appropriate to available width, preserve safe non-secret destination state, and route contextual credential creation and management through Vault rather than a separate Manage destination.

Sources: `gui/lib/main.dart`, `gui/lib/app/pars_gui_app.dart`, `gui/lib/screens/shell/mobile_shell.dart`

#### Scenario: Main shell exposes two destinations
- **GIVEN** the app is onboarded and unlocked
- **WHEN** the authenticated shell renders
- **THEN** it exposes Vault and Settings destinations
- **AND** it does not expose Manage as an equal top-level destination

#### Scenario: Destination switch preserves safe state
- **GIVEN** Vault contains a query, directory, selection, or scroll position
- **WHEN** the user opens Settings and returns
- **THEN** that non-secret Vault state is restored
- **AND** decrypted detail content is not retained by destination restoration

#### Scenario: Back navigation returns to Vault before exit
- **GIVEN** a compact authenticated shell is showing Settings with no nested route to pop
- **WHEN** the platform back action is invoked
- **THEN** the shell returns to Vault
- **AND** a later back action may leave the app according to platform convention

### Requirement: Vault SHALL support search, browse, recent, favorites, and refresh

Vault SHALL refresh on initial open and explicit pull-to-refresh, search by display name or path, browse direct children of a directory, present visible Favorites and bounded Recent sections, and display current favorite state on credential rows or detail headers. Recent SHALL contain only recorded recent metadata and SHALL be empty when no history exists; it SHALL NOT fall back to every non-directory entry. Search results SHALL replace home sections while the query is active. Public search, browse, section, selection, and scroll state SHALL survive a safe destination switch.

Sources: `gui/lib/screens/vault/vault_screen.dart`, `gui/lib/services/bridge_backed_repository.dart`, `gui/lib/services/vault_metadata_store.dart`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Search matches name or path
- **WHEN** a query is entered
- **THEN** entries whose display name or path contains the query case-insensitively are returned
- **AND** the screen presents Search results instead of duplicating Favorites, Recent, or Browse

#### Scenario: Recent metadata persists and is bounded
- **GIVEN** an entry is read or copied
- **WHEN** repository metadata is saved
- **THEN** a later repository instance using the same metadata store returns that entry in bounded recency order
- **AND** the number of visible recent rows is capped by a shared UI limit

#### Scenario: No history does not relabel all entries as recent
- **GIVEN** the selected store contains entries
- **AND** recent metadata is empty
- **WHEN** Vault renders
- **THEN** Recent shows a localized empty state or is collapsed according to the shared section policy
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

### Requirement: Entry detail SHALL reveal, copy, QR, URL, field, and favorite entry data

Entry detail SHALL show a masked password by default and SHALL expose exactly one reveal/hide control whose label, icon, tooltip, and semantics track the current obscured state. Password Copy SHALL be the primary secret action. Favorite SHALL be a visible stateful header action. URL opening and field copy SHALL remain adjacent to the related data. QR, edit, move, rename, regenerate, and delete SHALL be grouped as secondary or overflow actions, with Delete using destructive semantics. Unsupported actions SHALL be disabled, omitted, or explicitly explained rather than silently enabled.

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

## ADDED Requirements

### Requirement: Vault SHALL expose contextual single-entry and batch management workflows

Vault SHALL expose generated-password creation and manual credential creation through a prominent create action. It SHALL expose edit, move, rename, regenerate, and delete beside the relevant credential, and SHALL expose batch move, batch rename, batch regenerate, and batch delete only after entering explicit multi-select mode. All workflows SHALL reuse existing repository and optional Git-commit semantics.

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
- **THEN** public selection state is cleared or safely preserved according to the shell state policy
- **AND** no repository mutation occurs

#### Scenario: Batch operation preserves per-entry outcomes
- **WHEN** a contextual batch operation runs
- **THEN** successful paths and per-entry failures are collected through existing batch semantics
- **AND** the result surface distinguishes complete success, partial success, and failure

#### Scenario: Optional Git commit failure is durable
- **GIVEN** a contextual mutation succeeds and its optional Git commit fails
- **WHEN** the result is presented
- **THEN** the warning states that the vault mutation was not rolled back
- **AND** it remains available long enough to inspect or recover

### Requirement: Vault SHALL present repository and Git status with truthful semantics

Vault status presentation SHALL derive localized label, icon, color, tooltip, and semantic state from the actual repository/Git status. Failed, warning, busy, uncommitted, pull-needed, and clean states SHALL NOT reuse a fixed success icon. Status details and recovery actions SHALL be reachable without placing raw command or parser output in the header.

#### Scenario: Sync failure is not shown as success
- **GIVEN** repository Git status is `syncFailed`
- **WHEN** Vault renders the status control
- **THEN** it uses an error or warning icon and localized failure semantics
- **AND** it does not display a success check icon

#### Scenario: Status details are progressively disclosed
- **WHEN** the user activates a non-clean status
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

## REMOVED Requirements

### Requirement: Manage screen SHALL expose single-entry and batch workflows

**Reason**: A separate action-first Manage destination duplicates operations already associated with credentials and gives maintenance actions equal top-level prominence.

**Migration**: Generated/manual creation moves to the Vault create action; single-entry actions move to row/detail context; batch actions move to explicit Vault selection mode. Repository and optional Git-commit behavior remain unchanged.

### Requirement: Entry detail SHALL preserve modal width across asynchronous states

**Reason**: Entry detail becomes an adaptive route, pane, dialog, or sheet rather than requiring one modal form on every width class.

**Migration**: The replacement requirement, `Entry detail SHALL preserve stable geometry across asynchronous states`, retains the no-collapse guarantee across every adaptive detail presentation.
