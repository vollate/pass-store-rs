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
lock-on-resume, biometric enablement, PGP passphrase storage enablement, the
key-bound PGP private-key passphrase, onboarding completion, PGP session
expiration, and auto-lock timeout through the configured secure storage adapter.

Sources: `gui/lib/services/security_repository.dart`,
`gui/test/security_repository_test.dart`

#### Scenario: Active unlock sessions are not persisted

- GIVEN a repository is marked unlocked
- WHEN a new repository is loaded from the same storage
- THEN the new repository should lock until unlocked again

### Requirement: The PGP private-key passphrase SHALL be the only durable secret and SHALL live in system keystore storage

The passphrase that unlocks a local PGP private key SHALL be the only secret
Pars persists. Its durable storage SHALL remain opt-in and bound to one key
fingerprint, and it SHALL be written exclusively through platform
keystore-backed secure storage: Android Keystore on Android and the Keychain on
Apple platforms. Native Autofill publication SHALL re-protect the republished
copy with the same platform keystore facilities. Wherever this specification or
the Autofill specification mentions a stored, cached, or published passphrase, it
means that PGP private-key passphrase and never decrypted store content.

Decrypted entry content — passwords, parsed fields, TOTP values, and notes —
SHALL NEVER be persisted by app storage, an on-disk cache, the Autofill index,
or native published state. In-memory PGP sessions and passphrases typed for a
single operation SHALL stay in memory and SHALL NOT be written anywhere.

Sources: `gui/lib/services/security_repository.dart`,
`gui/android/app/src/main/kotlin/top/vollate/pars_gui/autofill/ParsAutofillStateStore.kt`,
`gui/ios/Shared/ParsAutofillSharedState.swift`

#### Scenario: Durable passphrase storage is keystore-backed and opt-in

- GIVEN the user has not enabled durable passphrase storage
- THEN no PGP passphrase is readable from secure storage
- WHEN the user explicitly saves a passphrase for a selected private key
- THEN it is written only through the platform keystore-backed adapter
- AND disabling storage removes it again

#### Scenario: No decrypted content becomes durable

- GIVEN an entry has been decrypted and displayed, autofilled, or enriched
- WHEN app storage, on-disk caches, the Autofill index, and native published
  state are inspected
- THEN none of them contains the decrypted password, fields, TOTP value, or
  notes

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
expired, or the security repository reports `shouldLock`. System file pickers,
folder pickers, and managed-store import SHALL suppress that lock while the
system UI is open and for a short grace period after it returns, so the form
that opened the picker stays mounted and keeps the selected path.

Sources: `gui/lib/app/pars_gui_app.dart`

#### Scenario: System-auth grace period suppresses lifecycle lock

- WHEN an action runs through `runDuringSystemAuthentication`
- THEN lifecycle locks are suppressed while system auth is active
- AND for a short grace period after it completes

#### Scenario: Returning from a file picker does not lock

- GIVEN lock-on-resume is enabled and the session is unlocked
- WHEN a file picker sends the app to the background and then returns
- THEN the lock screen is not shown
- AND the picker result remains on the form that requested it

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

Onboarding SHALL separate first-run local security from password-store setup. It SHALL require an accessible local gesture verifier, MAY offer biometrics without blocking progress, and SHALL then present Import and Clone as primary store-source actions plus Create as a secondary action. Import or Clone SHALL be completed before PGP repair so `.gpg-id` determines required private material. Create SHALL request recipients only as part of creating `.gpg-id`. Whenever onboarding needs store setup, including after a previously completed onboarding loses its store, it SHALL show a required PGP step and then an optional SSH step after biometrics and before store setup, and progress SHALL count the full gesture, biometrics, PGP, SSH, and store sequence. The PGP step lists local private PGP keys, offers Create and Import, and continues only once a private key exists; the chosen key (implicitly the only one) becomes the recipient of a newly created store. The SSH step lets a key be imported or generated before a store is cloned; the store setup page itself keeps only the Import, Clone, and Create actions. Generating an SSH key SHALL immediately show its public key with a copy action, and every listed SSH key SHALL expose its public key. The store remains usable when SSH is skipped. An SSH-form clone SHALL still offer import or generation when no key is present. When security and the canonical store are ready, onboarding SHALL enter Vault without a fixed expert step rail or mandatory review step.

