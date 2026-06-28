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

Onboarding SHALL start with gesture setup when no verifier exists, then optional
biometrics, PGP key selection/creation/import, optional SSH setup, store setup
when store lifecycle requires it, and review. Finish SHALL require store setup
to be complete and SHALL persist onboarding completion and mark unlocked.

Sources: `gui/lib/screens/onboarding/onboarding_screen.dart`,
`gui/lib/services/store_lifecycle.dart`,
`gui/lib/services/key_repository.dart`

#### Scenario: Finish onboarding marks app ready

- GIVEN review step is reached
- AND store setup no longer requires setup
- WHEN Finish setup is pressed
- THEN onboarding completion is saved
- AND the security repository is marked unlocked

### Requirement: Settings SHALL expose security, key, store, Git, and diagnostics surfaces

Settings SHALL expose gesture/biometric controls, PGP session timeout,
secure-storage passphrase cache controls, PGP and SSH key management, password
store management, Git sync/remotes, advanced Git args, and runtime diagnostics.

Sources: `gui/lib/screens/settings/settings_screen.dart`,
`gui/lib/services/runtime_diagnostics.dart`

#### Scenario: Reset onboarding clears onboarding completion

- WHEN Reset onboarding is selected in security settings
- THEN onboarding completion is set to false
- AND the app callback resets the onboarding view

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
keys. Before deleting key material, the UI SHALL require confirmation that
identifies the exact key, and deletion failures SHALL be shown to the user
without removing the key from the visible list.

Sources: `gui/lib/screens/settings/settings_screen.dart`,
`gui/test/mobile_gui_smoke_test.dart`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete PGP key from settings

- GIVEN Settings displays a PGP key with fingerprint `ABC`
- WHEN the user chooses delete for that key
- AND confirms deletion using the required confirmation text
- THEN Settings calls the PGP key delete operation for fingerprint `ABC`
- AND refreshes the visible key list after deletion succeeds

#### Scenario: Delete SSH key from settings

- GIVEN Settings displays an SSH key named `mobile-key`
- WHEN the user chooses delete for that key
- AND confirms deletion using the required confirmation text
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

## Needs Verification

- Gesture verifier uses a compact FNV-like 32-bit fingerprint value. Whether
  this is sufficient for the intended threat model needs security review.
- Biometric availability and secure storage behavior depend on platform
  adapters and device state; tests use fakes.
- PGP passphrase storage uses platform secure storage, but bridge PGP decrypt
  APIs do not currently accept an active passphrase from Flutter.
