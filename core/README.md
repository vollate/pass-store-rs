# pars-core

Core library for Pars, a cross-platform [pass](https://www.passwordstore.org/)
compatible password manager. Provides encrypted store operations, system-GnuPG
and pure-Rust OpenPGP APIs, SSH key management, GUI-oriented entry/Git APIs,
and autofill indexing.

```toml
[dependencies]
pars-core = "0.3.0"
```

## Backends and requirements

Existing `PGPClient` operations use an external GnuPG-compatible executable.
Library consumers can explicitly construct `pgp::rpgp_backend::RpgpBackend`
and use backend-aware APIs instead. Its configured `keyring_home` has separate
`public/` and `private/` armored-key directories: it does not automatically read
an existing GnuPG keyring. Import keys explicitly. Crypto/SSH dependencies are
currently unconditional even with default features disabled.

Git operations require Git; clipboard operations require the applicable system
clipboard tools. The CLI continues to use system GnuPG, not the pure-Rust backend.
Workspace dependency optimization profiles do not propagate to downstream
consumers; choose appropriate build profiles for cryptographic workloads.

The release lockfile includes dependencies requiring Rust 1.88. This is a
dependency floor, **not a build-verified MSRV**; development/CI uses nightly.

## Upgrading from 0.2

See [CHANGELOG.md](CHANGELOG.md) for the breaking Rust API change and the
canonical-store configuration migration. Back up multi-store configuration
and explicitly select the intended default store before upgrading.

## Tests (including the published source archive)

`cargo test --locked` runs unit, integration, and documentation tests without
requiring a self dev-dependency or a feature flag. `test-util` remains available
for workspace consumers such as the bridge, but is not a stable application API.

Run tests only with disposable configuration, stores and a temporary
`GNUPGHOME` (mode `0700`), never a personal keyring. GnuPG and Git must be on PATH.
Enable the opt-in GnuPG interoperability cases with:

```sh
PARS_RUN_GPG_INTEROP=1 cargo test --locked
cargo test --locked --features test-util
```

Some legacy interactive/desktop tests are ignored; inspect their requirements
before explicitly running them. Do not enable desktop clipboard tests against
real clipboard data during release validation.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE).
