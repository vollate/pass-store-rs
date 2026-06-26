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
