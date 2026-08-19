# Pars GUI Bridge

Milestone 2 uses `flutter_rust_bridge` v2.12.0 to generate the Dart/Rust bridge surface.
Milestone 3 adds FRB-compatible store lifecycle entrypoints for config inspection, first-run recovery, local store creation/import, Git clone, store selection, app-only removal, and strong-confirmation local deletion.

- Rust crate: `pars-bridge`
- Core dependency: `pars-core`
- CLI dependency: not allowed
- Rust API surface: `bridge/src/api.rs`
- Generated Dart API: `gui/lib/bridge/frb_generated/api.dart`
- App-facing Dart adapter: `gui/lib/bridge/pars_bridge_api.dart`

Build scripts in this directory compile the bridge crate for the major Flutter platform families:

- `build_unix.sh <android|ios|linux|macos>` for Unix-like build hosts.
- `build_windows.ps1` for Windows build hosts.

Android Gradle calls `build_unix.sh android` and passes the JNI output directory through `PARS_ANDROID_OUTPUT_DIR`. Platform packaging beyond bridge artifact compilation continues in the platform-packaging milestone.
Linux desktop CMake calls `build_unix.sh linux` during install and passes the final bundle `lib/` directory through `PARS_LINUX_OUTPUT_DIR`, which causes `libpars_bridge.so` to be copied next to `libflutter_linux_gtk.so`. This keeps `RustLib.init()` able to load `libpars_bridge.so` through the runner's `$ORIGIN/lib` RPATH.

## Autofill bridge contract

Autofill uses password-store paths as its default non-secret index source. For
`github.com/alice.gpg`, the immediate parent `github.com` is the Website/App
service and the filename stem `alice` is the Username. Rebuild, reconcile,
upsert, move, remove, and ranking-patch requests do not contain a PGP executable
or passphrase and never decrypt entries.

The candidate query ABI accepts `website`, human-readable `appName`, free-text
`query`, and `limit`. It does not accept or map Android package identifiers.
After platform authentication, credential resolution decrypts exactly the
selected indexed path and returns its first-line password with the path-derived
username.

Reading encrypted `url`, `website`, or `service` fields is a separate explicit
enrichment operation over a non-empty path selection. It stores normalized host
aliases only and commits them transactionally; it is never invoked by normal
index maintenance or credential resolution.
