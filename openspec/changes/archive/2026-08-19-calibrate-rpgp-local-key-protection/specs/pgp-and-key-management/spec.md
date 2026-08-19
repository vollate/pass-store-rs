## MODIFIED Requirements

### Requirement: Pure Rust private-key import SHALL apply managed OpenPGP protection

The pure-Rust backend SHALL validate every protected secret packet with the
single supplied passphrase and SHALL replace each protected packet that does not
satisfy the accepted local protection policy with the version-appropriate
managed OpenPGP protection profile before committing the private key. The
managed profile SHALL preserve the same passphrase, canonical primary
fingerprint, public material, certifications, subkeys, and capabilities.

The managed v4 profile SHALL use AES-256 CFB and iterated-and-salted SHA-256
with fresh per-packet randomness. Its RFC-encoded iteration count SHALL be
selected by a bounded, versioned local calibration policy targeting 100 ms for
one optimized local derivation, with a decoded-count floor of 1 MiB and ceiling
of 16 MiB. The managed v6 profile SHALL retain the existing AES-256 OCB and
Argon2id policy. Calibration SHALL NOT use legacy SHA-1 or `sha1-checked`
performance to lower the normal local v4 profile.

The rewritten private-key file SHALL remain passphrase-protected standard
OpenPGP material. Re-protection SHALL replace the imported representation as the
single authoritative local private-key record and SHALL NOT create a plaintext
private-key file, durable unlocked-key cache, derived-key cache, or retained
source copy. Normal unlock and password-entry decryption SHALL continue to
require the same passphrase under the existing session policy, and private-key
export SHALL remain protected so its secret parameters require that passphrase
for use.

#### Scenario: Legacy protected v4 key is re-protected during import

- **GIVEN** a v4 private key has one or more protected secret packets using
  iterated SHA-1, including a maximum encoded count
- **WHEN** the key is imported into the pure-Rust backend with the single
  passphrase that unlocks every protected packet
- **THEN** import pays the source protection cost once per protected packet
- **AND** the stored protected packets use the calibrated managed v4 AES-256,
  SHA-256, and iterated-count profile with fresh per-packet randomness
- **AND** the canonical primary fingerprint is unchanged

#### Scenario: Re-protection failure rejects the entire import

- **GIVEN** protected private-key material has been supplied for import
- **WHEN** local policy calibration, re-protection, binding or fingerprint
  verification, or atomic private-record commit fails
- **THEN** the import returns failure
- **AND** no new private or public key record is committed
- **AND** the backend does not retain the source-protected packet as a fallback
- **AND** no PGP session is started for the uncommitted key

#### Scenario: Local v4 count is calibrated and reused

- **GIVEN** a pure-Rust keyring has no valid policy-v2 calibration metadata
- **WHEN** the first protected v4 key is generated, imported, or prepared
- **THEN** the backend calibrates an RFC-encoded count through the optimized
  SHA-256 local S2K path within the configured floor and ceiling
- **AND** persists the non-secret policy result atomically
- **AND** later operations reuse that count without recalibrating on each entry
  read

#### Scenario: Protected generation avoids default-profile rework

- **GIVEN** a user generates a passphrase-protected v4 key
- **WHEN** pure-Rust key generation completes
- **THEN** every required secret packet is protected directly with the current
  calibrated managed profile before persistent serialization
- **AND** generation does not first persist or re-unlock an rPGP-default
  protected record

#### Scenario: Existing fixed-profile key migrates when locally too expensive

- **GIVEN** an existing v4 private record uses the former coded-224 managed
  profile
- **AND** policy-v2 calibration selected a different encoded count
- **WHEN** the user successfully authorizes that fingerprint
- **THEN** the backend atomically re-protects the record with the calibrated
  count
- **AND** subsequent authorization does not repeat the coded-224 derivation

#### Scenario: Existing-key migration failure rejects preparation

- **GIVEN** an already installed private key requires policy-v2 migration
- **WHEN** authorized migration or atomic replacement fails
- **THEN** the preparation request returns failure and no PGP session starts
- **AND** the previously installed private record remains available unchanged
  for a later retry

#### Scenario: Managed v6 key uses Argon2 and AEAD

- **GIVEN** a protected v6 private key is imported into the pure-Rust backend
- **WHEN** its protected packets are prepared for local storage
- **THEN** every rewritten protected packet uses the managed AES-256 OCB and
  Argon2id profile with fresh per-packet randomness
- **AND** it remains unlockable with the supplied passphrase

#### Scenario: Different packet passphrases do not partially import

- **GIVEN** an imported private key contains protected secret packets that
  cannot all be unlocked by the single supplied passphrase
- **WHEN** pure-Rust import prepares the key
- **THEN** import returns a sanitized unsupported-protection or passphrase
  failure
- **AND** it does not create or replace the private-key record

#### Scenario: Unprotected input is not silently assigned a passphrase

- **GIVEN** imported private-key material has no protected secret packets
- **WHEN** it is imported without a passphrase
- **THEN** the current unprotected-import behavior is preserved
- **AND** the backend does not invent or persist an undisclosed password

#### Scenario: Re-protected export remains interoperable

- **GIVEN** a private key was re-protected by the pure-Rust backend
- **WHEN** it is exported by fingerprint
- **THEN** the export is standard OpenPGP private-key material
- **AND** another supported OpenPGP implementation can import it with the same
  passphrase
- **AND** the exported public fingerprint equals the pre-import fingerprint

#### Scenario: Re-protection does not remove the password requirement

- **GIVEN** a protected private key has been re-protected for local storage
- **WHEN** a caller attempts to unlock the stored key or use exported private
  material without the passphrase or with an incorrect passphrase
- **THEN** the operation fails without exposing private material
- **AND** the original passphrase successfully unlocks the authoritative record

## ADDED Requirements

### Requirement: Pure Rust managed private-key unlock SHALL meet the entry-decryption performance budget

The pure-Rust backend SHALL provide stage-separated, secret-safe release
benchmark evidence for managed-key entry decryption. On the reference Android
device, after any one-time source unlock or policy migration has completed, the
p95 wall time for decrypting a password-store entry with a policy-compliant
private key SHALL be less than 800 milliseconds.

#### Scenario: Subsequent managed-key decrypt meets target

- **GIVEN** the reference Android device is running a release-built Pars native
  library
- **AND** the target encryption packet matches the current calibrated local
  policy
- **WHEN** the benchmark decrypts the same representative entry repeatedly
  after one-time preparation
- **THEN** subsequent decrypt p95 is less than 800 milliseconds
- **AND** the result excludes the separately reported legacy source migration
  duration

#### Scenario: Benchmark identifies expensive stage without exposing secrets

- **WHEN** managed-key preparation and entry decryption are benchmarked
- **THEN** timings distinguish key/message I/O and parsing, S2K/private-packet
  unlock, PKESK recovery, and payload decryption
- **AND** benchmark output contains no passphrase, private parameters, derived
  key, plaintext entry, or raw private-key material

#### Scenario: Subsequent decrypt avoids legacy SHA-1

- **GIVEN** a legacy SHA-1 protected key has been successfully migrated
- **WHEN** a later managed-key preparation or entry decryption runs
- **THEN** it does not execute the legacy `sha1-checked` S2K path
- **AND** optimizing that one-time compatibility implementation is not required
  to meet the subsequent-decryption target
