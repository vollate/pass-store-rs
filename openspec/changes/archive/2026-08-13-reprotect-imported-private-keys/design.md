## Context

The pure-Rust keyring currently writes `SignedSecretKey` material back to
`private/<fingerprint>.asc` without changing the protection on its secret-key
packets. Entry decryption parses that file and asks rPGP to unlock the matching
private material with the active Flutter PGP-session passphrase. Consequently,
an imported v4 key whose encryption subkey uses maximum-count iterated SHA-1
repeats the source key's expensive S2K whenever a new session reads an entry.

Profiling the Android release build showed that this is not a recipient scan or
entry-size problem: the hot path is rPGP's legacy S2K feeding roughly 62 MiB per
SHA-1 context into `sha1-checked`. The source S2K is legitimate and must be paid
at least once to import the private material, but it does not need to remain the
application's at-rest protection forever.

The current import pipeline already parses the exact material, identifies its
canonical fingerprint, accepts a passphrase, and rejects a bad passphrase before
backend mutation. Flutter separately owns the active passphrase session,
expiration, and optional Keychain/KMS persistence. The design must preserve that
separation: changing at-rest encoding must not silently lengthen authorization or
introduce an immortal unlocked-key cache.

## Goals / Non-Goals

**Goals:**

- Pay a source key's legacy S2K cost once during import or one-time migration,
  then use a documented local OpenPGP protection profile for normal sessions.
- Keep the stored and exported key valid OpenPGP material with the same primary
  fingerprint, public packets, identities, certifications, subkeys, and
  capabilities.
- Keep exactly one authoritative local private record after conversion and
  require the same passphrase for normal unlock and decryption while keeping
  exported private material protected; conversion is at-rest performance
  normalization, not decryption or caching.
- Re-protect using the same user passphrase so the existing session and optional
  secure-storage policy remain valid.
- Validate and transform protected secret packets without performing the same
  expensive source S2K twice.
- Commit private-key changes atomically and never write an unprotected
  intermediate key to disk.
- Migrate existing pure-Rust keyring records after their next successful,
  fingerprint-bound authorization.
- Give the UI a typed, localized success/failure boundary without introducing a
  different sheet style or a second import flow.
- Make GUI deletion prove that the authoritative re-protected private record is
  absent, clear its matching authorization state, and accurately report partial
  public-record cleanup failure.

**Non-Goals:**

- Patch, fork, disable, or replace `sha1-checked` in this change. That remains a
  separately benchmarked optional optimization for the compatibility path.
- Cache a decrypted private key or derived key beyond the configured PGP session
  expiration, or change any expiration duration.
- Change system-GPG storage; GnuPG already converts imported transfer keys into
  its agent-managed format.
- Invent an application-only private-key container, change `.gpg-id`, or change
  password-store entry encryption.
- Require a new passphrase when importing an unprotected private key. Such keys
  retain the current unprotected-import behavior.
- Optimize unrelated PGP message parsing, recipient selection, signing, or Git
  behavior.
- Require the private-key passphrase merely to delete its encrypted file; the
  existing human-readable typed confirmation remains the deletion gate.
- Rewrite password-store `.gpg-id` files when local key material is deleted.

## Decisions

### Store re-protected standard OpenPGP packets, not a custom envelope

The pure-Rust backend will decrypt protected secret parameters in memory and
re-encrypt those parameters using standard OpenPGP S2K usage fields. Protection
changes do not alter public key material, so the primary fingerprint and all
existing signatures remain stable. Export can continue returning the stored
OpenPGP key, and the same passphrase can import it into GnuPG or another
compatible implementation.

A custom Argon2-plus-AEAD application envelope was rejected because it would
require a second file format, custom migration/version parsing, and an export
conversion step. Persisting an unprotected OpenPGP key behind a platform-only
key was also rejected because it would couple backend authorization to
Keychain/KMS availability and could bypass the configured PGP session policy.

The normalized `private/<fingerprint>.asc` replaces the imported representation
as the sole authoritative private record. No original protected copy, plaintext
copy, unlocked-key file, or durable derived-key cache is retained. The speedup
comes only from using managed OpenPGP protection parameters on subsequent
password-based unlocks; the same password remains cryptographically required.

### Freeze a version-aware local protection policy

The current local policy will be constructed explicitly rather than calling an
rPGP default whose meaning could change after a dependency upgrade:

- v4 secret packets: S2K usage 254, AES-256 CFB, iterated-and-salted SHA-256,
  coded count 224 (16,777,216 hashed octets), and a fresh salt and IV per packet.
- v6 secret packets: S2K usage 253, AES-256 OCB, Argon2id with `t=3`, `p=4`, and
  `m_enc=16` (64 MiB), and a fresh salt and nonce per packet.

