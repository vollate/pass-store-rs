# flutter-security-and-onboarding Specification

## Purpose

Document implemented Flutter security repository, app lock, biometric,
passphrase, and onboarding behavior.

## Requirements

### Requirement: Gesture verifier SHALL require at least four dots and reject immediate repeats

Gesture verifier creation SHALL reject patterns shorter than four dots,
patterns containing consecutive repeated dots, and dot values outside `0..=8`.
Verifier matching SHALL be order-sensitive.

Sources: `gui/lib/services/security_repository.dart`,
`gui/test/security_repository_test.dart`,
`gui/lib/widgets/gesture_setup_panel.dart`,
`gui/test/gesture_lock_input_test.dart`

#### Scenario: Short gesture is rejected

- WHEN a verifier is created from three dots
- THEN an argument error is thrown

#### Scenario: Same dots in different order do not match

- GIVEN a verifier created from `[0, 1, 2, 5]`
- WHEN `[0, 1, 5, 2]` is checked
- THEN it does not match

### Requirement: Secure storage repository SHALL persist durable security settings

The secure-storage security repository SHALL persist gesture verifier,
lock-on-resume, biometric enablement, PGP passphrase storage enablement, cached
PGP passphrase, onboarding completion, PGP session expiration, and auto-lock
timeout through the configured secure storage adapter.

Sources: `gui/lib/services/security_repository.dart`,
`gui/test/security_repository_test.dart`

#### Scenario: Active unlock sessions are not persisted

- GIVEN a repository is marked unlocked
- WHEN a new repository is loaded from the same storage
- THEN the new repository should lock until unlocked again

### Requirement: App lock SHALL depend on gesture setup, unlock timestamp, and auto-lock timeout

Security repositories SHALL report that the app should lock when a gesture
verifier exists and there is no active unlocked timestamp, or when the elapsed
time since unlock reaches the configured timeout. A zero or negative timeout
SHALL disable time-based auto-lock after unlock.

Sources: `gui/lib/services/security_repository.dart`,
`gui/lib/app/pars_gui_app.dart`, `gui/test/security_repository_test.dart`

#### Scenario: Auto-lock triggers at timeout

- GIVEN auto-lock timeout is five minutes
- AND the app was unlocked at time T
- WHEN five minutes have elapsed
- THEN `shouldLock` returns true

### Requirement: App lifecycle SHALL lock on resume when configured or expired

The app SHALL cancel pending lock timers while backgrounded. On resume, it
SHALL lock if lock-on-resume is enabled, the background auto-lock window
expired, or the security repository reports `shouldLock`.

Sources: `gui/lib/app/pars_gui_app.dart`

#### Scenario: System-auth grace period suppresses lifecycle lock

- WHEN an action runs through `runDuringSystemAuthentication`
- THEN lifecycle locks are suppressed while system auth is active
- AND for a short grace period after it completes

### Requirement: Biometric unlock SHALL authenticate before enabling and before unlocking

Biometric enablement SHALL require local-auth availability and a successful
authentication attempt. Biometric unlock SHALL authenticate again, mark the app
unlocked on success, and start a PGP session from cached passphrase when one is
available.

Sources: `gui/lib/services/security_repository.dart`,
`gui/test/security_repository_test.dart`

#### Scenario: Failed biometric authentication does not enable biometrics

- GIVEN biometric auth is available
- AND authentication returns false
- WHEN biometric unlock is enabled
- THEN a state error is thrown
- AND persisted biometric state remains disabled

### Requirement: PGP passphrase session SHALL honor configured expiration

PGP session expiration SHALL support immediate, five minutes, fifteen minutes,
one hour, and until app exit. Immediate expiration SHALL clear the session when
started; until-app-exit SHALL not expire by elapsed time.

Sources: `gui/lib/services/security_repository.dart`,
`gui/test/security_repository_test.dart`,
`gui/lib/screens/settings/settings_screen.dart`

#### Scenario: Five-minute session expires