Sources: `gui/lib/screens/onboarding/onboarding_screen.dart`, `gui/lib/services/store_lifecycle.dart`, `gui/lib/services/key_repository.dart`

#### Scenario: Essential flow starts with security then store source

- **GIVEN** a new user has no gesture verifier or canonical store
- **WHEN** onboarding renders
- **THEN** it first establishes required local unlock
- **AND** then offers Import, Clone, and secondary Create
- **AND** it does not require a Gesture/Biometrics/PGP/SSH/Store/Review rail

#### Scenario: Store removal does not repeat security onboarding

- **GIVEN** local security onboarding is complete and the app is unlocked
- **AND** the canonical store is deleted or disconnected
- **WHEN** root lifecycle state refreshes
- **THEN** onboarding opens directly at store setup
- **AND** gesture and biometric setup are not reset

#### Scenario: Import discovers recipients before PGP repair

- **GIVEN** no canonical store is configured
- **WHEN** Import finalizes a password store
- **THEN** onboarding inspects that store's `.gpg-id`
- **AND** it requests PGP repair only if required private material is unavailable

#### Scenario: First-run onboarding offers SSH before store setup

- **GIVEN** gesture and biometrics are already handled, on first run or after the store was removed
- **WHEN** a store still needs to be set up
- **THEN** a required PGP step offers key creation and import as step 3 of 5
- **AND** Continue stays disabled until a private PGP key exists
- **AND** an optional SSH step offers key import and generation as step 4 of 5
- **AND** store setup is step 5 of 5
- **AND** Skip SSH or Continue leads to store setup with Import, Clone, and Create
- **AND** the store setup page does not repeat the SSH import and generation block

#### Scenario: Generated SSH key shows its public key

- **GIVEN** the user generates an SSH key in onboarding or Settings
- **WHEN** generation succeeds
- **THEN** the public key is shown with Copy and GitHub settings actions
- **AND** the key appears in the SSH key list without reopening it

#### Scenario: Clone requests only relevant transport setup

- **GIVEN** no SSH key is configured
- **WHEN** the user clones over HTTPS
- **THEN** SSH setup is not shown as a prerequisite
- **WHEN** the user clones over SSH and needs a key
- **THEN** SSH import or generation is offered in that clone context

#### Scenario: Required key repair remains blocking

- **GIVEN** the canonical store references PGP material that is not usable locally
- **WHEN** onboarding evaluates readiness
- **THEN** it presents contextual matching private-key import or repair
- **AND** Vault remains unavailable until required key state is usable

#### Scenario: Pure-Rust recipient inspection requires private material

- **GIVEN** mobile uses the configured pure-Rust PGP keyring
- **AND** `.gpg-id` contains one or more recipients
- **WHEN** app state is inspected
- **THEN** at least one usable recipient must match listed local private-key material
- **AND** a missing or public-only match reports required key repair

#### Scenario: Optional capabilities remain deferrable

- **GIVEN** local security and canonical store repair are complete
- **WHEN** biometrics, Git, a remote, or SSH is unavailable or skipped
- **THEN** onboarding can enter Vault
- **AND** optional capabilities remain available later in Settings

#### Scenario: Existing transactional setup behavior is preserved

- **WHEN** onboarding imports a protected key, handles an app-managed store conflict, creates a store, or clones a store
- **THEN** it uses validated picker, preparation, staging, conflict, and transactional repository behavior
- **AND** presentation code does not duplicate those operations

### Requirement: Settings SHALL expose security, key, store, Git, and diagnostics surfaces

Settings SHALL organize configuration into Appearance, Security and privacy, Password store, Git synchronization, Autofill, and Advanced/support groups. Appearance SHALL expose persisted System/English/Chinese language choice. Password store SHALL show one canonical store and offer app-managed Delete local copy or external Disconnect, without a store list, switcher, or default action. Git SHALL present disabled, local, or remote capability truthfully and SHALL contain optional SSH management. Settings SHALL retain PGP passphrase/session controls but SHALL NOT expose permanent PGP key CRUD. Technical commands, internal paths, and diagnostics SHALL remain progressively disclosed.

Sources: `gui/lib/screens/settings/settings_screen.dart`, `gui/lib/services/runtime_diagnostics.dart`

