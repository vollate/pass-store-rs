## ADDED Requirements

### Requirement: GUI-facing PGP key management SHALL delete local PGP keys

The GUI-facing key-management API SHALL support deleting a local PGP key by
fingerprint through the configured PGP backend. Deletion SHALL remove local
public key material and local private key material for that fingerprint when
present, and SHALL report an error when the key cannot be found or cannot be
deleted.

#### Scenario: Delete PGP key by fingerprint

- **GIVEN** a PGP key exists in the configured backend
- **WHEN** the GUI-facing delete PGP key API is called with that fingerprint
- **THEN** the key is removed from subsequent key listings
- **AND** local private key material for that fingerprint is removed when it
  exists

#### Scenario: Missing PGP key deletion reports an error

- **GIVEN** no local PGP key matches fingerprint `ABC`
- **WHEN** the GUI-facing delete PGP key API is called with fingerprint `ABC`
- **THEN** the API returns a key-management error

### Requirement: GUI-facing SSH key management SHALL delete local SSH keys

The GUI-facing key-management API SHALL support deleting a local SSH key by key
name from the configured SSH directory. Deletion SHALL remove both the private
key file and matching `.pub` public key file when present, and SHALL report an
error when neither file exists.

#### Scenario: Delete SSH key by name

- **GIVEN** SSH key files `mobile-key` and `mobile-key.pub` exist in the
  configured SSH directory
- **WHEN** the GUI-facing delete SSH key API is called with name `mobile-key`
- **THEN** both files are removed
- **AND** subsequent SSH key listings do not include `mobile-key`

#### Scenario: Missing SSH key deletion reports an error

- **GIVEN** no SSH key files exist for name `missing-key`
- **WHEN** the GUI-facing delete SSH key API is called with name `missing-key`
- **THEN** the API returns a key-management error