- GIVEN session expiration is five minutes
- WHEN a PGP session starts
- THEN it remains active before five minutes
- AND is cleared at or after five minutes

### Requirement: Onboarding SHALL progress through local unlock, optional biometrics, keys, store, and review

Onboarding SHALL use a capability-driven essential-first flow. It SHALL require an accessible local gesture verifier and a usable selected password store before Finish. It SHALL guide PGP key selection, creation, import, or missing-key repair when required by the selected store. Biometric unlock and SSH setup SHALL remain available but SHALL be skippable or deferrable to a post-setup checklist and Settings. Review SHALL distinguish required incomplete work from optional skipped work. Finish SHALL persist onboarding completion and mark the app unlocked only after all required prerequisites are satisfied.

Sources: `gui/lib/screens/onboarding/onboarding_screen.dart`, `gui/lib/services/store_lifecycle.dart`, `gui/lib/services/key_repository.dart`

#### Scenario: Essential flow avoids a fixed expert step rail
- **GIVEN** a new user has no gesture verifier or usable store
- **WHEN** onboarding renders
- **THEN** it presents required local unlock and store/key setup in goal-oriented order
- **AND** it does not require navigating a disabled six-chip Gesture/Biometrics/PGP/SSH/Store/Review rail

#### Scenario: Optional capabilities can be deferred
- **GIVEN** required gesture and store/key setup are complete
- **WHEN** biometrics or SSH is unavailable or skipped
- **THEN** onboarding may continue to review and Finish
- **AND** Settings or a post-setup checklist exposes the deferred capability later

#### Scenario: Required key repair remains blocking
- **GIVEN** the selected store references PGP material that is not usable locally
- **WHEN** onboarding evaluates completion
- **THEN** it presents the existing key selection, creation, import, or repair flow
- **AND** Finish remains disabled until the store has the required usable key state

#### Scenario: Pure-Rust recipient inspection requires private material
- **GIVEN** mobile uses the configured pure-Rust PGP keyring
- **AND** `.gpg-id` contains one or more recipients
- **WHEN** app state is inspected
- **THEN** every recipient must match listed local private-key material
- **AND** a missing or public-only match reports required key repair

#### Scenario: Public-only PGP key cannot satisfy onboarding
- **GIVEN** local PGP records contain public material without the matching private key
- **WHEN** onboarding presents usable encryption keys
- **THEN** the public-only record is not offered as Use PGP key
- **AND** Finish remains blocked until private material is available

#### Scenario: Finish onboarding marks app ready
- **GIVEN** the gesture verifier exists
- **AND** store setup no longer requires setup or required key repair
- **WHEN** Finish is activated
- **THEN** onboarding completion is saved
- **AND** the security repository is marked unlocked

#### Scenario: Existing transactional setup behavior is preserved
- **WHEN** onboarding imports a protected key, chooses a native path, handles a store conflict, creates a store, or clones a store
- **THEN** it uses the existing validation, preparation, picker, conflict, and transactional repository behavior
- **AND** a presentation redesign does not bypass or duplicate those operations

### Requirement: Settings SHALL expose security, key, store, Git, and diagnostics surfaces

Settings SHALL organize all existing configuration capabilities into a user-goal hierarchy. Appearance, Security and privacy, Vault and sync, and Autofill SHALL appear before Key management and Advanced/support diagnostics. Appearance SHALL expose the persisted System/English/Chinese language choice. Routine tiles SHALL show concise localized state; technical commands, parser details, internal paths, and diagnostics SHALL be progressively disclosed. Gesture/biometric controls, PGP session timeout, key-bound secure passphrase controls, PGP and SSH key management, password stores, Git sync/remotes, advanced Git args, Autofill, runtime diagnostics, and onboarding reset SHALL remain reachable.

Sources: `gui/lib/screens/settings/settings_screen.dart`, `gui/lib/services/runtime_diagnostics.dart`

