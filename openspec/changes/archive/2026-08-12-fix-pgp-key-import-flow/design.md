## Context

The GUI currently has two different PGP import experiences. Settings routes an
Import action through a Text/File choice, but its File branch always calls the
private-key API; Onboarding only exposes pasted text. Both branches finish as
soon as the bridge reports success, so a protected private key is not unlocked,
bound to a PGP session, or offered for secure passphrase storage.

The bridge also models source and key kind together through separate public
text, private text, and private file methods. System GPG returns an empty
fingerprint from import, while the pure-Rust backend derives one. A correct
post-import security flow needs a canonical fingerprint on every backend.

This change crosses Rust key parsing, backend mutation, bridge DTOs, generated
Flutter bindings, GUI navigation, and the security repository. Private key
material and passphrases must be treated as secrets throughout.

## Goals / Non-Goals

**Goals:**

- Give Settings and Onboarding the same Text/File PGP import states and
  outcomes.
- Treat source (text or file) independently from detected key kind (public or
  private).
- Inspect supported armored text and supported armored or binary key files
  before mutating the selected keyring.
- Return and use one canonical imported fingerprint on every backend, including
  when the key already exists.
- Validate a protected private key's passphrase against the exact import
  material before import completes.
- Start a fingerprint-bound in-memory session after protected private-key
  import and persist the passphrase only through an explicit opt-in.
- Clear secret controllers and temporary buffers on success, cancellation, and
  failure, and keep secrets out of errors and logs.

**Non-Goals:**

- Change CLI commands, `.gpg-id` format, or password-store entry encryption.
- Prompt for a passphrase when importing a public key or an unprotected private
  key.
- Automatically persist passphrases or change the configured session timeout.
- Add SSH passphrase support or redesign unrelated key export/delete actions.
- Support malformed or OpenPGP formats that neither configured backend can
  safely inspect and import.

## Decisions

### Inspect first and import atomically

Model PGP import as a small state machine shared by the Settings and Onboarding
surfaces:

```text
choose Text/File -> load and inspect -> public/unprotected: import
                                  \-> protected private: enter passphrase
                                                        -> validate and import
                                                        -> session/optional cache
```

Inspection returns key kind, canonical fingerprint, display identity, private
key availability, and whether a passphrase is required. A protected private-key
import request carries the passphrase and validates it before writing to the
keyring. An absent or incorrect passphrase returns a typed validation failure
and leaves the keyring unchanged.

This is preferred to importing first and testing against an arbitrary vault
entry: it is deterministic, does not require a configured store, and avoids
leaving unusable imported keys after a typo. From the user's perspective the
passphrase step follows the initial Import action, but bridge mutation is only
committed when validation succeeds.

### Use byte-safe core inspection for both sources

Add a core PGP import inspection model that accepts key bytes. Pasted text is
converted to UTF-8 bytes, while a file is read as bytes in Rust so binary
OpenPGP exports are not forced through `read_to_string`. Inspection parses the
key packets to distinguish public/private material, calculate the primary
fingerprint, and detect whether usable private encryption material is
passphrase-protected.

Text and file bridge methods remain separate at the transport boundary because
one carries secret text and the other carries a local path, but both call the
same inspector and importer. The Flutter repository exposes one result model
and does not infer private keys with string matching.

The alternative of adding a file picker that reads the file into Dart was
rejected because it would place private key bytes in another runtime and make
secret cleanup harder.

### Validate the exact private material without relying on GPG agent state

Passphrase validation SHALL unlock the encryption-capable private key or subkey
from the inspected import material in memory. It must not infer correctness
from a cached GPG-agent unlock and must not require decrypting a password-store
entry. Temporary unlocked material is discarded immediately after validation.

This makes validation consistent for system GPG and pure-Rust keyrings. The
configured backend still performs the final import only after common inspection
and validation succeeds.

### Derive the fingerprint before mutation and verify it after import

The inspector's primary-key fingerprint is the expected canonical identity.
After backend import, the bridge inspects or lists that exact fingerprint and
builds the returned key record from backend-confirmed metadata. This works for
new and duplicate imports and removes the system-GPG empty-fingerprint result.

For system GPG, status output such as `IMPORT_OK` may be used as additional
evidence, but it is not the sole source because duplicate imports can produce a
different status sequence. For pure Rust, the stored record is resolved by the
same expected fingerprint.

### Add typed PGP inspection/import APIs while retaining legacy wrappers

Add PGP-specific text and file inspection/import DTOs rather than extending the
generic SSH-compatible import request. Import responses include the detected
kind and canonical `KeyRecordDto`; failures distinguish invalid material,
passphrase required, incorrect passphrase, and backend import errors without
including secret input.

Existing public/private import bridge functions can remain as compatibility
wrappers during the in-repository migration, but Settings and Onboarding use the
new source-independent methods. Generated FRB bindings and method-table tests
are refreshed in the same change.

### Keep session activation and durable caching in Flutter security policy

The bridge validates and imports the key; Flutter decides what happens to the
validated passphrase. After a protected private import succeeds, Flutter starts
`SecurityRepository.startPgpSession` with the returned fingerprint. A
`Remember in Keychain/KMS` control is off by default. When explicitly selected,
Flutter enables the existing secure-storage setting if necessary and saves a
`PgpPassphraseCache` for that same fingerprint.

Public and unprotected private imports skip passphrase session/cache work. A
secure-storage failure does not roll back successfully imported key material;
the UI reports that the key was imported but remembering the passphrase failed,
keeps no plaintext in the form, and allows the user to retry from Settings.

### Reuse one import body with host-specific completion callbacks

Create a focused reusable Flutter PGP import sheet/body that owns source,
inspection, picker, passphrase, remember, submission, and inline error state.
Settings supplies a completion callback that refreshes the key list and shows a
notification. Onboarding supplies a callback that selects the returned key,
adds it to the selected store when applicable, and advances to SSH setup.

This shares behavior without coupling Settings navigation to Onboarding's step
history.

## Risks / Trade-offs

- **Some existing GPG exports may use packets the common inspector cannot
  parse** -> Fail before keyring mutation with a sanitized unsupported-material
  error and add armored/binary GnuPG interoperability fixtures.
- **Inspecting and validating secret key material uses additional sensitive
  memory** -> Keep the work in Rust, use secret/zeroizing buffers where
  available, avoid clones, and add log/error redaction tests.
- **Backend import can succeed but post-import metadata lookup can fail** ->
  treat this as an import failure with actionable diagnostics; do not create a
  key-bound session from an unconfirmed fingerprint.
- **Secure-storage persistence is not transactional with key import** -> Keep
  the imported key and active in-memory session, report the cache failure, and
  provide the existing Settings retry path.
- **Legacy wrappers temporarily duplicate API surface** -> Mark them as
  compatibility paths, migrate all in-tree callers and tests, then evaluate
  removal in a separate breaking change.

## Migration Plan

1. Add byte-safe inspection, passphrase validation, and canonical fingerprint
   tests in core without changing current Flutter callers.
2. Add typed bridge APIs, compatibility wrappers, secret-field metadata, smoke
   tests, and regenerate FRB bindings.
3. Extend the Flutter repository and security orchestration, then replace both
   existing GUI import forms with the shared flow.
4. Run focused Rust/Flutter tests, full static analysis, and OpenSpec validation.
5. Rollback can restore the old GUI routes and leave the additive bridge methods
   unused; no stored-data migration is required.

## Open Questions

None. The implementation may choose concrete widget names and backend parser
helpers as long as the source-independent, atomic, key-bound behavior remains.
