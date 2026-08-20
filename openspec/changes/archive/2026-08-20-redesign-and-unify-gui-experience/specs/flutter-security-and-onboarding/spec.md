## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Authenticated GUI SHALL provide immediate manual lock

The authenticated GUI SHALL expose a clearly named Lock now action from the Vault or shell header. Lock now SHALL call the existing full lock path, clear the active in-memory PGP session, dispose decrypted detail content, and render the lock screen without changing durable onboarding, key, store, favorite, recent, or locale state.

#### Scenario: User locks from Vault
- **GIVEN** the app is unlocked
- **WHEN** the user activates Lock now
- **THEN** the security repository is marked locked
- **AND** any active PGP session and decrypted detail content are cleared
- **AND** the lock screen replaces the authenticated shell

#### Scenario: Manual lock preserves durable configuration
- **WHEN** Lock now completes
- **THEN** persisted onboarding, language, keys, stores, favorites, recents, and secure-storage preferences remain unchanged

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
