# Verification

## Summary

The whole-GUI redesign is implemented across Flutter, Android, iOS, and the small bridge seam required to verify pure-Rust private-key readiness. Existing password-store ciphertext, OpenPGP protection, Git mutation semantics, path-first Autofill schema, package-matching prohibition, and selected-entry-only decryption remain unchanged.

## Flutter and UI Foundation

- `dart format lib test` — passed.
- `flutter analyze` — passed with no issues.
- Dart LSP diagnostics — 0 diagnostics across the GUI/test workspace.
- `flutter test` — **246/246 passed**.
- Deterministic golden matrix — **10/10 passed**:
  - compact English/light Vault;
  - compact English/light Vault selection;
  - compact Chinese/dark Vault search;
  - compact English/dark entry detail;
  - compact English/light detail loading;
  - compact English/light detail error;
  - compact Chinese/light Settings;
  - expanded English/dark Settings;
  - compact Chinese/light onboarding;
  - compact Chinese/dark lock.
- Responsive/semantics coverage passed for compact phone, keyboard phone, landscape, medium, expanded, 200% text scale, NavigationBar/NavigationRail, adaptive sheet/dialog, stable detail geometry, lock scrolling, gesture-dot semantic selection, Clear/Submit, and overflow detection.
- Source/localization audits passed:
  - English/Chinese ARB key and placeholder parity;
  - Android/iOS native resource parity;
  - no quoted English fallback in presentation properties;
  - no raw caught-error rendering from screens/widgets;
  - no direct secret clipboard write outside `SensitiveClipboardService`;
  - no literal empty production action callback.

## Android Build and Runtime

- JDK: Android Studio bundled OpenJDK 21.
- `./gradlew app:compileDebugKotlin app:testDebugUnitTest --no-daemon` — `BUILD SUCCESSFUL`.
- Kotlin/JUnit field-selection tests cover:
  - focused visible form over earlier hidden/inactive fields from another login method on the same page;
  - latest adjacent visible pair when a browser omits focus state;
  - username-only login step;
  - password-only login step.
- `flutter build apk --release` — passed.
- Final release APK:
  - Path: `gui/build/app/outputs/flutter-apk/app-release.apk`
  - SHA-256: `21477918d90301594c3f8d3511517941b7ecea124436d2d4126c4b152ee50ac5`
- Installed with `adb install -r`; application data was preserved.
- Release window dump reports `SECURE`; capture-protection source/runtime checks passed.
- Native clipboard checks passed for sensitive metadata, native delayed expiry, per-write owner-token and value matching, same-value re-copy protection, external-identical-text protection, API-compatible clearing, background clearing, and no unsafe mobile `PlatformException` fallback.

## Android Emulator / Browser Autofill Evidence

A clean Android 16 ARM64 emulator was provisioned with synthetic-only data:

- Generated a local test PGP key and configured the explicit secure-storage test passphrase `foo`.
- Created app-managed test store `personm`.
- Created synthetic entries `linux.do/foo` and `127.0.0.1/foo`, both with password `foo`.
- Rebuilt the path-first index: Settings reported `Ready / 2 entries indexed`.
- Selected Pars as both Autofill service and credential provider.
- Installed official Mozilla Fenix 154.0 ARM64 APK from `ftp.mozilla.org`.

Observed results:

