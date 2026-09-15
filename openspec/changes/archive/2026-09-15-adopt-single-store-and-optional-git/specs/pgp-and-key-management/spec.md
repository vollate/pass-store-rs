## ADDED Requirements

### Requirement: Bridge PGP setup APIs SHALL list, inspect, import, and generate keys contextually

The GUI bridge SHALL expose the PGP operations required to list usable local material, inspect text or file input, import public or private material with exact-key passphrase validation, generate a new private key for new-store creation, and prepare a selected private key for a session. It SHALL NOT expose general Flutter PGP export, delete, or append-to-`.gpg-id` operations. Inspection and import SHALL derive key kind and canonical primary-key fingerprint from the supplied material rather than its source.

#### Scenario: Text and file sources detect key kind independently

- **GIVEN** supported PGP public or private material is supplied as text, an armored file, or a binary OpenPGP file
- **WHEN** contextual PGP inspection runs
- **THEN** it returns the material's public/private kind and canonical fingerprint
- **AND** it does not derive kind from whether Text or File was selected

#### Scenario: Incorrect protected-key passphrase does not mutate the keyring

- **GIVEN** private import material is protected by a passphrase
- **WHEN** contextual import receives no passphrase or an incorrect passphrase
- **THEN** it returns a typed sanitized validation failure
- **AND** the configured keyring is not mutated

#### Scenario: Correct protected-key passphrase completes import

- **GIVEN** protected private material has canonical fingerprint `ABC`
- **WHEN** contextual import receives the correct passphrase
- **THEN** exact encryption-capable private material is validated and imported
- **AND** the result identifies fingerprint `ABC`

#### Scenario: Unprotected private key imports without a passphrase

- **GIVEN** supported private PGP material is not passphrase-protected
- **WHEN** it is imported without a passphrase
- **THEN** import succeeds and returns its canonical fingerprint

#### Scenario: New-store creation can generate recipients

- **GIVEN** Create needs a recipient for a new `.gpg-id`
- **WHEN** the user generates a new private PGP key successfully
- **THEN** the generated canonical fingerprint may be written as a new-store recipient
- **AND** the operation does not modify any existing store

### Requirement: Existing store `.gpg-id` recipients SHALL remain authoritative

Import, Clone, unlock, and missing-key repair SHALL treat the nearest applicable `.gpg-id` recipients as authoritative. Repair SHALL make matching private material available and SHALL NOT append or substitute an unrelated local fingerprint. Recipient changes to an existing store SHALL require a separate explicit migration that defines re-encryption behavior.

#### Scenario: Import does not append the onboarding key

- **GIVEN** an imported store `.gpg-id` contains recipient `ABC`
- **AND** another local private key `DEF` exists
- **WHEN** Import and repair complete
- **THEN** `.gpg-id` still contains its original recipients
- **AND** `DEF` is not appended automatically

#### Scenario: Matching private import satisfies existing recipient

- **GIVEN** an existing store requires recipient `ABC`
- **AND** local private material for `ABC` is absent
- **WHEN** the user imports valid private material for `ABC`
- **THEN** required-key repair can complete
- **AND** `.gpg-id` is not rewritten

#### Scenario: Nonmatching key cannot satisfy repair

- **GIVEN** an existing store requires recipient `ABC`
- **WHEN** contextual repair imports or selects key `DEF`
- **THEN** repair remains incomplete
- **AND** the store recipients remain unchanged

#### Scenario: New store writes selected recipients once

- **GIVEN** Create is initializing a new password store
- **WHEN** one or more usable private-key fingerprints are selected for that new store
- **THEN** the new root `.gpg-id` is written with those normalized recipients
- **AND** duplicate recipient lines are not created

## REMOVED Requirements

### Requirement: Bridge PGP key management SHALL generate, import, list, and export keys

**Reason**: Permanent GUI PGP administration and private/public export are outside the contextual setup and required-recipient repair model.

**Migration**: Use the contextual bridge PGP setup APIs for list, inspection, import, generation, and private-key preparation. CLI or backend-specific tooling remains responsible for general PGP administration.

### Requirement: GUI-facing PGP key management SHALL delete local PGP keys

**Reason**: General Flutter PGP deletion can remove active password-store key material without recipient rotation and re-encryption.

**Migration**: No permanent GUI deletion action is provided. A future explicit PGP migration must verify recipient replacement and entry re-encryption before deleting obsolete material.

### Requirement: Selected PGP keys SHALL be appended to root `.gpg-id` once

**Reason**: Automatically appending a locally selected key mutates imported or cloned recipient policy and can mask a missing required private key.

**Migration**: Preserve existing `.gpg-id`; import matching private material for repair. Write selected recipients only while creating a new store or through a future explicit recipient-rotation migration.