#### Scenario: Routine settings precede advanced diagnostics
- **WHEN** Settings home renders
- **THEN** appearance, security/privacy, vault/sync, and Autofill groups precede key-management and advanced/support groups
- **AND** Runtime diagnostics and advanced Git args do not receive the same initial prominence as routine settings

#### Scenario: Language is changed from Appearance
- **WHEN** the user selects System, English, or Chinese in Appearance
- **THEN** the UI foundation applies and persists that locale preference
- **AND** Settings remains on an equivalent route after the live language change

#### Scenario: Technical status is summarized
- **GIVEN** a Settings capability is unavailable, stale, or failed
- **WHEN** its home row renders
- **THEN** the row shows a concise localized state and appropriate status semantics
- **AND** bounded technical details are available only through an explicit details or diagnostics action

#### Scenario: Every existing setting remains reachable
- **WHEN** the redesign is complete
- **THEN** each security, key, store, Git, Autofill, diagnostic, and onboarding-reset operation defined by existing requirements has a concrete Settings route or action
- **AND** none is replaced by a no-op or misleading placeholder

#### Scenario: Reset onboarding clears onboarding completion
- **WHEN** Reset onboarding is selected and its confirmation completes
- **THEN** onboarding completion is set to false
- **AND** the app callback returns to the redesigned onboarding flow

### Requirement: Settings key sheets SHALL separate global add actions from per-key actions

Settings SHALL present PGP keys and SSH keys in separate key-management sheets.
Each sheet SHALL expose only key-adding actions at the sheet level, and SHALL
place actions that operate on an existing key inside that key row's overflow
menu.

#### Scenario: PGP sheet exposes only create and import globally

- **GIVEN** Settings displays the PGP keys sheet with one or more PGP keys
- **WHEN** the sheet is shown
- **THEN** the sheet-level actions include Create and Import
- **AND** sheet-level actions do not include Export public, Export private, Add
  to `.gpg-id`, or Delete

#### Scenario: PGP key row menu contains key-specific actions

- **GIVEN** Settings displays a PGP key with fingerprint `ABC`
- **WHEN** the user opens that key row's overflow menu
- **THEN** the menu includes Export public, Export private, Add to `.gpg-id`,
  and Delete
- **AND** choosing one of those actions targets fingerprint `ABC`

#### Scenario: SSH sheet exposes only create and import globally

- **GIVEN** Settings displays the SSH keys sheet with one or more SSH keys
- **WHEN** the sheet is shown
- **THEN** the sheet-level actions include Create and Import
- **AND** sheet-level actions do not include Export public, Export private, or
  Delete

#### Scenario: SSH key row menu contains key-specific actions

- **GIVEN** Settings displays an SSH key named `mobile-key`
- **WHEN** the user opens that key row's overflow menu
- **THEN** the menu includes Export public, Export private, and Delete
- **AND** choosing one of those actions targets name `mobile-key`

#### Scenario: PGP and SSH sheets remain separate

- **WHEN** the user opens PGP keys from Settings
- **THEN** Settings shows the PGP keys sheet
- **AND** it does not merge SSH keys into the same popup
- **WHEN** the user opens SSH keys from Settings
- **THEN** Settings shows the SSH keys sheet
- **AND** it does not merge PGP keys into the same popup

### Requirement: Settings and Onboarding SHALL use native path selectors for filesystem paths

Flutter Settings and Onboarding SHALL use platform-native file or folder
selectors as the primary UI for user-facing filesystem path choices. Affected
forms SHALL show a compact no-icon picker row that displays the default/base
path before selection and the selected path after selection. The store-folder
selection UI and key-file selection UI SHALL remain in their existing separate
interfaces and SHALL NOT be merged into one popup or form.

#### Scenario: Store folder picker shows default path before selection

- **GIVEN** a Settings or Onboarding store form needs a filesystem folder path
- **WHEN** the form is opened before the user chooses a folder
- **THEN** the form shows a compact no-icon row for the store folder
- **AND** the row displays `Default: <path>` using the best available base or
  derived store path
