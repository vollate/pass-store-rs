# Verification: adopt-single-store-and-optional-git

Date: 2026-08-21 CST

## Scope and result

This verification used repository fixtures, test-only Android `DocumentsProvider` data, iOS Simulator, and the configured Android emulator only. No real device, real key, real password, staging, commit, push, or publication was performed. One initial `flutter test integration_test/... -d emulator-5554` attempt unexpectedly uninstalled the debug package during tool teardown; it affected synthetic data only. The documented synthetic `personm` store was immediately rebuilt with a newly generated synthetic OpenPGP key and equivalent synthetic entries. The repeatable evidence command was then changed to `flutter drive --keep-app-running`; its run and every subsequent deployment used replacement install behavior and preserved the restored package data. No manual `adb uninstall` or app-data clear command was used.

All implementation and device tasks pass. Dart formatting, Flutter Analyze, configured Dart LSP diagnostics, all Flutter tests, localization, accessibility, and goldens pass.

## 9.1 Rust workspace

Commands:

```text
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --quiet
cargo test -p pars-core --test config_canonical_store_test --quiet
cargo test -p pars-bridge --test bridge_smoke_test --quiet
```

Results:

- Formatting: pass.
- Workspace Clippy with warnings denied: pass.
- Workspace tests: pass, 177 executed and 18 legacy CLI cases ignored, zero failures.
- Bridge: 21 unit and 23 smoke tests pass.
- Core Autofill: 9/9; canonical config migration: 6/6.
- Singular lifecycle, multi-recipient PGP readiness, upstream-aware Git, store-bound Autofill reconcile, atomic config, delete retry, and legacy no-fallback cases are included.
- Safe Create tests reject existing directory/file/symlink/raced targets, preserve old `.gpg-id`, and clean only new staging/installed trees on Git/config failure.

## 9.2 Flutter and Dart LSP

Commands:

```text
cd gui
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter compact
flutter test test/localization_completeness_test.dart test/responsive_accessibility_matrix_test.dart test/ui_visual_matrix_test.dart --reporter compact
```

Results:

- Dart format: pass.
- Flutter Analyze: no issues.
- Full Flutter suite: 262/262 pass.
- Localization/accessibility/visual matrix: 20/20 pass.
- Deterministic goldens: 10/10 pass.
- Configured Dart LSP diagnostics after the final Dart edits: pass, 0 diagnostics across 101 files.

## 9.3 Android and release APK

Commands:

```text
JAVA_HOME=/tmp/pars-temurin-21/Contents/Home ./gradlew testDebugUnitTest --no-daemon
JAVA_HOME=/tmp/pars-temurin-21/Contents/Home ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest --no-daemon
adb -s emulator-5554 install -r -t <app-debug.apk>
adb -s emulator-5554 install -r -t <app-debug-androidTest.apk>
adb -s emulator-5554 shell am instrument -w -r top.vollate.pars_gui.test/androidx.test.runner.AndroidJUnitRunner
JAVA_HOME=/tmp/pars-temurin-21/Contents/Home flutter build apk --release
adb -s emulator-5554 install -r <app-release.apk>
```

Results:

- Android/JVM tests: `BUILD SUCCESSFUL`.
- Instrumentation: `OK (8 tests)` in 44.45 seconds.
  - Five production importer/provider transaction tests.
  - Three Android Autofill enabled/tombstone/generation-race tests.
- Release APK built successfully.
- APK: `gui/build/app/outputs/flutter-apk/app-release.apk`
- Size: 91,778,219 bytes.
- SHA-256: `54dfa43141fde4502dea73ad49d7e3cc4aa23c308ee89037c8d7a8caec24c5cc`.
- Release APK inspection found no `integration_test`, `FlutterTestRunner`, or synthetic-provider symbols.

Data-preservation evidence:

- The final repeatable Android integration run used `flutter drive --keep-app-running`; `firstInstallTime` remained `2026-08-21 03:22:13` before and after that run.
- Subsequent debug, androidTest, release, and debug round-trip deployments used `adb install -r` / `adb install -r -t` and retained that same timestamp.
- The restored synthetic store `files/stores/personm` survived every compliant rerun and final deployment with:
  - `.gpg-id`
  - `127.0.0.1/foo.gpg`
  - `linux.do/foo.gpg`

## 9.4 iOS simulator

Command:

```text
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **`.

Runner native tests: 5/5 pass:

- shared Rust Autofill JSON decode;
- disabled tombstone/index/identity cleanup including stale publication race;
- in-flight credential resolution rejected after generation tombstoning;
- credential identity record identifiers bind publication generation;
- unavailable app-group cleanup still clears authorization and identities.

A simulator-executed Flutter integration test also resolved the production store setup, removing, and repair strings in both English and Chinese.

Known warning: credential-provider `CFBundleShortVersionString` is `1.0` while the containing app is `1.0.0`.

## 9.5 Emulator Import evidence

Emulator:

- Serial: `emulator-5554`
- AVD: `Medium_Phone_API_36.0`
- Model: `sdk_gphone64_arm64`
- Android: 16 / API 36
- ABI: `arm64-v8a`
- Fingerprint: `google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.D1/13818094:user/release-keys`