These are the rPGP 0.20 version-specific defaults, but they become application
policy constants with tests. The policy SHALL NOT derive a lower security
parameter merely because a slow implementation makes a benchmark reach a time
target early. In particular, calibrating legacy SHA-1 through `sha1-checked`
would create a weak count for attackers using optimized SHA-1 and is rejected.

An already protected packet may be retained only when it satisfies the current
accepted-policy predicate and does not use a legacy MD5, SHA-1, or RIPEMD-160
S2K. Noncompliant protected packets are rewritten to the applicable profile.
Unprotected packets remain unprotected; the import flow does not invent a
password the user did not supply.

Using Argon2 AEAD for v4 packets was rejected for this change because older
OpenPGP implementations have uneven support. The conservative v4
AES-256/SHA-256 profile preserves broad import/export compatibility while
removing the `sha1-checked` hot path from subsequent unlocks.

### Fuse passphrase validation with re-protection

The current common importer calls `validate_passphrase` and then asks the
backend to store the parsed key. If pure-Rust re-protection independently calls
`remove_password`, a maximum-count packet would be unlocked twice. Instead, the
pure-Rust preparation path will consume or own a mutable parsed private key and
perform one pass over its secret packets:

1. For each encrypted primary key or subkey, call the rPGP unlock/remove-password
   operation exactly once with the supplied password.
2. Treat any failure as a typed incorrect-passphrase or unsupported-protection
   result and discard the prepared key before touching the keyring.
3. Re-encrypt each noncompliant packet with fresh randomness and the same
   password; retain acceptable protected packets only after their password was
   validated.
4. Verify bindings and assert that the canonical primary fingerprint is
   unchanged before serialization.

This requires adjusting backend import plumbing so the pure-Rust backend can
own preparation instead of receiving a reference after an earlier validation.
System GPG retains exact-material validation followed by its existing import.
The API must not expose the prepared or plaintext secret parameters.

One supplied passphrase must unlock every protected secret packet being
imported. Keys whose packets deliberately use different passwords are rejected
atomically with a sanitized unsupported-protection failure; partially rewriting
such a key would leave surprising and difficult-to-export state.

### Atomically replace only fully protected serialized material

The backend will serialize the fully re-protected key into a secret buffer,
create a restrictive temporary file in the destination private-key directory,
flush and sync it, and atomically rename it over
`private/<fingerprint>.asc`. The public record may be staged separately because
it contains no secret material, but an existing private record must remain
untouched until the replacement is complete. Temporary files are removed on
failure, and serialized buffers are zeroized where the involved types allow it.

No plaintext secret-key serialization is written to a file, log, bridge DTO,
or Flutter value. Errors may include a fingerprint or destination path but not
the passphrase, source key bytes, decrypted parameters, salt, or derived key.

For a duplicate import, preparation and verification finish before replacing
the existing record. A failed re-import therefore preserves the previously
usable key.

### Migrate existing records at the authorization boundary

Import-time re-protection fixes new records but not keys already stored by the
current release. Add a fingerprint-bound core/bridge preparation operation that
parses the existing private record, checks its packet protection against the
accepted-policy predicate, validates the supplied passphrase, and atomically
rewrites it when needed.

Flutter orchestration invokes this operation before reporting that a manually
entered or securely restored passphrase has started a PGP session for an
existing key. A compliant record is validated without rewriting. A legacy
record pays its old S2K cost once; after commit, later decrypts use the local
profile. A migration error leaves both the old key file and the prior session
state unchanged.

The security repository remains the authority for the in-memory passphrase and
its expiration. The Rust bridge does not retain the passphrase or an unlocked
key after the preparation call. Entry reads continue to receive the active
passphrase through the existing request path, now against the re-protected key.

Migration is lazy rather than an unattended startup job because the passphrase
is required and background prompting would violate the security flow. A bulk
automatic migration was rejected for the same reason.

### Keep import UI structure and localize the new state

The shared Settings/Onboarding import body remains the only import surface.
While Rust performs original unlock and re-protection, the existing submit
action remains pending and cannot be submitted twice. A protected import is
reported successful and starts its key-bound session only after the private
record commit succeeds.

Migration/re-protection failures use typed bridge kinds mapped to localized
messages through the existing Flutter i18n resources. No hard-coded English
strings, bespoke bottom sheet, or new visual language is introduced. Detailed
diagnostics stay sanitized and may be logged only at the non-secret stage level.

### Delete the authoritative private record before hiding the key