- **AND** the row exposes a Choose action instead of an editable path text field

#### Scenario: Store folder picker shows selected path after selection

- **GIVEN** a Settings or Onboarding store form shows a store folder picker row
- **WHEN** the platform folder selector returns a folder path
- **THEN** the row displays `Selected: <path>` with the returned or derived
  store path
- **AND** the row action changes to Change
- **AND** submitting the form passes that selected path to the existing store
  repository operation

#### Scenario: Create and clone derive target root from selected base folder

- **GIVEN** a create-store or clone-store form needs a target root that may not
  exist yet
- **WHEN** the user chooses a base folder from the native folder selector
- **THEN** the final store root is derived from the selected base folder and the
  store name or remote URL slug
- **AND** the derived root is shown as the selected path before submission

#### Scenario: Key file import uses a separate file picker row

- **GIVEN** the user opens a PGP or SSH key-file import flow
- **WHEN** the import file form is shown
- **THEN** the form shows a compact no-icon row for the key file
- **AND** the row displays `Default: <path>` before selection
- **AND** the key-file picker remains inside the key import interface, separate
  from store folder selection interfaces
- **AND** the form does not show an editable path text field

#### Scenario: Key file import submits selected file path

- **GIVEN** a PGP or SSH key-file import form shows a key file picker row
- **WHEN** the platform file selector returns a file path
- **THEN** the row displays `Selected: <path>` with that file path
- **AND** submitting the form passes that selected file path to the existing key
  import repository operation

#### Scenario: Picker cancellation preserves default state

- **GIVEN** a path picker row is shown before a required path has been selected
- **WHEN** the native selector is canceled
- **THEN** the row continues to display the default path
- **AND** the submit action for that required path remains disabled

#### Scenario: Unsupported picker reports an error without manual fallback

- **GIVEN** a platform-native selector is unavailable or fails before returning
  a path
- **WHEN** the user invokes the Choose action
- **THEN** Settings or Onboarding shows a clear error notification
- **AND** the form does not enable submission using a manually typed path

### Requirement: Settings SHALL allow deleting existing PGP and SSH keys

Settings key management SHALL expose delete actions for existing PGP and SSH
keys. Before deleting key material, the UI SHALL require confirmation using a
human-readable key label displayed in the key list, SHALL show the exact phrase
the user must type before submission, and SHALL show machine identifiers such as
PGP fingerprints as read-only context rather than requiring them as typed
confirmation text. Deletion failures SHALL be shown to the user without
removing the key from the visible list.

Sources: `gui/lib/screens/settings/settings_screen.dart`,
`gui/test/mobile_gui_smoke_test.dart`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete PGP key from settings

- GIVEN Settings displays a PGP key with name `Alice` and fingerprint `ABC`
- WHEN the user chooses delete for that key
- AND confirms deletion by typing `Alice`
- THEN Settings calls the PGP key delete operation for fingerprint `ABC`
- AND refreshes the visible key list after deletion succeeds

#### Scenario: PGP key delete dialog does not require fingerprint input

- GIVEN a PGP key deletion confirmation dialog is open for fingerprint `ABC`
- WHEN the dialog renders its confirmation instructions
- THEN the required typed confirmation text is the key's human-readable name
- AND the fingerprint `ABC` is displayed only as key context

#### Scenario: Delete SSH key from settings

- GIVEN Settings displays an SSH key named `mobile-key`
- WHEN the user chooses delete for that key
- AND confirms deletion by typing `mobile-key`
- THEN Settings calls the SSH key delete operation for name `mobile-key`
- AND refreshes the visible key list after deletion succeeds

#### Scenario: Delete key cancellation preserves the key

- GIVEN a key deletion confirmation dialog is open
- WHEN the user cancels the dialog or enters incorrect confirmation text
- THEN Settings does not call the key delete operation
- AND the key remains visible

### Requirement: PGP passphrase cache SHALL be associated with a selected PGP key