The test-only provider drives production DocumentsUI, `ContentResolver`, MethodChannel, staging, finalize, commit, rollback, and cancel seams. Its valid Git tree contains a real commit/tree/blob graph plus 256 valid nested loose objects. The imported emulator tree was exported after instrumentation and independently checked:

```text
git fsck --full                                  PASS
git log -1                                       cd504016... synthetic import fixture
git branch --show-current                        main
git remote get-url origin                        https://example.invalid/synthetic.git
```

Missing-Git evidence:

- Provider tree staged without `.git`.
- Cancel removed staging and did not create/replace destination.
- Continue finalized a usable local-only store without `.git`.
- A device-side production-seam integration run passed `ManagedStoreGitDecision.initialize` through the same staged missing-Git resolver used by production before finalization. It executed embedded `git2` against staging on emulator-5554, finalized and registered the result, and observed Git mode `local`. No post-finalization direct-init workaround or system `git` executable was used.
- The resolver was invoked exactly once with `ManagedStoreGitState.absent`; `.git` existed only in the finalized app-managed destination, while the synthetic source digest was unchanged and its source contained no `.git`.
- The final repeatable run used `flutter drive --keep-app-running`; all four named device integration tests passed.
- The same run is repeatable with `gui/tool/run_single_store_device_evidence.sh`; the harness is temporarily injected and is absent from the production pubspec/APK.

Invalid-Git evidence:

- Provider delivered `.git/HEAD = not-a-valid-head`.
- The invalid tree was staged, classified by the production decision contract, cancelled, and never replaced the existing destination marker.
- Exported tree fails `git rev-parse --is-inside-work-tree` as expected.

## 9.6 Removal/privacy evidence

The device-side Flutter integration uses disposable canonical configs, pure-Rust keyrings, app-managed stores, genuinely encrypted credentials written through `BridgeBackedRepository.saveEntry`, metadata, active sessions, durable synthetic passphrases, and real native publication. One emulator test opens the production Vault detail, decrypts the credential with the synthetic protected key/session, taps Reveal, and observes `live-decrypted-password`; direct canonical removal while that detail remains live unmounts the detail and removes the revealed value before store setup appears. A separate test opens and reveals `synthetic-password`, then drives production Settings → Password store → Delete app copy with exact typed confirmation. It verifies shell/confirmation removal, setup UI, Recent/Favorite metadata and active-session clearing, retained durable preference, native `enabled=false` with no root/passphrase, deleted filesystem root, and singular config with no store. Arbitrary placeholder bytes are not used as decryption evidence. The existing restored `personm` store remains untouched.

Android instrumentation additionally verifies explicit publication generation, encrypted synthetic passphrase readback, synchronous `enabled=false` clear, generation change on same-root replacement, tombstoning during resolution, stale index retained but unservable, and zero candidates after tombstoning. Candidate intents and iOS credential identity record identifiers carry only path plus generation, never a password. Final native state is:

```xml
<boolean name="enabled" value="false" />
```

Flutter behavior tests pass for:

- lifecycle notification unmounting `MobileShell` and closing a sensitive route;
- deleting the sole app-managed store entering store setup without resetting gesture security;
- clearing entries, query/selection navigation, Recent/Favorite metadata, active PGP session, enrichment, shared index, candidates, and native publication before bridge mutation;
- retaining only the durable secure-storage passphrase preference;
- replacement isolation and explicit non-decrypting rebuild requirement;
- failure retry and dual metadata-sentinel fail-closed behavior;
- stale publication/reconcile races and post-decryption generation checks ending in disabled state.

## 9.7 Legacy configuration

Automated config and bridge tests verify:

- non-empty prior `default_repo` is the sole canonical GUI store;
- an empty default recovers only the first non-empty legacy path;
- ignored legacy directories remain untouched;
- successful writes normalize `repos` to zero or one canonical mirror;
- disconnect/delete never select another legacy root;
- missing canonical roots can be cleared and retried safely.

Results: core canonical config 6/6; bridge smoke 23/23.

## 9.8 OpenSpec and repository hygiene

Commands:

```text
openspec validate adopt-single-store-and-optional-git --strict
openspec validate --all --strict
git diff --check
git diff --cached --name-only
```

Final result is recorded after the task update. No files are staged. Branch is `refactor/gui-design`; baseline HEAD is `b034be73073a98a9d43ceb372521e8520275e894`.

## Residual risks


- Persistent app-managed import transaction journaling across process death remains outside this change; native Autofill tombstones are durable.
- OEM-specific DocumentsUI implementations are covered by lower-level safety/retry tests, while UI automation ran on the Android 16 Google emulator.
- Android/iOS HTTPS trust uses default libgit2 verification; target compilation and structured operations are covered, but no external live TLS endpoint was contacted.
- Windows-only atomic replace and non-following `.gpg-id` tests are defined but were not executable on this macOS host.
- The Android release build still uses debug signing configuration and must not be distributed as a production-signed artifact.
- The existing iOS extension/app version mismatch warning remains deployment configuration debt.
- The initial Flutter integration harness teardown incident changed the emulator package's historical first-install timestamp; the restored data and all later compliant runs are documented above rather than claiming the original timestamp survived.
