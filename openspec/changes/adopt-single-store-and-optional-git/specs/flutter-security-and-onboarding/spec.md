## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Onboarding SHALL progress through local unlock, optional biometrics, keys, store, and review

Onboarding SHALL separate first-run local security from password-store setup. It SHALL require an accessible local gesture verifier, MAY offer biometrics without blocking progress, and SHALL then present Import and Clone as primary store-source actions plus Create as a secondary action. Import or Clone SHALL be completed before PGP repair so `.gpg-id` determines required private material. Create SHALL request recipients only as part of creating `.gpg-id`. SSH setup SHALL appear only for an SSH-form clone or later Git transport configuration. When security and the canonical store are ready, onboarding SHALL enter Vault without a fixed expert step rail or mandatory review step.

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

## REMOVED Requirements

### Requirement: Settings key sheets SHALL separate global add actions from per-key actions

**Reason**: The permanent PGP key sheet is removed and SSH management moves under Git synchronization.

**Migration**: Use the SSH management surface for SSH CRUD and the contextual PGP setup/repair flow for required private material.

### Requirement: Settings SHALL allow deleting existing PGP and SSH keys

**Reason**: Combining PGP and SSH deletion under general key management permits removal of active encryption material without a recipient migration plan.

**Migration**: SSH deletion remains under Git synchronization; Flutter no longer exposes general PGP deletion.

### Requirement: Deleting a PGP key SHALL clear matching passphrase cache state

**Reason**: Flutter Settings no longer exposes PGP key deletion.

**Migration**: Session and durable passphrase cleanup remains part of store removal, lock/privacy behavior, and any future explicit PGP migration rather than ordinary key CRUD.

### Requirement: Settings and Onboarding SHALL share a source-independent PGP import flow

**Reason**: PGP import is no longer available from permanent Settings key management.

**Migration**: Use the added contextual PGP setup and repair requirement, which retains source-independent Text/File inspection and exact-key passphrase preparation.

### Requirement: GUI PGP deletion SHALL reflect verified managed-key removal

**Reason**: General GUI PGP deletion is removed to prevent active store key loss without recipient rotation and re-encryption.

**Migration**: Existing backend deletion primitives are not exposed by Flutter; a future recipient-rotation change must define safe migration and deletion semantics.
