## ADDED Requirements

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
