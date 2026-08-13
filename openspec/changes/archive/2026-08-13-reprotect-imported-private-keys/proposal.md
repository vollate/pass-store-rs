## Why

The pure-Rust backend currently persists imported private keys with their source
protection unchanged, so a legacy maximum-count SHA-1 S2K can make every new PGP
session spend tens of seconds unlocking the same key on Android. Import already
has the passphrase needed to pay that legacy cost once and replace it with a
portable, application-managed OpenPGP protection profile.

## What Changes

- Re-protect passphrase-protected private keys during pure-Rust import using the
  same user passphrase and a documented, version-aware local OpenPGP protection
  profile before any keyring file is committed.
- Unlock and re-protect every protected secret packet atomically, preserve the
  primary fingerprint, public material, certifications, and key capabilities,
  and never persist an unprotected intermediate key.
- Keep stored private keys as interoperable OpenPGP material so private-key
  export continues to use the same fingerprint and passphrase.
- Treat the re-protected file as the one authoritative local private-key
  record, not as an unprotected acceleration cache or a second retained copy.
  Normal unlock and entry decryption continue to require the same passphrase
  under the configured session policy, and exported private material remains
  protected by that passphrase.
- Lazily migrate existing pure-Rust private-key records after their next
  successful authorized unlock, while leaving the old file untouched if
  migration fails.
- Treat re-protection as part of import completion: return typed, sanitized
  failures and do not start the Flutter PGP session until the rewritten key has
  been committed successfully. Any new user-facing status or error text SHALL
  use the existing i18n system and established import UI components.
- Preserve the configured PGP session expiration and opt-in Keychain/KMS
  passphrase policy. This change does not introduce an unbounded decrypted-key
  cache or extend an active session.
- Leave replacing, disabling, or specializing rPGP's `sha1-checked` backend as
  a future optional optimization. The legacy SHA-1 path remains available for
  the one-time import or migration unlock required for compatibility.
- Make GUI deletion verifiable for pure-Rust keys: delete the authoritative
  re-protected private record before removing its public listing record, clear
  matching session/cache state once secret material is gone, and report a
  localized partial result if only public-record cleanup fails. Password-store
  `.gpg-id` files remain unchanged. For a PGP identity such as
  `Alice <alice@example.com>`, typed deletion confirmation requires only the
  human-readable display name `Alice`; the email address is informational and
  is not part of the confirmation value. The existing dialog remains
  scrollable and usable when the software keyboard reduces the viewport.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pgp-and-key-management`: Require the pure-Rust backend to re-protect imported
  protected private material with a local OpenPGP profile, atomically migrate
  existing legacy records, preserve interoperability and key identity, and
  verifiably delete the resulting authoritative private record.
- `native-bridge-api`: Make private-key re-protection part of the existing
  import transaction and expose typed, sanitized re-protection failures without
  exposing passphrases or private material; expose an explicit deletion result
  that distinguishes total failure from secret-material deletion followed by
  public-record cleanup failure.
- `flutter-security-and-onboarding`: Complete protected private-key import and
  start its key-bound session only after local re-protection is committed, with
  localized progress and failure feedback and unchanged expiration semantics;
  make deletion clear matching security state whenever the private record is
  confirmed absent.

## Impact

- Pure-Rust PGP import, private-key serialization, keyring file replacement,
  existing-key migration, decryption, private-key export, and deletion paths.
- Core import validation and backend trait plumbing needed to make the validated
  passphrase available to pure-Rust re-protection.
- Bridge failure DTOs/mappings and generated Flutter bindings if a dedicated
  failure kind or deletion-result DTO is added.
- Shared Settings/Onboarding PGP import orchestration, localized resources, and
  security-session integration.
- Unit, atomicity, migration, GnuPG interoperability, session-expiration, and
  Android release performance regression coverage.
- No CLI behavior, password-store entry format, `.gpg-id` format, or system-GPG
  key storage behavior changes are intended.