The PGP passphrase cache SHALL store the selected PGP key fingerprint alongside
the cached passphrase. Settings SHALL require the user to choose a private PGP
key before saving a passphrase, and all UI labels for stored passphrase state
SHALL identify the associated key.

Sources: `gui/lib/services/security_repository.dart`,
`gui/lib/screens/settings/settings_screen.dart`,
`gui/test/security_repository_test.dart`,
`gui/test/mobile_gui_smoke_test.dart`

#### Scenario: Save passphrase for selected PGP key

- GIVEN Settings displays private PGP keys `ABC` and `DEF`
- WHEN the user selects key `DEF`
- AND saves a non-empty PGP passphrase
- THEN the security repository stores the passphrase with fingerprint `DEF`
- AND Settings shows that the cached passphrase belongs to key `DEF`

#### Scenario: Passphrase save requires a private PGP key

- GIVEN no private PGP key is selected
- WHEN the user attempts to save a PGP passphrase
- THEN Settings does not save the passphrase
- AND it explains that a PGP key must be selected

#### Scenario: Legacy unbound passphrase is not reused

- GIVEN secure storage contains a cached PGP passphrase without key fingerprint
  metadata
- WHEN the security repository loads
- THEN the repository treats the cached passphrase as absent
- AND the user must save a new key-specific passphrase before biometric unlock
  can restore a PGP session

### Requirement: Deleting a PGP key SHALL clear matching passphrase cache state

Settings SHALL clear any cached PGP passphrase or active PGP session associated
with a PGP key fingerprint when that key is deleted. Cached passphrases for
other PGP keys SHALL remain unchanged.

Sources: `gui/lib/screens/settings/settings_screen.dart`,
`gui/lib/services/security_repository.dart`,
`gui/test/security_repository_test.dart`,
`gui/test/mobile_gui_smoke_test.dart`

#### Scenario: Delete cached-passphrase key clears cache

- GIVEN the cached PGP passphrase is associated with fingerprint `ABC`
- WHEN the user deletes PGP key `ABC` from Settings
- THEN the security repository clears the cached PGP passphrase
- AND clears any active PGP session for fingerprint `ABC`

#### Scenario: Delete unrelated PGP key preserves cache

- GIVEN the cached PGP passphrase is associated with fingerprint `ABC`
- WHEN the user deletes PGP key `DEF` from Settings
- THEN the cached PGP passphrase for fingerprint `ABC` remains available

### Requirement: Settings and Onboarding SHALL share a source-independent PGP import flow

Settings and Onboarding SHALL offer the same PGP import flow with Text and File
as source choices. The flow SHALL use bridge inspection to determine public or
private key kind and passphrase protection, SHALL use a native file picker for
the File source, and SHALL complete using the canonical key record returned by
the bridge. A protected private-key import SHALL not complete until its
passphrase is validated. Successful validation SHALL start an in-memory PGP
session bound to the imported fingerprint and SHALL persist the passphrase only
when the user explicitly opts into Keychain/KMS storage.

#### Scenario: Both GUI surfaces offer Text and File

- **WHEN** the user opens PGP import from Settings or Onboarding
- **THEN** the import flow offers Text and File source choices
- **AND** selecting File opens the native key-file picker inside the import flow

#### Scenario: Source does not determine public or private kind

- **GIVEN** supported public or private PGP material is supplied from Text or
  File
- **WHEN** the GUI inspects the selected material
- **THEN** it follows the public/private kind returned by the bridge
- **AND** it does not assume every file is a private key

#### Scenario: Protected private import requests and validates passphrase

- **GIVEN** inspection identifies passphrase-protected private PGP material
- **WHEN** the user submits the selected text or file
- **THEN** the flow presents an obscured PGP passphrase field
- **AND** import completion remains blocked until validation succeeds

#### Scenario: Incorrect passphrase stays in the import flow

- **GIVEN** a protected private-key passphrase step is visible
- **WHEN** the user enters an incorrect passphrase
- **THEN** the flow shows a sanitized inline validation error
- **AND** it does not advance Onboarding or report Settings import success
- **AND** it does not start or cache a PGP session

