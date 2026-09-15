# Verification

## Automated checks

- `flutter analyze`: passed.
- `flutter test`: passed, 271 tests.
- Android importer JVM tests: passed, 11 tests.
- Android debug APK: built successfully.
- Android instrumentation APK: compiled successfully.
- `cargo fmt --all -- --check`: passed.
- `cargo clippy --workspace --all-targets`: passed with the existing unused `jni` manifest warning.
- `cargo test --workspace --no-fail-fast`: passed.

The complete Android JVM suite still has an unrelated existing failure in
`ParsAutofillStateGateTest`; the importer test class passes independently.
The existing DocumentsUI instrumentation harness does not complete on the
connected ColorOS device, so provider UI coverage still requires the emulator.

## ColorOS evidence

- Model: `PHK110`
- Build fingerprint:
  `OnePlus/PHK110/OP5913L1:16/BP2A.250605.015/T.26c6ee8-56ebcf-56ebcc:user/release-keys`
- Debug APK replacement preserved the original app installation time.
- Direct recovery of the real store succeeded through the app after the user
  granted All-files access.
- Resulting encrypted-entry count: 773. This was measured inside the debug
  app's private storage without recording entry names or contents.
- No Android emulator or AVD is available on this host. The existing
  DocumentsUI instrumentation runner also hangs under ColorOS ActivityScenario,
  so unchanged-provider UI verification remains pending on an emulator.

## Play Console declaration

Proposed justification:

> Pars is a password-store client whose core import function must preserve a
> user-selected directory tree, including non-media `.gpg` files and Git
> metadata. On affected OPPO/OnePlus ColorOS devices, Android's
> DocumentsProvider returns a finished empty listing for populated local
> folders, making normal SAF import unusable. Pars always attempts SAF first
> and requests All files access only after this provider fault and explicit
> user consent. The fallback reads only the folder selected immediately before
> the request, copies it into app-private storage, never writes to shared
> storage, and does not upload or share file contents.

Approval is not guaranteed: Google Play applies a narrow core-functionality
policy to `MANAGE_EXTERNAL_STORAGE`, so the declaration must be reviewed before
shipping through Play. Sideloaded and F-Droid builds do not require Play review.
