# Third-Party Packaging Notices

Pars is GPL-3.0-or-later. Phase-1 GUI packages use system Git and system GPG by
default, so no Git or GPG binaries are bundled by the app today.

When a release package bundles a crypto or Git component, add the exact package
name, version, source URL, license, and local install path here before shipping.

## Runtime Components

| Component | Bundled | License | Notes |
| --- | --- | --- | --- |
| pars-core / pars-bridge | Yes | GPL-3.0-or-later | Built from this repository into the Flutter app bundle. |
| Git | No | GPL-2.0-only | Resolved from the platform `PATH` in phase 1. |
| GnuPG / OpenPGP backend | No | GPL family | Resolved from configured path or platform `PATH` in phase 1. |
| Flutter plugins | Yes | See package licenses | Managed through `pubspec.lock`. |