#### Scenario: Correct passphrase starts a key-bound session

- **GIVEN** protected private key material imports as fingerprint `ABC`
- **WHEN** the user enters the correct passphrase
- **THEN** the security repository starts an in-memory PGP session for
  fingerprint `ABC`
- **AND** Onboarding selects `ABC` before advancing or Settings refreshes the
  visible key list

#### Scenario: Remembering an imported passphrase is explicit

- **GIVEN** the protected private-key passphrase step is visible
- **WHEN** the user successfully imports the key without selecting Remember in
  Keychain/KMS
- **THEN** the passphrase is not written to durable storage
- **WHEN** the user explicitly selects Remember in Keychain/KMS
- **THEN** the saved passphrase cache is associated with the imported
  fingerprint

#### Scenario: Public and unprotected private imports skip passphrase UI

- **GIVEN** inspection identifies a public key or an unprotected private key
- **WHEN** import succeeds
- **THEN** the flow does not request or persist a PGP passphrase
- **AND** it completes with the returned canonical key record

#### Scenario: Secure-storage failure does not expose the passphrase

- **GIVEN** a protected private key was imported and its in-memory session
  started
- **WHEN** optional Keychain/KMS persistence fails
- **THEN** the GUI reports that remembering the passphrase failed without
  rolling back the imported key
- **AND** clears the passphrase field
- **AND** no error or notification contains the passphrase

### Requirement: Protected PGP sessions SHALL start only after private-key preparation

Flutter PGP orchestration SHALL await pure-Rust private-key import
re-protection, or existing-key preparation and migration, before starting a
fingerprint-bound in-memory PGP session. Preparation SHALL NOT change the
configured session expiration, enable durable passphrase storage, or retain an
unlocked key beyond existing policy. A failed preparation SHALL not create or
extend a session.

#### Scenario: Imported key session waits for commit

- **GIVEN** the shared Settings or Onboarding flow is importing a protected
  private key into the pure-Rust backend
- **WHEN** the user submits the correct passphrase
- **THEN** the import remains pending while the backend validates and
  re-protects the key
- **AND** the session for the returned fingerprint starts only after commit
  succeeds

#### Scenario: Existing legacy key migrates before session activation

- **GIVEN** an existing selected private key uses legacy protection
- **WHEN** a manually entered or securely restored passphrase is used to start
  its PGP session
- **THEN** Flutter awaits fingerprint-bound backend preparation and migration
- **AND** starts the session only after preparation succeeds

#### Scenario: Preparation failure does not start or extend session

- **GIVEN** no active PGP session exists for fingerprint `ABC`
- **WHEN** import re-protection or existing-key preparation for `ABC` fails
- **THEN** no session is started for `ABC`
- **AND** the user can retry without the failed passphrase remaining in the
  input field

#### Scenario: Existing expiration policy remains authoritative

- **GIVEN** private-key preparation succeeds and the configured PGP session
  expiration is five minutes
- **WHEN** Flutter starts the fingerprint-bound session
- **THEN** the session expires under the existing five-minute policy
- **AND** successful migration does not extend, persist, or bypass that policy

### Requirement: Private-key preparation feedback SHALL use existing UI and i18n

Settings, Onboarding, and existing-key unlock flows SHALL present private-key
preparation as part of their established pending and error states. Every new
user-facing progress, success, and failure string introduced by this change
SHALL come from the configured Flutter i18n resources. The change SHALL NOT add
a separate visual style, import sheet, or hard-coded English fallback for the
new states.

#### Scenario: Slow one-time preparation remains visibly pending

- **GIVEN** a legacy key requires a long one-time source S2K operation
- **WHEN** preparation is running
- **THEN** the existing action shows a localized pending state
- **AND** duplicate submission is disabled
- **AND** completion produces a localized success or sanitized failure result

#### Scenario: Typed failure maps to localized text

