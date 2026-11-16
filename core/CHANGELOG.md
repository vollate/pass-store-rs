# pars-core Changelog

## [0.3.0] - Unreleased

Changes since the published `pars-core 0.2.5`.

### Added

- Pure-Rust OpenPGP backend, key import/inspection/export and private-key
  protection APIs, alongside the existing system-GnuPG backend.
- SSH key management, GUI-oriented entry and Git APIs, and autofill index APIs.

### Breaking changes and migration

- `ParsConfig` has a new public `pgp_config` field. Add
  `pgp_config: Default::default()` to exhaustive struct literals, use
  `..Default::default()` where appropriate, and add `..` to exhaustive patterns
  that do not need the new field. Old TOML without this field still loads.
- Store configuration is normalized to one canonical store. A nonempty
  `path_config.default_repo` wins; otherwise the first nonempty `repos` entry
  wins. `repos` becomes a zero-or-one-entry compatibility mirror. Loading
  normalizes in memory; saving persists the removal of other registrations.
  Store directories and passwords are **not deleted**. Back up multi-store
  configuration and explicitly set the intended `default_repo` before migration.
- Configuration saves atomically replace the destination. Callers relying on
  symlink-following writes or preservation of existing file metadata should
  review this behavior.

### Changed and fixed

- Recipient-file (`.gpg-id`) read errors propagate from the recipient lookup
  helper instead of silently falling back; callers may still handle errors.
- File `mv`/`cp` operations create missing destination parent directories.
- Dependencies include `pgp 0.20`, `rand 0.10`, and `toml 1.1`. The locked
  dependency floor is Rust 1.88; this is not a verified MSRV.
- Source distributions include README and GPL license text. Integration tests
  no longer rely on a path-only self dev-dependency stripped by Cargo packaging.

### Scope and limitations

The pure-Rust backend is a library capability, not a CLI backend replacement.
Setting `pgp_config.backend = "pure_rust"` does not switch CLI operations;
they still use `executable_config.pgp_executable`. The pure-Rust keyring is
separate from GnuPG and requires explicit key import. Default features being
empty does not make crypto/SSH dependencies optional.

GUI/mobile changes in `bridge/` and `gui/` are not all shipped by this crate.
Android manual device testing for `strengthen-git-sync` task 10.3 remains
unfinished and unverified; this release does not claim otherwise.
