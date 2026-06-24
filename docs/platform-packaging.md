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

Phase 1 keeps Git as a configured system backend and uses pure Rust OpenPGP on
mobile:

- Git is invoked through the selected store path using the system `git` command.
- CLI and desktop PGP operations use GnuPG (`gpg`) through the existing
  external-command backend by default.
- Android and iOS use the `pure_rust` backend built on the rPGP `pgp` crate.
  This avoids mobile subprocess and dynamic-linking constraints.
- Bundled GnuPG is a fallback packaging route for desktop or specialist builds,
  not the mobile default.
- Release packages that include bundled binaries must include their exact
  version, source URL, license, and packaged path in
  [THIRD_PARTY_PACKAGING_NOTICES.md](THIRD_PARTY_PACKAGING_NOTICES.md).

The Settings runtime diagnostics sheet shows the bridge load state, core
version, native library stem, PGP backend, Git backend, and key storage backend
for installed builds.

## Smoke Checks

Release smoke checks should run the platform build, verify the native bridge
artifact exists in the expected bundle location, and then run Flutter widget
tests plus Rust workspace tests. CI records the same contract in
[GuiPackaging.yml](../.github/workflows/GuiPackaging.yml). Android release
qualification also includes installing the debug or release APK on a physical
arm64 device, launching `top.vollate.pars_gui`, and checking the app PID log for
startup crashes.
