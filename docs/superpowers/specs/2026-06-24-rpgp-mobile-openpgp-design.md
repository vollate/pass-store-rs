# rPGP Mobile OpenPGP Backend Design

## Decision

Mobile PGP uses an in-process Rust OpenPGP backend built on the `pgp` crate from
`rpgp/rpgp`. Desktop and CLI keep the existing `system_gpg` default so users with
an installed GnuPG setup keep their current behavior. The previously explored
mobile bundled-GnuPG path stays documented only as a later fallback for desktop
or specialist builds.

## Scope

The first milestone implements the pass-compatible subset required by the GUI:
public/private key import, generated key storage, key listing, fingerprint
inspection, public/private export, `.gpg-id` recipient resolution, entry
encryption, and entry decryption. The backend must interoperate with standard
GnuPG-generated stores and keys.

Out of scope for this milestone: GPGME, direct GnuPG subprocesses on mobile,
keyservers, Web of Trust, ownertrust, smart cards, revocation-policy UI, and
OpenKeychain/Android provider integration.

## Architecture

`pars-core` keeps `PgpBackend` as the boundary. A new `RpgpBackend` implements
that trait and stores armored keys in an app-owned keyring directory configured
through `PgpBackendConfig.keyring_home`. `SystemGpgBackend` remains unchanged for
CLI and desktop users.

Bridge APIs stop returning a concrete `SystemGpgBackend`; instead they return a
boxed `PgpBackend`. The Flutter repository can request the `pure_rust` backend
on Android and iOS without resolving a `gpg2` executable path.

## Data Model

The rPGP keyring is file based:

- `public/<fingerprint>.asc` stores an armored public key.
- `private/<fingerprint>.asc` stores an armored private key.

The private key import path also writes or updates the matching public key when
rPGP can derive it. Listing merges both directories by fingerprint so one key
record can report whether a private key is available.

## Entry Crypto Flow

Encryption reads recipients from `.gpg-id`, resolves each recipient against the
rPGP keyring by full fingerprint, long key ID, short key ID, or user ID text,
and writes a binary `.gpg` message by default. Decryption tries available
private keys and an empty passphrase first. Passphrase-protected private keys
can be wired through the existing GUI PGP passphrase session in a later step.

## Testing

Tests must prove the contract at three levels:

- Unit tests for keyring import/list/export/fingerprint resolution.
- Pure Rust backend tests for `.gpg-id`, encryption, and decryption.
- GnuPG interoperability tests when `gpg` is available: GnuPG encrypts and rPGP
  decrypts; rPGP encrypts and GnuPG decrypts.

The test suite may skip GnuPG interoperability checks when `gpg` is unavailable,
but pure Rust tests must not skip on mobile or CI.
