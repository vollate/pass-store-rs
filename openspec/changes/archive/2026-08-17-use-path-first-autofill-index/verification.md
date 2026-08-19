## Verification environment

- Date: 2026-08-17
- Rust: repository nightly toolchain
- Flutter: 3.44.2
- Android reference device: OnePlus PHK110, Android 16 / API 36, arm64-v8a
- Android Gradle/Kotlin checks used Android Studio's bundled JDK 21; the shell's JDK 26.0.2 is not understood by the current embedded Kotlin parser.
- iOS checks used Xcode's iOS 26.5 simulator runtime on an iPhone 17 simulator.

## Automated correctness

- `cargo test -p pars-core --test autofill_test` passed 8 path-first tests covering path derivation, root and nested entries, strict schema rejection, atomic reads, zero-decrypt rebuild/reconcile/incremental operations, matching score classes, exactly-one selected decrypt, transactional URL enrichment, and alias clearing.
- `cargo test --workspace -- --skip macos_clipboard_test` passed, including 18 bridge smoke tests and 3 native Autofill JSON ABI tests.
- `cargo fmt --all -- --check` passed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- Production Autofill source contains no `refresh_autofill_index`, backend-backed refresh, Android package request, package index, or package matching symbol. The only package-shaped request is a native ABI rejection test proving `androidPackage` is not accepted.
- Focused Flutter Autofill/repository tests passed 29 tests, including metadata-only ranking patches, incremental upsert, and failure isolation after a successful vault mutation.
- The complete Flutter suite passed all 169 tests.
- `flutter analyze` and formatting checks passed.

## Platform checks

- Android `:app:compileDebugKotlin` passed with the new app-label request parser, JNI request model, AutofillService, Credential Manager provider, and selected-credential activity.
- Android `:app:testDebugUnitTest` completed successfully; this target currently has no JVM test sources.
- Android `:app:connectedDebugAndroidTest` completed successfully against PHK110 and rebuilt/packaged the Rust JNI bridge; this target currently has no instrumentation test sources, so real system-provider selection remains a device-level check.
- iOS `xcodebuild test` built the Runner and Credential Provider extension without signing and passed `RunnerTests.testAutofillIndexDecodesSharedRustJson` against the replacement path-first schema.
- Native provider availability and full OS-mediated fill UX still depend on Android system services and iOS app-group/keychain provisioning as documented in the main specification.

## Performance invariants

Core counting-backend tests establish these deterministic invariants:

- explicit path rebuild: zero decrypt calls;
- incremental upsert/move/remove/ranking patch: zero decrypt calls;
- batch path reconciliation: zero decrypt calls;
- candidate query: zero decrypt calls;
- selected credential resolution: exactly one decrypt call and no index write;
- optional enrichment: exactly one decrypt per explicitly selected path, with no partial index commit on failure.

The previous 13.44-second metadata stage was approximately 220 repeated 55–65 ms decryptions, not one slow decrypt. That attribution is now also recorded in `calibrate-rpgp-local-key-protection/verification.md`.

## Device release verification

The final arm64 release APK was built with the release Rust JNI bridge:

- APK: `gui/build/app/outputs/flutter-apk/app-release.apk`
- APK SHA-256: `04234f626678482f1602bc38fd929e5b868bccf36ca9cd805f5081bd2c92b6fa`
- packaged `lib/arm64-v8a/libpars_bridge.so` SHA-256: `2c6bea513e93404e950ddaa1161698a42b61b30cca8de2c506972cdb8c1104bc`

`adb install -r` installed the APK successfully on PHK110. The package's
`firstInstallTime` remained `2026-06-24 19:56:42`, its data directory remained
`/data/user/0/top.vollate.pars_gui`, and only `lastUpdateTime` changed, confirming
an in-place replacement without clearing application data.

After owner authentication, the installed production release was exercised
against the real 220-entry vault:

- The stale development index failed closed on its removed `websites` field, as
  designed, and the Settings sheet directed the user to rebuild it.
- **Rebuild paths** completed successfully, showed `Ready` and `220 entries
  indexed`, and displayed `Path-based autofill data rebuilt without decrypting
  entries`. The captured completion frame arrived 1,216.7 ms after the ADB tap
  command while the procedure intentionally slept 650 ms before capture; there
  was no former 12–13 second whole-vault decrypt delay.
- Opening a real recent entry produced a fully rendered detail sheet, masked
  password, and parsed fields in the first immediate captured frame. The bound
  from issuing the ADB tap through receiving that frame was **606.2 ms**, which
  includes ADB input and screenshot-transfer overhead and is below the 800 ms
  end-to-end requirement.
- Toggling Favorite changed the live action to Unfavorite in the first immediate
  captured frame. The equivalent ADB-input-through-screenshot bound was **545.0
  ms**; the action was then reverted. There was no whole-index rebuild delay.

The release binary exercised on-device is the same code covered by the counting
backend: rebuild and metadata patch call APIs that have no backend/passphrase
input and therefore make zero decrypt calls, while selected resolution made
exactly one call in the deterministic regression test. No temporary profiling
instrumentation or secret logging was included in the installed artifact.
