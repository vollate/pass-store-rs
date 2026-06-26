## ADDED Requirements

### Requirement: Settings SHALL allow deleting existing PGP and SSH keys

Settings key management SHALL expose delete actions for existing PGP and SSH
keys. Before deleting key material, the UI SHALL require confirmation that
identifies the exact key, and deletion failures SHALL be shown to the user
without removing the key from the visible list.

#### Scenario: Delete PGP key from settings

- **GIVEN** Settings displays a PGP key with fingerprint `ABC`
- **WHEN** the user chooses delete for that key
- **AND** confirms deletion using the required confirmation text
- **THEN** Settings calls the PGP key delete operation for fingerprint `ABC`
- **AND** refreshes the visible key list after deletion succeeds

#### Scenario: Delete SSH key from settings

- **GIVEN** Settings displays an SSH key named `mobile-key`
- **WHEN** the user chooses delete for that key
- **AND** confirms deletion using the required confirmation text
- **THEN** Settings calls the SSH key delete operation for name `mobile-key`
- **AND** refreshes the visible key list after deletion succeeds

#### Scenario: Delete key cancellation preserves the key

- **GIVEN** a key deletion confirmation dialog is open
- **WHEN** the user cancels the dialog or enters incorrect confirmation text
- **THEN** Settings does not call the key delete operation
- **AND** the key remains visible

### Requirement: PGP passphrase cache SHALL be associated with a selected PGP key

The PGP passphrase cache SHALL store the selected PGP key fingerprint alongside
the cached passphrase. Settings SHALL require the user to choose a private PGP
key before saving a passphrase, and all UI labels for stored passphrase state
SHALL identify the associated key.

#### Scenario: Save passphrase for selected PGP key

- **GIVEN** Settings displays private PGP keys `ABC` and `DEF`
- **WHEN** the user selects key `DEF`
- **AND** saves a non-empty PGP passphrase
- **THEN** the security repository stores the passphrase with fingerprint `DEF`
- **AND** Settings shows that the cached passphrase belongs to key `DEF`

#### Scenario: Passphrase save requires a private PGP key

- **GIVEN** no private PGP key is selected
- **WHEN** the user attempts to save a PGP passphrase
- **THEN** Settings does not save the passphrase
- **AND** it explains that a PGP key must be selected

#### Scenario: Legacy unbound passphrase is not reused

- **GIVEN** secure storage contains a cached PGP passphrase without key
  fingerprint metadata
- **WHEN** the security repository loads
- **THEN** the repository treats the cached passphrase as absent
- **AND** the user must save a new key-specific passphrase before biometric
  unlock can restore a PGP session

### Requirement: Deleting a PGP key SHALL clear matching passphrase cache state

Settings SHALL clear any cached PGP passphrase or active PGP session associated
with a PGP key fingerprint when that key is deleted. Cached passphrases for
other PGP keys SHALL remain unchanged.

#### Scenario: Delete cached-passphrase key clears cache

- **GIVEN** the cached PGP passphrase is associated with fingerprint `ABC`
- **WHEN** the user deletes PGP key `ABC` from Settings
- **THEN** the security repository clears the cached PGP passphrase
- **AND** clears any active PGP session for fingerprint `ABC`

#### Scenario: Delete unrelated PGP key preserves cache

- **GIVEN** the cached PGP passphrase is associated with fingerprint `ABC`
- **WHEN** the user deletes PGP key `DEF` from Settings
- **THEN** the cached PGP passphrase for fingerprint `ABC` remains available
