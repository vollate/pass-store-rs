## MODIFIED Requirements

### Requirement: Bridge PGP key management SHALL generate, import, list, and export keys

The bridge SHALL expose methods to list keys, generate PGP keys, import public
PGP keys, import private PGP keys from text or file, export public PGP keys, and
export private PGP keys. Private PGP key export SHALL still identify the target
key by fingerprint, but its confirmation phrase SHALL be derived from the
human-readable key identity returned by key listing rather than the fingerprint.

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

- GIVEN pasted key material is detected as PGP public or private
- WHEN the requested import kind does not match the detected material
- THEN the bridge returns a validation error