Pure-Rust deletion resolves the normalized fingerprint and checks the public and
private record paths. If a private record exists, deletion removes it first and
verifies that the path is absent before attempting to remove the public record.
This ordering prevents a failed private-file deletion from producing an
unlisted secret file that the user cannot reach from the GUI. Temporary files
owned by interrupted preparation for the same fingerprint are also removed or
reported as a deletion failure; deletion and preparation use the same per-key
synchronization boundary so they cannot recreate one another's files.

The backend returns a structured deletion result rather than unit success. It
records whether private material existed and whether the private and public
records are confirmed absent. If private deletion fails, the public record is
left in place and the GUI reports failure without clearing the associated
session or stored password. If private deletion succeeds but public cleanup
fails, the bridge returns both the verified private-absent result and a typed
cleanup error. Flutter then clears the matching active session and securely
stored passphrase, refreshes the list, and shows a localized partial-success
message. A fully successful delete performs the same security-state cleanup.

Deletion continues to require human-readable typed confirmation but not the PGP
passphrase: removing an encrypted file does not require decrypting it. For a PGP
User ID rendered as `Display Name <email>`, the confirmation value is only
`Display Name`; making the user reproduce the informational email address adds
friction without improving fingerprint-bound deletion safety. Identities that
do not have that trailing email form retain their displayed name as the
confirmation value, and SSH behavior is unchanged. The established Material
dialog is made scrollable so its confirmation field and actions stay reachable
when the software keyboard reduces the available height. Password-store `.gpg-id`
references are deliberately preserved; after refresh they remain visible as
references whose local key material is missing.

### Measure the result without making `sha1-checked` part of this change

Correctness tests inspect the persisted packet parameters and prove that a
second unlock no longer enters a legacy SHA-1 S2K. Interoperability tests export
the rewritten key and use GnuPG to import it and decrypt a fixture. Atomicity
tests inject preparation, serialization, and rename failures.

An Android release benchmark records the one-time legacy import/migration time
separately from subsequent session preparation and entry decryption. Timing is
reported for the reference device rather than enforced as a flaky universal CI
threshold. A later `sha1-checked` proposal may optimize the one-time legacy
path, but must preserve standard S2K output and be independently profiled.

## Risks / Trade-offs

- **The first import or migration can still take a long time** → Show one
  localized pending operation, fuse validation and transformation so each
  protected source packet is unlocked only once, and make subsequent work
  deterministic from stored parameters.
- **Re-protection changes the byte representation returned by private export** →
  Preserve public material, fingerprint, and password; add rPGP/GnuPG round-trip
  interoperability tests. Document that protection packets are normalized.
- **A key may use different passwords for different secret packets** → Reject it
  before mutation with a typed sanitized error instead of storing a partially
  migrated key.
- **A crash during replacement could damage a key** → Stage in the same
  directory, set restrictive permissions, sync, and rename atomically while
  retaining the previous file until the final operation.
- **The local policy may need strengthening later** → Keep construction and
  policy detection centralized and versioned in code so another lazy migration
  can be introduced without changing fingerprints or the keyring layout.
- **Repeated entry reads still derive the local S2K** → Accept the bounded local
  cost in this change; do not introduce a decrypted-key cache until its lifetime
  can be tied rigorously to the existing expiration policy.
- **Public cleanup can fail after the private file is gone** → Return a
  structured partial result, clear matching authorization because the secret is
  already absent, refresh the UI, and expose a localized cleanup warning rather
  than claiming an all-or-nothing failure.
- **Deletion can race migration/import** → Serialize mutations per normalized
  fingerprint and verify path absence before reporting the deletion outcome.
- **Older app versions may see rewritten keys** → Use standard OpenPGP v4/v6
  encodings already understood by the pinned backend and cover downgrade parsing
  in tests where supported.

## Migration Plan

1. Add policy construction, policy inspection, all-packet one-pass preparation,
   and atomic private-record replacement behind pure-Rust core tests.
2. Change import plumbing so pure-Rust preparation replaces the separate
   validate-then-store sequence, without changing system-GPG behavior.
3. Add the existing-record preparation bridge method and typed sanitized
   failures; regenerate bindings and update secret-field coverage.
4. Integrate preparation into import/session orchestration and localized UI
   feedback without changing configured expiration or durable-cache defaults.
5. Change key deletion to private-first verified removal, return a structured
   result through the bridge, and integrate localized GUI/security cleanup.
6. Run core/bridge/Flutter tests, GnuPG interoperability tests, strict OpenSpec
   validation, and the Android release before/after benchmark.

Rollback may stop creating newly normalized records, but must continue reading
the standard OpenPGP files already written. Because fingerprints and file names
do not change, no reverse data migration is required.

## Open Questions

None. Changes to the local protection parameters or to SHA-1 implementation
selection require a separate reviewed proposal rather than an implementation
shortcut in this change.
