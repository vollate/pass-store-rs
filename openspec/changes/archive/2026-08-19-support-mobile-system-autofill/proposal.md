## Why

Pars can manage mobile password stores, keys, and local app unlock state, but
it does not register with iOS or Android as a system password manager. Users
must open the app manually, reveal or copy an entry, then paste credentials
into apps and websites.

## What Changes

- Register Pars as a system credential provider on iOS and Android.
- Provide username and password autofill for entries in the selected mobile
  password store.
- Add a safe shared autofill index that stores matching metadata only, not
  plaintext passwords.
- Reuse the existing app lock, biometric, PGP passphrase cache, and pure Rust
  mobile PGP runtime so system autofill can authenticate and decrypt entries
  outside the Flutter UI process.
- Add Settings controls to show autofill status, open platform setup screens,
  refresh autofill data, and clear autofill data.

## Capabilities

### New Capabilities

- `mobile-system-autofill`: iOS and Android system password autofill
  registration, matching, authentication, and credential return behavior.

### Modified Capabilities

- `native-bridge-api`: Read-entry bridge requests must optionally carry the
  active PGP passphrase, and native mobile autofill code must be able to call a
  small Rust ABI without Flutter.
- `flutter-vault-and-manage`: Repository reads and copy-password calls must
  pass the active PGP session secret to the bridge when available.
- `flutter-security-and-onboarding`: Mobile passphrase cache behavior must be
  usable by system autofill after local authentication.
- `configuration-and-runtime`: Mobile runtime paths must support app group or
  platform-shared containers where required by system autofill extensions.

## Impact

- Rust core, bridge, and generated Dart bindings need API additions.
- Flutter services, settings UI, and tests need an autofill repository surface.
- Android needs service registration, metadata XML, Kotlin service classes, and
  secure access to the shared index and cached passphrase.
- iOS needs a Credential Provider extension target, app group/keychain
  entitlements, identity store sync, and extension-side Rust access.
- Packaging and manual verification now require device or simulator checks for
  platform autofill enablement and credential fill flows.
