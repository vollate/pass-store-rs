## ADDED Requirements

### Requirement: Pure Rust private-key import SHALL apply managed OpenPGP protection

The pure-Rust backend SHALL validate every protected secret packet with the
single supplied passphrase and SHALL replace each protected packet that does not
satisfy the accepted local protection policy with the version-appropriate
managed OpenPGP protection profile before committing the private key. The
managed profile SHALL preserve the same passphrase, canonical primary
fingerprint, public material, certifications, subkeys, and capabilities. The
backend SHALL NOT persist an unprotected intermediate key or reduce protection
parameters in response to the runtime cost of a slow legacy hash
implementation.

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
- **AND** the stored protected packets use the managed v4 AES-256, SHA-256, and
  iterated-count profile with fresh per-packet randomness
- **AND** the canonical primary fingerprint is unchanged

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

### Requirement: Pure Rust private-key replacement SHALL be atomic and secret-safe

The pure-Rust backend SHALL serialize only the fully protected replacement into
a restrictive temporary file in the destination keyring directory and SHALL
atomically replace the fingerprint-addressed private-key record only after
preparation, verification, serialization, flush, and sync succeed. Failures
SHALL preserve an existing record and SHALL remove temporary artifacts. Errors
and logs SHALL NOT contain a passphrase, source private-key bytes, plaintext
secret parameters, derived key, or serialized private material.

#### Scenario: Re-import failure preserves existing key

- **GIVEN** a private-key record already exists for fingerprint `ABC`
- **WHEN** re-import fails during packet preparation, serialization, or atomic
  replacement
- **THEN** the previously stored record for `ABC` remains byte-for-byte usable
- **AND** no unprotected or temporary private-key file remains

#### Scenario: Successful replacement never writes plaintext secret material

- **GIVEN** all protected packets have been unlocked in memory and rewritten
- **WHEN** the keyring commit succeeds
- **THEN** every private-key byte written to persistent storage belongs to the
  fully protected OpenPGP serialization
- **AND** transient plaintext secret parameters are dropped without crossing
  the bridge

### Requirement: Existing pure Rust private keys SHALL migrate after authorized unlock

The pure-Rust backend SHALL expose a fingerprint-bound preparation operation for
an existing private-key record. After the supplied passphrase successfully
validates every protected packet, the operation SHALL atomically migrate
noncompliant protection to the current managed profile before reporting
success. A compliant record SHALL be validated without unnecessary rewriting,
and a failed preparation SHALL leave the original record unchanged.

#### Scenario: Existing legacy key migrates once

- **GIVEN** fingerprint `ABC` identifies an existing pure-Rust private key with
  legacy iterated SHA-1 protection
- **WHEN** the user next authorizes `ABC` with the correct passphrase
- **THEN** the backend atomically rewrites its noncompliant protected packets
  using the managed profile
- **AND** subsequent preparations do not execute the legacy SHA-1 S2K again

#### Scenario: Failed legacy migration preserves the old record

- **GIVEN** fingerprint `ABC` identifies an existing legacy private-key record
- **WHEN** authorization or atomic migration fails
- **THEN** the old record remains available in its original form
- **AND** the operation does not report an active prepared session

#### Scenario: Compliant key is not rewritten

- **GIVEN** every protected packet for fingerprint `ABC` satisfies the accepted
  local policy
- **WHEN** the correct passphrase is prepared for a new session
- **THEN** the operation validates the key and returns success
- **AND** the private-key file is not replaced solely to refresh salts or
  timestamps

### Requirement: Pure Rust key deletion SHALL verifiably remove managed secret material

The pure-Rust backend SHALL delete a fingerprint's authoritative re-protected
private record before deleting its public listing record and SHALL verify that
the private path is absent before reporting the secret material removed. A
private-record deletion failure SHALL preserve the public record. Deletion SHALL
be serialized against import and migration for the same normalized fingerprint,
SHALL clean same-key preparation temporaries, and SHALL NOT modify password-store
`.gpg-id` files.

#### Scenario: Successful deletion removes the re-protected private record

- **GIVEN** fingerprint `ABC` has an authoritative managed private record and a
  public record
- **WHEN** the backend deletes `ABC`
- **THEN** the private record and its same-key preparation temporaries are absent
- **AND** the public record is absent
- **AND** no retained source or plaintext private-key copy exists

#### Scenario: Private deletion failure keeps the key visible

- **GIVEN** fingerprint `ABC` has private and public records
- **WHEN** removal of the private record fails
- **THEN** deletion returns failure with private material not confirmed absent
- **AND** the public record remains available for listing and retry

#### Scenario: Public cleanup failure reports that private material is gone

- **GIVEN** removal of the private record for `ABC` succeeds
- **WHEN** removal of its public record fails
- **THEN** deletion reports a partial result confirming the private record is
  absent and public cleanup failed
- **AND** subsequent private export cannot find `ABC`

#### Scenario: Local deletion preserves password-store recipient references

- **GIVEN** one or more selected stores reference fingerprint `ABC` in `.gpg-id`
- **WHEN** local key `ABC` is deleted
- **THEN** every `.gpg-id` remains byte-for-byte unchanged
- **AND** the GUI may represent `ABC` as referenced but missing locally
