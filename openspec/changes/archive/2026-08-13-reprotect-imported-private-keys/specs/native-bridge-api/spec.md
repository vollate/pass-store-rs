## ADDED Requirements

### Requirement: Bridge private-key preparation SHALL be transactional and sanitized

The bridge SHALL make pure-Rust private-key re-protection part of protected
private import and SHALL expose a fingerprint-bound operation for preparing an
existing private key before a PGP session starts. Success SHALL be returned only
after the protected keyring record is committed or confirmed compliant.
Failures SHALL distinguish missing/incorrect passphrase, unsupported packet
protection, and local re-protection or commit failure without returning secret
input.

#### Scenario: Protected import responds after re-protection commit

- **GIVEN** protected private-key material and its correct passphrase are sent
  through the typed import API for the pure-Rust backend
- **WHEN** the source packets require managed re-protection
- **THEN** the bridge returns the imported key record only after the protected
  replacement has been committed
- **AND** the response contains no passphrase, private-key bytes, or derived
  material

#### Scenario: Existing-key preparation is fingerprint-bound

- **GIVEN** private keys `ABC` and `DEF` exist in the pure-Rust keyring
- **WHEN** the bridge preparation operation receives fingerprint `DEF` and its
  passphrase
- **THEN** it validates and, when necessary, migrates only key `DEF`
- **AND** it returns the backend-confirmed fingerprint `DEF`

#### Scenario: Re-protection failure is typed and sanitized

- **GIVEN** a pure-Rust private import or existing-key preparation cannot safely
  re-protect all required packets
- **WHEN** the bridge maps the core failure
- **THEN** the response contains a stable typed failure kind suitable for
  localized Flutter messaging
- **AND** its message contains neither the passphrase nor private-key material

#### Scenario: System GPG retains native key management

- **GIVEN** the selected backend is system GPG or bundled GPG
- **WHEN** protected private-key import succeeds
- **THEN** the bridge does not rewrite the material using the pure-Rust managed
  profile
- **AND** the configured GPG implementation remains responsible for its local
  private-key protection

### Requirement: Bridge PGP deletion SHALL report verified secret-material state

The bridge PGP deletion operation SHALL return a structured result containing
the backend-confirmed fingerprint, whether private material existed, whether
the private record is confirmed absent, and whether the public record is
confirmed absent. It SHALL distinguish a total deletion failure from a partial
result where private material is gone but public-record cleanup failed, without
requiring or returning the private-key passphrase.

#### Scenario: Complete deletion returns confirmed absence

- **GIVEN** a local PGP key has public and managed private records
- **WHEN** deletion removes both records
- **THEN** the bridge returns the canonical fingerprint with private and public
  absence confirmed
- **AND** it returns no deletion error

#### Scenario: Private deletion failure is not reported as success

- **GIVEN** the backend cannot remove a local managed private record
- **WHEN** the bridge maps the deletion outcome
- **THEN** it returns a typed PGP deletion failure
- **AND** it does not claim that private material is absent

#### Scenario: Public cleanup failure preserves the private-absent result

- **GIVEN** the backend has removed and verified absence of the private record
- **WHEN** its public-record removal fails
- **THEN** the bridge returns a result with private absence confirmed and public
  absence unconfirmed
- **AND** it returns a typed public-cleanup error suitable for localized GUI
  messaging
