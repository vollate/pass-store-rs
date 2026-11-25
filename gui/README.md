# Pars GUI (`pars_gui`)

Cross-platform Flutter graphical interface for [Pars](../README.md), a
[zx2c4-pass](https://www.passwordstore.org/)-compatible password manager.
`pars_gui` shares core store, OpenPGP, SSH, Git, and Autofill logic with the
Rust workspace through `pars-bridge` and `pars-core`.

## Supported Platforms

| Platform | PGP Runtime Default | System Autofill | Adaptive Layout |
| --- | --- | --- | --- |
| **Android** | Pure-Rust OpenPGP (`rPGP`) | `ParsAutofillService` & `ParsCredentialProviderService` | Bottom `NavigationBar` / `NavigationRail` |
| **iOS** | Pure-Rust OpenPGP (`rPGP`) | `ParsCredentialProvider` app extension | Bottom `NavigationBar` / `NavigationRail` |
| **macOS** | System GnuPG (`gpg` / `gpg2` on `PATH`) | — | Responsive `NavigationRail` |
| **Linux** | System GnuPG (`gpg` / `gpg2` on `PATH`) | — | Responsive `NavigationRail` |
| **Windows** | System GnuPG (`gpg` / `gpg2` on `PATH`) | — | Responsive `NavigationRail` |

On desktop platforms, `pars_gui` uses the standard Pars configuration file and
system GnuPG from `PATH`. On Android and iOS, it automatically configures the
pure-Rust OpenPGP (`rPGP`) backend with app-managed `pgp/`, `ssh/`, and
`stores/` directories inside the app support directory (or the shared App Group
container on iOS so the Credential Provider extension can access it).

## Features

- **Vault & Entry Management**
  - Browse nested directories and search entries across the active password
    store.
  - View parsed pass fields (`username`/`user`/`login`, `email`,
    `url`/`website`, `totp`/`otp`, `note`, plus free-form notes) and render
    passwords as QR codes.
  - Insert, generate (configurable length and symbol options), edit, replace
    passwords, move, rename, and delete entries, as well as run batch
    operations (move, prefix/suffix rename, regenerate, delete).
  - Privacy-aware clipboard (`SensitiveClipboardService`): marks copied secrets
    as sensitive on Android (`IS_SENSITIVE`) and local-only/expiring on iOS
    (`UIPasteboard`), automatically clears secrets after 45 seconds when
    ownership still matches, and enables `FLAG_SECURE` on Android release
    builds.
- **Guided Onboarding & Store Lifecycle**
  - Step-by-step setup for local unlock, biometrics, PGP/SSH keys, and store
    creation, import, cloning, or repair.
  - Create a new local store, import an existing store directory (via the
    Storage Access Framework on Android), clone a remote Git store, disconnect
    a store from the app, or delete a local store with typed confirmation.
- **PGP & SSH Key Management**
  - Generate PGP keys, inspect and import armored text or binary OpenPGP key
    files, configure store `.gpg-id` recipients, and manage stored or
    per-session PGP passphrases with configurable expiration (`Immediately`,
    `5 min`, `15 min`, `1 hour`, or `Until app exit`).
  - Generate, import (text or file), export public keys, export private keys
    (with typed confirmation), and delete SSH keys, with a shortcut to GitHub
    SSH settings.
- **Git Sync & Remotes**
  - Embedded `git2` (vendored `libgit2` and OpenSSL) inside `pars-bridge` for
    status summaries, fetch, pull, push, commit, sync, conflict recovery
    (reset to upstream or push a backup branch), commit history, remote branch
    switching, Git author identity, and remote management (add, edit, remove).
  - Optional commit-on-change and remote check on launch, plus secure storage
    for HTTPS credentials and SSH key passphrases. Desktop builds also support
    running arbitrary Git command lines.
- **Local Unlock & Biometrics**
  - Local app lock using either a **gesture pattern** (default on mobile) or a
    **password** verified with PBKDF2-HMAC-SHA256 (default on desktop), stored
    via `flutter_secure_storage`.
  - Optional biometric unlock (`local_auth`), lock-on-resume, and configurable
    auto-lock timeout (15 minutes by default).
- **System Autofill (Android & iOS)**
  - Maintains a non-secret, path-based autofill index (for example,
    `github.com/alice.gpg` maps to service `github.com` and username `alice`)
    without decrypting entries during normal sync.
  - Supports an explicit opt-in enrichment action to index encrypted login/URL
    fields and an action to forget those enriched fields.
  - Decrypts only the user-selected credential after native platform
    authentication. See [bridge/README.md](bridge/README.md) for the Autofill
    bridge contract.
- **Localization**
  - Full **English (`en`)** and **Simplified Chinese (`zh`)** translations via
    Flutter ARB files, with runtime switching between System, English, and
    Chinese persisted locally.

## Architecture

```text
Flutter UI (gui/lib/screens/, gui/lib/widgets/, gui/lib/app/)
        │
        ▼
Repositories & Services (gui/lib/services/, gui/lib/bridge/pars_bridge_api.dart)
        │  ├── flutter_rust_bridge v2.12.0 (gui/lib/bridge/frb_generated/)
        │  └── Platform MethodChannels (clipboard, autofill, iOS App Group, Android SAF)
        ▼
Rust Bridge Crate: pars-bridge (../bridge/src/api.rs, git_ops.rs, autofill_native.rs)
        │
        ▼
Core Library: pars-core (../core/)
```

- `pars-bridge` depends on `pars-core` and must not depend on `pars-cli`.
- Bridge configuration and method inventory live in
  [`bridge/bridge_config.toml`](bridge/bridge_config.toml) and
  [`bridge/README.md`](bridge/README.md).
- For details on `pars-core`, see [`../core/README.md`](../core/README.md).

## Prerequisites & Setup

### Common Requirements

- **Flutter SDK**: stable channel (Dart SDK `^3.7.2` as specified in
  [`pubspec.yaml`](pubspec.yaml)).
- **Rust toolchain**: Cargo and `rustup` (the workspace
  [`../rust-toolchain.toml`](../rust-toolchain.toml) configures `nightly` with
  `rustfmt` and `clippy`; CI packaging builds `pars-bridge` with `stable`).

### Platform-Specific Toolchains

- **Android**: Android SDK & NDK, JDK 17, and `cargo-ndk`:
  ```sh
  cargo install cargo-ndk --locked
  ```
  Ensure the corresponding Rust Android targets are installed (e.g.,
  `rustup target add aarch64-linux-android` for `arm64-v8a`).
- **iOS**: macOS with Xcode (`xcodebuild`, `lipo`). `bridge/build_unix.sh ios`
  adds `aarch64-apple-ios` (and simulator targets `aarch64-apple-ios-sim` /
  `x86_64-apple-ios` when available) via `rustup`.
- **macOS**: macOS with Xcode Command Line Tools (`install_name_tool`,
  `codesign`).
- **Linux**:
  ```sh
  sudo apt-get install -y clang cmake git libgtk-3-dev ninja-build pkg-config
  ```
- **Windows**: Visual Studio with the Desktop development with C++ workload and
  PowerShell.
- **Desktop runtime**: GnuPG (`gpg`/`gpg2`) available on `PATH` for desktop
  vault operations.

### Package Mirrors

[`.vscode/settings.json`](../.vscode/settings.json) configures Flutter China
mirrors, and [`pubspec.yaml`](pubspec.yaml) references hosted dependencies on
`https://pub.flutter-io.cn`:

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

When running Flutter commands from a terminal outside VS Code, export these
variables if your environment relies on the mirror before running
`flutter pub get`, `flutter run`, or `flutter build`.

Install Dart/Flutter dependencies:

```sh
cd gui
flutter pub get
```

## Building the Native Bridge & Running the App

Each platform's Flutter build automatically compiles and bundles `pars-bridge`,
so standard `flutter run` and `flutter build` commands work out of the box once
prerequisites are installed. You can also run the bridge build scripts directly
from the repository root when debugging native builds or packaging artifacts.

### Linux

- **Run / build app** (CMake in `gui/linux/CMakeLists.txt` runs
  `gui/bridge/build_unix.sh linux` and copies `libpars_bridge.so` into the
  bundle's `lib/` directory):
  ```sh
  cd gui
  flutter run -d linux
  flutter build linux --release
  ```
- **Build bridge directly** (from repo root):
  ```sh
  PARS_BRIDGE_PROFILE=release \
  PARS_LINUX_OUTPUT_DIR="$PWD/gui/build/native/linux" \
    bash gui/bridge/build_unix.sh linux
  ```

### Android

- **Run / build app** (`gui/android/app/build.gradle.kts` registers
  `buildParsBridge<Variant>` and runs `gui/bridge/build_unix.sh android` via
  `cargo-ndk`):
  ```sh
  cd gui
  flutter run -d <android-device-id>
  flutter build apk --release
  ```
- **Build bridge directly** (from repo root; `PARS_ANDROID_TARGETS` defaults to
  `arm64-v8a` and accepts a comma-separated list such as
  `arm64-v8a,armeabi-v7a,x86_64`):
  ```sh
  PARS_ANDROID_PROFILE=release \
  PARS_ANDROID_OUTPUT_DIR="$PWD/gui/build/native/android" \
    bash gui/bridge/build_unix.sh android
  ```

### iOS

- **Run / build app** (Xcode's build phase in `gui/ios/Runner.xcodeproj` invokes
  `gui/bridge/build_unix.sh ios` and links static libraries for both `Runner`
  and `ParsCredentialProvider`):
  ```sh
  cd gui
  flutter run -d <ios-device-or-simulator-id>
  flutter build ios --release
  ```
- **Build bridge XCFramework directly** (from repo root):
  ```sh
  PARS_IOS_PROFILE=release \
  PARS_IOS_OUTPUT_DIR="$PWD/gui/build/native/ios" \
    bash gui/bridge/build_unix.sh ios
  ```

### macOS

- **Run / build app** (Xcode's build phase invokes
  `gui/macos/build_pars_bridge.sh` to create `pars_bridge.framework`):
  ```sh
  cd gui
  flutter run -d macos
  flutter build macos --release
  ```
- **Build bridge framework directly** (from repo root):
  ```sh
  PROJECT_DIR="$PWD/gui/macos" \
  TARGET_BUILD_DIR="$PWD/gui/build/macos-ci" \
  FRAMEWORKS_FOLDER_PATH="Frameworks" \
  CONFIGURATION=Release \
  CODE_SIGNING_ALLOWED=NO \
    bash gui/macos/build_pars_bridge.sh
  ```

### Windows

- **Run / build app** (`gui/windows/CMakeLists.txt` runs
  `gui/bridge/build_windows.ps1` and stages `pars_bridge.dll` next to
  `pars_gui.exe`):
  ```powershell
  cd gui
  flutter run -d windows
  flutter build windows --release
  ```
- **Build bridge DLL directly** (PowerShell, from repo root):
  ```powershell
  ./gui/bridge/build_windows.ps1 -Profile Release -OutputDir "$PWD/gui/build/native/windows"
  ```

## Development Workflows

Run Flutter commands from `gui/`:

```sh
# Regenerate localization files after editing lib/l10n/app_en.arb or app_zh.arb
flutter gen-l10n

# Static analysis
flutter analyze

# Unit, widget, accessibility, and golden tests
flutter test
```

### Additional Verification

- **Rust bridge smoke tests** (from repo root):
  ```sh
  cargo test -p pars-bridge
  ```
- **Golden updates**: Only run `flutter test --update-goldens` when a visual
  change is intentional and the rendered diff has been inspected.
- **Device integration test harness**:
  [`tool/run_single_store_device_evidence.sh`](tool/run_single_store_device_evidence.sh)
  temporarily wires `integration_test` templates and drives an end-to-end
  single-store persistence check on an Android emulator/device (and optionally
  an iOS device):
  ```sh
  bash gui/tool/run_single_store_device_evidence.sh emulator-5554
  # Or with an optional second iOS device argument:
  bash gui/tool/run_single_store_device_evidence.sh emulator-5554 <ios-device-id>
  ```
- **UI design conventions**: See [`../AGENTS.md`](../AGENTS.md) for design
  tokens (`ParsSpacing`, `ParsRadii`, `ParsSizes`, `ParsInsets`), shared
  components (`AppSectionBox`, `ParsButtonGrid`, `ParsDialog`), clipboard rules,
  and 200% text-scale verification requirements.

## Directory Structure

```text
gui/
├── lib/
│   ├── app/          # App bootstrap, root widget, theme, and design tokens
│   ├── bridge/       # Dart adapter (pars_bridge_api.dart) & FRB generated code
│   ├── component/    # Shared search bar and reusable UI elements
│   ├── l10n/         # ARB translations (app_en.arb, app_zh.arb) & generated l10n
│   ├── models/       # Entry, key, PGP import, and Git sync models
│   ├── screens/      # Onboarding, lock screen, adaptive shell, vault, settings
│   ├── services/     # Bridge repositories, security, clipboard, autofill, caches
│   └── widgets/      # Shared sections, dialogs, action groups, key/Git flows
├── bridge/           # Native bridge build scripts, C headers, config & docs
├── tool/             # Device integration test runner & templates
├── test/             # Unit, widget, localization, accessibility & golden tests
├── android/          # Android runner, SAF importer, Autofill & Credential services
├── ios/              # iOS runner, App Group shared state & ParsCredentialProvider
├── macos/            # macOS runner and build_pars_bridge.sh framework script
├── linux/            # Linux GTK runner & CMake bridge bundling
├── windows/          # Windows Win32 runner & CMake bridge bundling
├── l10n.yaml         # Flutter localization generator configuration
└── pubspec.yaml      # Flutter package manifest and dependencies
```

The Rust side of the bridge lives in [`../bridge/`](../bridge/) (`pars-bridge`).
