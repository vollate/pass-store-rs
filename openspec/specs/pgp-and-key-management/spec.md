# pgp-and-key-management Specification

## Purpose

Document implemented PGP backend, `.gpg-id`, PGP key, SSH key, and key import
behavior.

## Requirements

### Requirement: CLI PGP client SHALL resolve key metadata through GPG

The CLI-oriented `PGPClient` SHALL resolve fingerprints, usernames, and emails
by invoking the configured PGP executable with `--list-keys --with-colons` for
each configured identity.

Sources: `core/src/pgp/utils.rs`, `core/src/pgp/mod.rs`,
`cli/src/command/init.rs`

#### Scenario: Init displays resolved key user information

- WHEN `pars init` receives GPG IDs
- THEN it creates a temporary PGP client
- AND uses resolved usernames and emails in the init message

### Requirement: PGP backend config SHALL support system, bundled, and pure-rust selections

The config schema SHALL store `pgp_config.backend` with supported values
`system_gpg`, `bundled`, and `pure_rust`. Defaults SHALL select `system_gpg`.
Bundled backend SHALL require `bundled_gpg_path`; system backend SHALL use
`system_gpg_path` when present or default to `gpg2`.

Sources: `core/src/config/cli.rs`, `core/src/pgp/backend.rs`,
`core/tests/pgp_backend_test.rs`, `config/cli/pars_config.toml`

#### Scenario: Default config selects system GPG

- WHEN `ParsConfig::default()` is created
- THEN `pgp_config.backend` is `SystemGpg`

#### Scenario: Bundled backend selects bundled path

- GIVEN backend is `bundled`
- AND `bundled_gpg_path` is configured
- WHEN a `SystemGpgBackend` is created from config
- THEN its executable is the bundled path

### Requirement: Pure Rust backend SHALL maintain file-based keyrings and support entry crypto

The pure Rust backend SHALL require `keyring_home`, create public/private
keyring directories, generate OpenPGP keys, import/export public and private
keys, list keys, validate recipients, encrypt entry content, and decrypt entry
content.

Sources: `core/src/pgp/rpgp_backend.rs`, `core/src/gui/mod.rs`,
`bridge/tests/bridge_smoke_test.rs`, `core/tests/rpgp_gnupg_interop_test.rs`

#### Scenario: Pure Rust bridge encrypts and decrypts an entry

- GIVEN config selects `pure_rust`
- AND the store `.gpg-id` contains a generated pure-rust key fingerprint
- WHEN bridge insert writes an entry
- AND bridge read reads that entry
- THEN the parsed password and fields match the inserted plaintext

### Requirement: `.gpg-id` recipient lookup SHALL prefer nearest ancestor file

Recipient lookup SHALL search from the target path toward the store root and
return the nearest `.gpg-id` file's non-empty lines.

Sources: `core/src/util/fs_util.rs`, `core/src/pgp/backend.rs`,
`core/tests/pgp_backend_test.rs`

#### Scenario: Subdirectory `.gpg-id` overrides root `.gpg-id`

- GIVEN root `.gpg-id` contains `alice@example.com`
- AND `work/.gpg-id` contains `team@example.com`
- WHEN recipients are validated for `work/github.gpg`
- THEN `team@example.com` is returned

#### Scenario: Empty backend recipient list is invalid

- GIVEN the nearest `.gpg-id` contains only comments or blank lines
- WHEN backend validation runs
- THEN it returns an invalid `.gpg-id` error

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

### Requirement: GUI-facing PGP key management SHALL delete local PGP keys

The GUI-facing key-management API SHALL support deleting a local PGP key by
fingerprint through the configured PGP backend. Deletion SHALL remove local
public key material and local private key material for that fingerprint when
present, and SHALL report an error when the key cannot be found or cannot be
deleted.

Sources: `core/src/pgp/backend.rs`, `core/src/pgp/rpgp_backend.rs`,
`bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete PGP key by fingerprint

- GIVEN a PGP key exists in the configured backend
- WHEN the GUI-facing delete PGP key API is called with that fingerprint
- THEN the key is removed from subsequent key listings
- AND local private key material for that fingerprint is removed when it exists

#### Scenario: Missing PGP key deletion reports an error

- GIVEN no local PGP key matches fingerprint `ABC`
- WHEN the GUI-facing delete PGP key API is called with fingerprint `ABC`
- THEN the API returns a key-management error

### Requirement: SSH key management SHALL operate without external ssh-keygen for generated ed25519 keys

The core key management layer SHALL generate OpenSSH ed25519 keys directly,
write private keys with private permissions on Unix, write `.pub` public keys,
compute `SHA256:` fingerprints, list `.pub` keys, import unencrypted OpenSSH
ed25519 private keys, and export public/private SSH keys.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`, `gui/lib/services/key_repository.dart`

#### Scenario: Generated SSH key creates private and public files

- WHEN an SSH ed25519 key named `mobile-key` is generated
- THEN `<ssh_dir>/mobile-key` exists
- AND `<ssh_dir>/mobile-key.pub` exists
- AND the fingerprint starts with `SHA256:`

#### Scenario: Private SSH export requires confirmation

- GIVEN key name `github-mobile`
- WHEN private SSH export is requested
- THEN confirmation must equal `EXPORT PRIVATE KEY github-mobile`

### Requirement: GUI-facing SSH key management SHALL delete local SSH keys

The GUI-facing key-management API SHALL support deleting a local SSH key by key
name from the configured SSH directory. Deletion SHALL remove both the private
key file and matching `.pub` public key file when present, and SHALL report an
error when neither file exists.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete SSH key by name

- GIVEN SSH key files `mobile-key` and `mobile-key.pub` exist in the configured
  SSH directory
- WHEN the GUI-facing delete SSH key API is called with name `mobile-key`
- THEN both files are removed
- AND subsequent SSH key listings do not include `mobile-key`

#### Scenario: Missing SSH key deletion reports an error

- GIVEN no SSH key files exist for name `missing-key`
- WHEN the GUI-facing delete SSH key API is called with name `missing-key`
- THEN the API returns a key-management error

### Requirement: Key material detection SHALL classify supported pasted keys

Key material detection SHALL recognize PGP public keys, PGP private keys, and
SSH private keys by supported BEGIN/END markers and SHALL reject unsupported
text without echoing invalid private key text in the error.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`

#### Scenario: PGP public text is classified

- GIVEN text with `BEGIN PGP PUBLIC KEY BLOCK` and matching end marker
- WHEN detection runs
- THEN the result is `pgp_public`

#### Scenario: Invalid private key text is not echoed

- GIVEN incomplete private key text
- WHEN detection rejects it
- THEN the error string does not include the invalid private text

### Requirement: Selected PGP keys SHALL be appended to root `.gpg-id` once

Adding a PGP key to the selected store SHALL create the store root if needed,
append the normalized fingerprint to root `.gpg-id`, preserve an existing final
line, and avoid duplicate entries.

Sources: `core/src/key_management.rs`, `core/tests/key_management_test.rs`,
`bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`

#### Scenario: Duplicate selected key is not appended twice

- GIVEN `.gpg-id` already contains a fingerprint
- WHEN the same fingerprint is added twice
- THEN `.gpg-id` contains one copy of that fingerprint

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

## Needs Verification

- CLI recipient lookup does not filter comment lines before constructing
  `PGPClient`, while backend validation does. Intended `.gpg-id` comment support
  across CLI and GUI needs verification.
- Pure Rust backend accepts passphrases during key generation, but decryption
  currently attempts empty-password secret-key decryption. Encrypted private-key
  behavior needs verification.