- **GIVEN** the bridge returns a typed re-protection or migration failure
- **WHEN** Flutter renders the failure
- **THEN** it selects the message through the existing i18n system
- **AND** the rendered message contains no passphrase or private-key material

### Requirement: GUI PGP deletion SHALL reflect verified managed-key removal

Settings SHALL retain human-readable typed confirmation and SHALL NOT request
the PGP passphrase merely to delete the encrypted private-key file. When a PGP
identity is displayed as `Display Name <email>`, the required confirmation
SHALL be only `Display Name`; the email address SHALL NOT be required. After the
bridge confirms that managed private material is absent,
Settings SHALL clear the matching active session and securely stored
passphrase, refresh the key list, and show localized outcome text. If private
removal fails, Settings SHALL preserve matching security state and keep the key
visible. If only public cleanup fails, Settings SHALL report localized partial
success and SHALL NOT claim the private key remains installed. `.gpg-id`
references SHALL remain unchanged.

#### Scenario: Complete GUI deletion clears matching authorization

- **GIVEN** Settings displays protected PGP key `ABC` and its matching session or
  securely stored passphrase exists
- **WHEN** the user types the displayed human-readable key name and deletion
  confirms both private and public records absent
- **THEN** Settings clears the session and stored passphrase for `ABC`
- **AND** refreshes the list and shows a localized deletion success

#### Scenario: Deletion does not request the private-key passphrase

- **GIVEN** the delete confirmation is open for protected PGP key `ABC`
- **WHEN** the user supplies the required human-readable key-name confirmation
- **THEN** Settings submits deletion without requesting or transmitting the PGP
  passphrase

#### Scenario: PGP email is excluded from typed confirmation

- **GIVEN** Settings displays PGP identity `Alice <alice@example.com>`
- **WHEN** the user opens its delete confirmation
- **THEN** the required confirmation value is `Alice`
- **AND** the user is not required to type `<alice@example.com>`

#### Scenario: Delete confirmation remains usable above the keyboard

- **GIVEN** the PGP delete confirmation is displayed on a phone-sized viewport
- **WHEN** the software keyboard opens for the confirmation field
- **THEN** the dialog content can scroll within the remaining height
- **AND** the confirmation field and delete action remain reachable without a
  layout overflow

#### Scenario: Private removal failure preserves security state and visibility

- **GIVEN** deletion of `ABC` cannot confirm its private record absent
- **WHEN** Settings receives the failure
- **THEN** it does not clear `ABC`'s matching session or stored passphrase
- **AND** it refreshes or preserves the visible key record and shows a localized
  failure

#### Scenario: Public cleanup failure clears secrets and reports partial success

- **GIVEN** deletion confirms `ABC`'s private record absent but public cleanup
  failed
- **WHEN** Settings handles the structured bridge response
- **THEN** it clears `ABC`'s matching session and stored passphrase
- **AND** refreshes the list and shows a localized partial-success warning
- **AND** any `.gpg-id` reference remains visible as missing local key material

### Requirement: Authenticated GUI SHALL provide immediate manual lock

The authenticated GUI SHALL expose a clearly named Lock now action from the Vault or shell header. Lock now SHALL call the existing full lock path, clear the active in-memory PGP session, dispose decrypted detail content, and render the lock screen without changing durable onboarding, key, store, favorite, or locale state.

#### Scenario: User locks from Vault
- **GIVEN** the app is unlocked
- **WHEN** the user activates Lock now
- **THEN** the security repository is marked locked
- **AND** any active PGP session and decrypted detail content are cleared
- **AND** the lock screen replaces the authenticated shell

#### Scenario: Manual lock preserves durable configuration
- **WHEN** Lock now completes
- **THEN** persisted onboarding, language, keys, stores, favorites, and secure-storage preferences remain unchanged

### Requirement: Authenticated and secret GUI surfaces SHALL protect background and capture privacy

