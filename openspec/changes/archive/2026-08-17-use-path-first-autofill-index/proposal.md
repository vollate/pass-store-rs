## Why

The current autofill refresh decrypts every password entry to discover usernames, URLs, and Android package metadata, turning a routine entry open or metadata update into hundreds of serial PGP decryptions. Autofill candidate discovery can instead use the already-public password-store path convention, eliminating the observed multi-second delay and keeping decryption confined to the credential the user selects.

## What Changes

- **BREAKING** Replace decrypted-content indexing with a path-first index: the immediate parent directory is the Website/App matching name and the `.gpg` filename stem is the Username.
- Make normal full index rebuilds and incremental add, edit, move, delete, favorite, and recent updates operate without a PGP backend, passphrase, or entry decryption.
- Decrypt exactly one selected entry after platform authentication, returning its first-line password while using the indexed filename stem as the username.
- **BREAKING** Remove Android package identifiers, package-name matching, package mappings, and `android-package`/`android_package` field handling from the core, bridge, native JSON ABI, and platform adapters.
- Add an explicit, opt-in URL-enrichment operation for users who choose to decrypt entries and add normalized `url`, `website`, or `service` aliases; this operation is separate from default rebuild and mutation flows.
- Replace the unpublished autofill index and SDK interfaces directly, with no legacy schema readers, compatibility wrappers, migration code, or deprecated API aliases.
- Keep favorite and recent ranking updates lightweight and prevent metadata-only reads from triggering index rebuilds.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `mobile-system-autofill`: Redefine index construction, matching, credential resolution, mutation updates, optional URL enrichment, and public integration interfaces around non-decrypting path metadata.

## Impact

- Rust core index models and APIs in `core/src/autofill.rs`.
- Flutter Rust Bridge request/response DTOs and generated Dart bindings in `bridge/src/api.rs` and `gui/lib/bridge_generated/`.
- Dart autofill repository, bridge-backed vault mutation hooks, settings actions, and platform publication in `gui/lib/services/`.
- Android JNI JSON ABI, AutofillService, Credential Manager provider, request parser, and native bridge under `gui/android/`.
- iOS C JSON ABI consumers, shared index decoding, credential identities, and provider extension under `gui/ios/`.
- Rust, Dart, Android, iOS, and device-level regression coverage; no password-store ciphertext, PGP protection, or platform provider registration changes.
