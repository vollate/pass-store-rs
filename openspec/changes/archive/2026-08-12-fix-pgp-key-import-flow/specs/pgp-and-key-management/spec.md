## MODIFIED Requirements

### Requirement: Bridge PGP key management SHALL generate, import, list, and export keys

The bridge SHALL expose methods to list keys, generate PGP keys, inspect and
import public or private PGP keys from text or file sources, export public PGP
keys, and export private PGP keys. Inspection and import SHALL derive the key
kind and canonical primary-key fingerprint from supported key material rather
than inferring kind from the selected source. Protected private-key material
SHALL be passphrase-validated against the exact import material before the
configured backend is mutated. Private PGP key export SHALL still identify the
target key by fingerprint, but its confirmation phrase SHALL be derived from
the human-readable key identity returned by key listing rather than the
fingerprint.

Sources: `bridge/src/api.rs`, `core/src/pgp/backend.rs`,
`bridge/tests/bridge_smoke_test.rs`, `gui/lib/services/key_repository.dart`

#### Scenario: Private PGP export requires human-readable confirmation

- GIVEN a PGP key with fingerprint `ABC` and identity `Alice`
- WHEN private PGP export is requested for fingerprint `ABC`
- THEN confirmation must equal `EXPORT PRIVATE KEY Alice`
- OTHERWISE the bridge returns a validation error that includes the expected
  phrase

#### Scenario: Private PGP export targets the selected fingerprint

- GIVEN two PGP keys share the display identity `Alice`
- WHEN private PGP export is requested for one key's fingerprint with
  confirmation `EXPORT PRIVATE KEY Alice`
- THEN the bridge exports private key material only for the requested
  fingerprint

#### Scenario: Import type must match requested PGP import

- GIVEN imported key material is detected as PGP public or private
- WHEN a legacy type-specific import method requests a kind that does not match
  the detected material
- THEN the bridge returns a validation error

#### Scenario: Text and file sources detect key kind independently

- GIVEN supported PGP public or private key material is supplied as pasted
  armored text, an armored file, or a binary OpenPGP file
- WHEN PGP import inspection runs
- THEN it returns the material's public/private kind
- AND the result does not derive key kind from whether Text or File was selected

#### Scenario: Import returns a canonical fingerprint

- GIVEN supported PGP key material has canonical primary fingerprint `ABC`
- WHEN the key is imported into system GPG or the pure-Rust backend
- THEN the bridge returns fingerprint `ABC` with backend-confirmed key metadata
- AND it returns the same fingerprint when the key already exists

#### Scenario: Incorrect protected-key passphrase does not mutate the keyring

- GIVEN private PGP import material is protected by a passphrase
- WHEN import receives no passphrase or an incorrect passphrase
- THEN the bridge returns a typed passphrase validation failure
- AND the configured keyring does not contain a newly imported key
- AND the error does not contain the passphrase or private key material

#### Scenario: Correct protected-key passphrase completes import

- GIVEN private PGP import material with fingerprint `ABC` is protected by a
  passphrase
- WHEN import receives the correct passphrase
- THEN the bridge validates the encryption-capable private material
- AND imports the key
- AND returns fingerprint `ABC`

#### Scenario: Unprotected private key imports without a passphrase

- GIVEN supported private PGP import material is not passphrase-protected
- WHEN it is imported without a passphrase
- THEN import succeeds and returns its canonical fingerprint