Release builds SHALL obscure authenticated Pars content in application-switcher snapshots and SHALL prevent or obscure screenshots and screen recording of revealed passwords, parsed secret fields, passphrase inputs, QR payloads, and private-key material where the platform provides a supported mechanism. Entering a protected background state SHALL clear or cover decrypted detail content without altering vault data. Platform privacy policy SHALL NOT interfere with system-owned Autofill authentication or credential-return contracts.

#### Scenario: Android authenticated window is protected
- **GIVEN** a release Android build is displaying the authenticated shell
- **WHEN** the system attempts a screenshot, recording, or recents snapshot
- **THEN** Pars applies the supported secure-window policy
- **AND** revealed secret content is not captured

#### Scenario: iOS application switcher is covered
- **GIVEN** iOS is displaying authenticated Pars content
- **WHEN** the app resigns active for the application switcher
- **THEN** a privacy cover obscures authenticated content before the snapshot
- **AND** the cover is removed only after a safe active-state transition

#### Scenario: Privacy transition does not mutate the vault
- **WHEN** Pars covers or clears a sensitive presentation for background privacy
- **THEN** no entry, key, Git, store, or Autofill record is mutated
- **AND** reopening a cleared detail uses the ordinary authenticated decrypt path

#### Scenario: System Autofill remains independently usable
- **WHEN** an Android or iOS Autofill provider authenticates and resolves a selected credential while the main app window is protected
- **THEN** the provider follows its existing system-owned authentication and exactly-one-decrypt flow
- **AND** main-window capture protection does not cause an empty credential to be filled

### Requirement: Gesture unlock SHALL expose an accessible non-drawing interaction

Gesture setup and unlock SHALL retain drawing input and the existing ordered-dot verifier while also exposing each dot as an assistive-technology action with selected state. Localized Clear and Submit actions SHALL allow the same ordered pattern to be entered without a continuous drawing gesture. The accessible interaction SHALL create no new persisted credential and SHALL never announce or log the completed pattern.

#### Scenario: Screen reader enters an existing gesture pattern
- **GIVEN** assistive technology is active
- **WHEN** the user activates gesture dots in order and invokes Submit
- **THEN** the resulting ordered dot list is verified by the existing gesture verifier
- **AND** successful verification unlocks through the existing path

#### Scenario: Accessible gesture can be corrected
- **GIVEN** one or more dots have been selected through semantic actions
- **WHEN** the user invokes Clear
- **THEN** selection resets without a verification attempt
- **AND** the cleared state is announced

#### Scenario: Incorrect accessible pattern remains secret
- **WHEN** an accessible gesture submission does not match
- **THEN** Pars announces a localized mismatch
- **AND** it does not announce, log, persist, or include the selected pattern in an error

### Requirement: Lock, onboarding, and Settings SHALL remain usable with large text and assistive technology

Lock, onboarding, and Settings primary workflows SHALL expose ordered focus, accessible names, selected/busy/error states, and scrollable keyboard-safe actions. At 200% text scaling, required setup, unlock, language, key repair, store setup, and destructive confirmation actions SHALL remain reachable without overflow.

#### Scenario: Lock remains usable at large text
- **GIVEN** text scaling is 200% on a compact phone
- **WHEN** the lock screen renders
- **THEN** gesture and available biometric actions remain reachable
- **AND** mismatch feedback is visible and announced without clipping

#### Scenario: Onboarding form remains reachable above keyboard
- **GIVEN** an onboarding form requires text or confirmation input
- **WHEN** the software keyboard opens at 200% text scaling
- **THEN** content scrolls within the remaining viewport
- **AND** the required submit action remains reachable

## Needs Verification

- Gesture verifier uses a compact FNV-like 32-bit fingerprint value. Whether
  this is sufficient for the intended threat model needs security review.
- Biometric availability and secure storage behavior depend on platform
  adapters and device state; tests use fakes.
- PGP passphrase storage uses platform secure storage, but bridge PGP decrypt
  APIs do not currently accept an active passphrase from Flutter.