#### Scenario: Routine settings precede advanced diagnostics

- **WHEN** Settings home renders
- **THEN** appearance, security/privacy, password store, Git synchronization, and Autofill precede advanced/support
- **AND** Runtime diagnostics and advanced Git args do not receive routine-setting prominence

#### Scenario: Language is changed from Appearance

- **WHEN** the user selects System, English, or Chinese in Appearance
- **THEN** the UI foundation applies and persists that locale preference
- **AND** Settings remains on an equivalent route after the live language change

#### Scenario: Password store presents one canonical root

- **GIVEN** a canonical store exists
- **WHEN** Password store settings render
- **THEN** they show that store's concise identity and state
- **AND** they do not show alternate stores, Select, or Set default actions

#### Scenario: Technical status is summarized

- **GIVEN** a capability is unavailable, stale, or failed
- **WHEN** its Settings row renders
- **THEN** the row shows a concise localized state with appropriate semantics
- **AND** bounded technical details are available only through an explicit details or diagnostics action

#### Scenario: Git-disabled status is not an error

- **GIVEN** the canonical password store intentionally has no `.git`
- **WHEN** Settings renders Git synchronization
- **THEN** it shows a localized disabled/local-only state and an Enable Git action
- **AND** it does not report sync failure

#### Scenario: Reset onboarding does not manufacture a store

- **WHEN** Reset onboarding is selected and confirmed
- **THEN** security onboarding completion is reset according to existing security semantics
- **AND** the next flow still derives store availability from the actual canonical lifecycle snapshot

### Requirement: Settings and Onboarding SHALL use native path selectors for filesystem paths

Flutter Settings and Onboarding SHALL use platform-native file or folder
selectors as the primary UI for user-facing filesystem path choices. Affected
forms SHALL show a compact no-icon picker row that displays the default/base
path before selection and the selected path after selection. The store-folder
selection UI and key-file selection UI SHALL remain in their existing separate
interfaces and SHALL NOT be merged into one popup or form. SSH key-file
selection SHALL display the location the user selected and SHALL NOT copy the
source file into app storage during selection. The name field SHALL be filled
from the selected file name and SHALL remain editable. Submitting SHALL read
that selection, and SHALL write the converted OpenSSH private key into app data
only after the material is accepted.

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

#### Scenario: App-managed clone does not show a store folder

- **GIVEN** clone stores its result in app-managed storage
- **WHEN** the clone form is shown
- **THEN** the form asks for the remote URL
- **AND** it does not show a store folder row
- **AND** the clone root is the app-managed path derived from the remote URL

#### Scenario: Clone failure can be opened in Details

- **GIVEN** submitting the clone form fails
- **WHEN** the form shows the failure
- **THEN** the summary stays the localized operation-failed text
- **AND** a Details action reveals the sanitized failure text

#### Scenario: Key file import uses a separate file picker row

- **GIVEN** the user opens a PGP or SSH key-file import flow
- **WHEN** the import file form is shown
- **THEN** the form shows a compact no-icon row for the key file
- **AND** the row displays `Default: <path>` before selection
- **AND** the key-file picker remains inside the key import interface, separate
  from store folder selection interfaces
- **AND** the form does not show an editable path text field

#### Scenario: PGP key file import submits selected file path

- **GIVEN** a PGP key-file import form shows a key file picker row
- **WHEN** the platform file selector returns a file path
- **THEN** the row displays `Selected: <path>` with that file path
- **AND** submitting the form passes that selected file path to the existing key
  import repository operation

#### Scenario: SSH key file selection shows the chosen location

- **GIVEN** an SSH key-file import form
- **WHEN** the user selects a private key file
- **THEN** the row displays `Selected:` with the location the user selected
- **AND** the source file is not copied into app storage
- **AND** the name field is filled with the selected file name
- **AND** the name field remains editable

#### Scenario: SSH key file import stores the converted key only after it is accepted

- **GIVEN** an SSH key-file import form has a selected private key file
- **WHEN** the user submits the import
- **THEN** the selected file is read and checked before anything is written
- **AND** a rejected key leaves app storage unchanged
- **AND** an accepted key is written to app data as the converted OpenSSH private key

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

### Requirement: Authenticated GUI SHALL provide immediate manual lock