1. **No match:** local `127.0.0.1` form before its entry existed displayed `No matching passwords`; no field was changed.
2. **linux.do multi-login-form regression:** tested with Firefox at `https://linux.do/login`, where one page exposes several login methods/form variants. Pars displayed `linux.do · Pars / foo`; `dumpsys autofill` bound the Dataset to the current visible IDs (`i7/i8`), not an earlier hidden/inactive form, and reported `NUM_DATASETS=1`.
3. **Authenticated fill:** selecting the linux.do candidate opened `Unlock Pars / Fill the selected password`; emulator PIN authentication completed with `AUTH_STATUS=DATASET_AUTHENTICATED`, selected Dataset `linux.do/foo`, and both username/password ViewStates recorded non-null `autofilledValue` values.
4. **Password-only second step:** synthetic `/step2.html?username=foo` contained only a password field. Pars displayed `127.0.0.1 · Pars / foo`; after authentication, the sole password ViewState recorded an autofilled value and selected Dataset `127.0.0.1/foo`.
5. **Username-only provider logic:** pure Kotlin selection tests verify a username-only latest context remains fillable. Whether a browser requests Autofill on a particular username-only HTML page remains browser-controlled; Pars no longer requires a simultaneous password ID.
6. **Multi-context behavior:** the service uses field IDs only from the latest FillContext while inheriting website/app/query metadata from earlier contexts, preventing stale-page field fills.

Android presentation remains app-owned and RemoteViews-safe (`LinearLayout`/`TextView`; no `TwoLineListItem`). Candidate PendingIntents now use collision-resistant UUID data identity plus one-shot semantics.

## iOS

- `xcodebuild -project Runner.xcodeproj -target ParsCredentialProvider -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` — passed.
- `flutter build ios --simulator --debug` — built `build/ios/iphonesimulator/Runner.app` successfully.
- Runner now uses a custom `SceneDelegate` for `sceneWillResignActive`, `sceneDidBecomeActive`, and capture-state privacy covering; it is wired through `Info.plist` and the Runner Sources phase.
- Clipboard publication is local-only, expiration-aware, and value-matched before clear.
- English/`zh-Hans` Runner/provider resource parity passed; the provider authentication reason uses `NSLocalizedString`.
- Missing shared indexes remove stale iOS credential identities, and identity synchronization failures are propagated.
- No physical iOS device was available; iOS evidence is simulator compilation, deterministic Flutter tests, and native source/resource tests.

## Security and State Corrections from Independent Review

- Native Autofill publication now uses only an explicitly remembered secure-storage passphrase; an active session-only PGP passphrase is never published durably. Tests cover session-only null publication, explicit remembered publication, and clearing.
- Lock/background transitions clear decrypted detail presentation, clear owned clipboard data, and republish native Autofill security state without blocking the lock UI.
- Required missing-private-key state reopens onboarding repair. Pure-Rust bridge inspection now compares `.gpg-id` recipients against listed private key material instead of treating every non-empty file as healthy.
- Public-only PGP keys are excluded from onboarding key eligibility.
- Entry-detail loading/passphrase/error/content states use stable adaptive geometry.
- User-visible caught errors pass through localized/sanitized `UiProblem`; optional diagnostics remain explicitly disclosed.

## Rust, Bridge, and Autofill Non-Regression

- `cargo test -p pars-core --test autofill_test` — **8/8 passed**.
- `cargo test -p pars-bridge --lib` — **5/5 passed**, including pure-Rust private-key matching tests.
- `cargo test -p pars-bridge --test bridge_smoke_test` — **18/18 passed**.
- `cargo clippy --workspace --all-targets -- -D warnings` — passed.
- Focused Flutter Autofill/repository suites passed within the full 246-test run.
- No FRB API signature changed; generated bridge API consistency tests passed.

## OpenSpec and Repository Hygiene

- `openspec validate redesign-and-unify-gui-experience --strict` — passed.
- `git diff --check` — passed.
- All **91/91** implementation tasks are complete.
- Parallel implementation lanes and independent final reviewers modified no staging state, commits, pushes, publications, or releases.

## Residual Platform Limits

- Native Autofill popup pixels remain OEM/System-UI controlled; tests assert safe hierarchy, localized identity, correct field IDs, no empty fill, authentication, and selected-entry-only behavior rather than identical pixels.
- Flutter goldens use the deterministic test font and primarily protect geometry/theme hierarchy rather than production Chinese glyph shape.
- Production Android signing and iOS provisioning identities remain deployment configuration concerns outside this GUI change; the repository still uses development scaffold signing/identifiers.
