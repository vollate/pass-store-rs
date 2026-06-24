# Third-Party Packaging Notices

Pars is GPL-3.0-or-later. Phase-1 GUI packages use system Git by default.
Mobile GUI packages use the Rust bridge and the rPGP `pgp` crate for in-process
OpenPGP. CLI and desktop builds keep system GnuPG as the default PGP backend.

When a release package bundles a crypto or Git component, add the exact package
name, version, source URL, license, and local install path here before shipping.

## Runtime Components

| Component | Bundled | License | Notes |
| --- | --- | --- | --- |
| pars-core / pars-bridge | Yes | GPL-3.0-or-later | Built from this repository into the Flutter app bundle. |
| rPGP `pgp` crate | Yes | MIT OR Apache-2.0 | Pure Rust OpenPGP backend for Android and iOS. Version is recorded in `Cargo.lock`. |
| Git | No | GPL-2.0-only | Resolved from the platform `PATH` in phase 1. |
| GnuPG (`gpg`) | No | GPL-3.0-or-later plus dependencies | Used through the system executable on CLI and desktop by default. |
| Flutter plugins | Yes | See package licenses | Managed through `pubspec.lock`. |
