# Pars GUI Platform Packaging

This document defines the phase-1 packaging targets for the Flutter GUI and
the native Rust bridge.

## Supported Phase-1 Platforms

| Platform | Status | Rust bridge target | Native library form |
| --- | --- | --- | --- |
| Android | Supported | `armv7-linux-androideabi`, `aarch64-linux-android`, `i686-linux-android`, `x86_64-linux-android` | `jniLibs/<abi>/libpars_bridge.so` |
| iOS | Supported | `aarch64-apple-ios`, simulator targets where available | `pars_bridge.xcframework` static library |
| macOS | Supported | host `*-apple-darwin` target | `pars_bridge.framework` wrapping `libpars_bridge.dylib` |
| Windows | Supported | `x86_64-pc-windows-msvc` | `pars_bridge.dll` next to `pars_gui.exe` |
| Linux | Supported | host GNU Linux target | `lib/libpars_bridge.so` in the bundle |

## Build Scripts

- Android and Linux use [gui/bridge/build_unix.sh](../gui/bridge/build_unix.sh).
- iOS uses [gui/bridge/build_unix.sh](../gui/bridge/build_unix.sh) with the `ios` mode to create `pars_bridge.xcframework`.
- macOS uses [gui/macos/build_pars_bridge.sh](../gui/macos/build_pars_bridge.sh) from an Xcode build phase.
- Windows uses [gui/bridge/build_windows.ps1](../gui/bridge/build_windows.ps1), invoked from CMake.

## Crypto And Git Backends

Phase 1 keeps Git and OpenPGP as configured system backends:

- Git is invoked through the selected store path using the system `git` command.
- OpenPGP uses the configured `gpg` executable or the `PATH` default.
- Bundled OpenPGP/Git binaries are reserved for target-specific release work.
  Release packages that include bundled binaries must place them under the app
  resources directory, set the config backend path, and include their notices in
  [THIRD_PARTY_PACKAGING_NOTICES.md](THIRD_PARTY_PACKAGING_NOTICES.md).

The Settings runtime diagnostics sheet shows the bridge load state, core
version, native library stem, PGP backend, Git backend, and key storage backend
for installed builds.

## Smoke Checks

Release smoke checks should run the platform build, verify the native bridge
artifact exists in the expected bundle location, and then run Flutter widget
tests plus Rust workspace tests. CI records the same contract in
[GuiPackaging.yml](../.github/workflows/GuiPackaging.yml).