The authenticated GUI SHALL expose a clearly named Lock now action from the Vault or shell header. Lock now SHALL call the existing full lock path, clear the active in-memory PGP session, dispose decrypted detail content, and render the lock screen without changing durable onboarding, key, store, or locale state.

#### Scenario: User locks from Vault
- **GIVEN** the app is unlocked
- **WHEN** the user activates Lock now
- **THEN** the security repository is marked locked
- **AND** any active PGP session and decrypted detail content are cleared
- **AND** the lock screen replaces the authenticated shell

#### Scenario: Manual lock preserves durable configuration
- **WHEN** Lock now completes
- **THEN** persisted onboarding, language, keys, stores, and secure-storage preferences remain unchanged

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

### Requirement: Settings SHALL manage SSH keys without exposing permanent PGP key CRUD

Settings SHALL place SSH key creation, import, public/private export, and deletion under Git synchronization. It SHALL NOT expose a permanent PGP key list or general PGP create, export, append-to-`.gpg-id`, or delete actions. PGP passphrase/session controls SHALL remain under Security and privacy.

#### Scenario: SSH management is available under Git

- **WHEN** the user opens Git synchronization settings
- **THEN** SSH key management is reachable
- **AND** existing SSH keys expose supported per-key export and delete actions

#### Scenario: Settings has no general PGP key page

- **WHEN** Settings home and nested routes render
- **THEN** there is no permanent PGP keys management destination
- **AND** PGP passphrase/session security controls remain available

#### Scenario: Local-only store does not require SSH

- **GIVEN** the canonical store has Git disabled or has no SSH remote
- **WHEN** Settings renders SSH capability
- **THEN** SSH is presented as an optional Git transport capability
- **AND** store readiness does not depend on configuring an SSH key

### Requirement: Contextual PGP setup and repair SHALL follow the canonical store recipients

Flutter SHALL expose PGP key selection, generation, or import only while creating a store, satisfying a missing `.gpg-id`, or repairing required private material. For an existing `.gpg-id`, the flow SHALL accept only private material matching a required recipient and SHALL NOT append a different selected fingerprint. Protected private import SHALL use the source-independent Text/File inspection and preparation flow, start a fingerprint-bound session only after validation, and persist a passphrase only after explicit consent.

#### Scenario: Existing matching private key completes repair

- **GIVEN** the canonical store `.gpg-id` references fingerprint `ABC`
- **AND** local private material for `ABC` is usable
- **WHEN** repair evaluates the store
- **THEN** the store can become ready without editing `.gpg-id`

#### Scenario: Nonmatching imported private key is rejected for repair

- **GIVEN** the canonical store requires fingerprint `ABC`
- **WHEN** the user imports private key `DEF` through the repair flow
- **THEN** the flow does not mark repair complete
- **AND** `.gpg-id` remains unchanged

#### Scenario: Public-only material cannot complete repair

- **GIVEN** `.gpg-id` references fingerprint `ABC`
- **AND** local records contain only the public key for `ABC`
- **WHEN** repair evaluates readiness
- **THEN** repair remains required
- **AND** the public-only record is not offered as a usable private key

#### Scenario: Text and File sources use the same inspection flow

- **WHEN** contextual setup or repair opens PGP import
- **THEN** Text and File source choices use bridge inspection to determine public/private kind and protection
- **AND** the selected source does not predetermine key kind

#### Scenario: Protected matching import validates before completion

- **GIVEN** matching private material is protected by a passphrase
- **WHEN** the user imports it during setup or repair
- **THEN** completion remains blocked until exact-key passphrase validation and private-key preparation succeed
- **AND** incorrect passphrases produce sanitized inline feedback without starting or caching a session

#### Scenario: Remembering a contextual passphrase is explicit

- **GIVEN** a protected matching private key was prepared successfully
- **WHEN** the user does not select Remember in Keychain/KMS
- **THEN** only the in-memory fingerprint-bound PGP session is started
- **AND** no passphrase is durably stored

## Needs Verification

- Gesture verifier uses a compact FNV-like 32-bit fingerprint value. Whether
  this is sufficient for the intended threat model needs security review.
- Biometric availability and secure storage behavior depend on platform
  adapters and device state; tests use fakes.
- Platform keystore guarantees for the stored PGP passphrase depend on device
  hardware and OS state; tests use fake secure-storage adapters.
