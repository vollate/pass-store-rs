# PGP Backend Strategy

Milestone: 4, GPG/OpenPGP Backend Strategy and Packaging

## Decision

Pars will support PGP through a Rust `PgpBackend` trait. The first concrete backend is
the existing system `gpg` integration, with the same implementation also used for a
future bundled GnuPG path. Mobile should target a pure Rust OpenPGP backend first,
because it avoids subprocess and dynamic-linking constraints on mobile platforms.

The backend choices in config are:

- `system_gpg`: use an installed GnuPG executable.
- `bundled`: use an app-packaged GnuPG executable resolved from config or platform
  packaging.
- `pure_rust`: use the in-process Rust OpenPGP backend.

The first pure Rust implementation uses the `pgp` crate from
[rpgp/rpgp](https://github.com/rpgp/rpgp). This follows the same broad direction
as Android Password Store's move away from OpenKeychain and into an app-owned
OpenPGP backend, while keeping Pars' CLI/desktop default on system GnuPG.

The compatibility target remains existing `pass` stores: `.gpg-id` recipient
selection, armored key import/export, generated key support, and encrypted `.gpg`
entry read/write must keep interoperating with standard GnuPG.

## Platform Feasibility

- Android: prefer pure Rust OpenPGP first. Bundling GnuPG is possible only with
  per-ABI native artifacts, license notices, integrity checks, and a private
  writable `GNUPGHOME`.
- iOS: prefer pure Rust OpenPGP first. A subprocess-style GnuPG backend is not a
  good fit for app-store mobile packaging and sandbox constraints.
- macOS: bundled GnuPG is feasible inside the app bundle under resources, with
  runtime path resolution and a sandbox-compatible keyring directory.
- Windows: bundled GnuPG is feasible as application-local binaries, with runtime
  path resolution and integrity checks.
- Linux: bundled GnuPG is feasible per package format. AppImage/Flatpak need
  package-specific runtime path and writable-home handling; deb/rpm can depend on
  system packages or ship app-local binaries.

## Packaging Requirements For Bundled GnuPG

Bundled GnuPG remains a desktop packaging option. Before enabling it by default,
platform packaging must provide:

- Reproducible build scripts for every shipped binary target.
- GPL-compatible license notices for GnuPG and bundled dependencies.
- Binary integrity checks at startup or install time.
- Runtime executable path resolution.
- Sandbox-compatible keyring and home-directory handling through config.

## Pure Rust Backend Requirements

The pure Rust backend is the preferred mobile direction. Before it becomes the
default, it must pass compatibility tests for:

- Existing `pass` stores using `.gpg-id` recipient files.
- RSA and modern OpenPGP key algorithms used by current stores.
- Public and private key import/export.
- Fingerprint inspection matching GnuPG expectations.
- Decrypt/encrypt round trips against GnuPG-generated sample entries.

The first rPGP milestone intentionally implements the smallest pass-compatible
subset: app-owned key import/export/listing, fingerprint lookup, `.gpg-id`
recipient resolution, entry encryption, and entry decryption. Advanced OpenPGP
semantics such as revocation policy, Web of Trust, keyserver interaction,
smart cards, and GnuPG ownertrust are outside this milestone.

## Migration

Users who already have system GPG keep using `system_gpg` by default. When a
bundled or pure Rust backend is selected later, the app should import or reuse
the existing public/private keys only after explicit user confirmation. The
config keeps `system_gpg_path`, `bundled_gpg_path`, and `keyring_home` separate
so users can switch back without losing their existing GnuPG setup.
