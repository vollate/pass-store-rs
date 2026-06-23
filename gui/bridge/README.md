# Pars GUI Bridge

Milestone 2 uses a handwritten Dart FFI-compatible bridge surface instead of generated `flutter_rust_bridge` code.

- Rust crate: `pars-bridge`
- Core dependency: `pars-core`
- CLI dependency: not allowed
- C ABI entrypoints: `pars_bridge_call` and `pars_bridge_free_string`
- Dart API surface: `gui/lib/bridge/pars_bridge_api.dart`

Build scripts in this directory compile the bridge crate for the major Flutter platform families. Platform packaging and artifact copying continue in the platform-packaging milestone.
