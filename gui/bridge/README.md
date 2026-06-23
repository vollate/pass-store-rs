# Pars GUI Bridge

Milestone 2 uses `flutter_rust_bridge` v2.12.0 to generate the Dart/Rust bridge surface.
Milestone 3 adds FRB-compatible store lifecycle entrypoints for config inspection, first-run recovery, local store creation/import, Git clone, store selection, app-only removal, and strong-confirmation local deletion.

- Rust crate: `pars-bridge`
- Core dependency: `pars-core`
- CLI dependency: not allowed
- Rust API surface: `bridge/src/api.rs`
- Generated Dart API: `gui/lib/bridge/frb_generated/api.dart`
- App-facing Dart adapter: `gui/lib/bridge/pars_bridge_api.dart`

Build scripts in this directory compile the bridge crate for the major Flutter platform families. Platform packaging and artifact copying continue in the platform-packaging milestone.
