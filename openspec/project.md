# Pars OpenSpec Onboarding

Pars is a cross-platform `zx2c4-pass` compatible password manager. The current
repository contains a Rust workspace for the core library, CLI, and native
Flutter bridge, plus a Flutter GUI package.

## Scope

This onboarding records behavior that is already implemented in the current
codebase. It does not define future behavior or modify business code.

Primary evidence was extracted from:

- `README.md` and `cli/README.md`
- Rust workspace manifests: `Cargo.toml`, `core/Cargo.toml`,
  `cli/Cargo.toml`, `bridge/Cargo.toml`
- Flutter manifest and config: `gui/pubspec.yaml`,
  `gui/analysis_options.yaml`, `gui/bridge/bridge_config.toml`
- CLI parser and command wrappers under `cli/src/`
- Core operations, PGP, Git, GUI-facing APIs, and key management under
  `core/src/`
- Native bridge API under `bridge/src/api.rs`
- Flutter services, models, app shell, onboarding, vault, manage, and settings
  screens under `gui/lib/`
- Tests under `cli/tests/`, `core/tests/`, `bridge/tests/`, and `gui/test/`

## Tech Stack

- Rust workspace with crates `pars-core`, `pars-cli`, and `pars-bridge`.
- Flutter GUI package `pars_gui`.
- `flutter_rust_bridge` v2.12.0 for native bridge generation.
- System GnuPG, bundled GnuPG, and pure Rust OpenPGP backend configuration
  paths exist in code; CLI operations primarily call a configured system GPG
  executable.
- Git integration shells out to the configured Git executable in the CLI and to
  `git` in GUI-facing core/bridge code.

## Suggested Capability Directory

```text
openspec/specs/
  cli-command-surface/
    spec.md
  password-store-entries/
    spec.md
  pgp-and-key-management/
    spec.md
  git-integration/
    spec.md
  configuration-and-runtime/
    spec.md
  shell-completions/
    spec.md
  native-bridge-api/
    spec.md
  flutter-vault-and-manage/
    spec.md
  flutter-security-and-onboarding/
    spec.md
  store-lifecycle/
    spec.md
```

## Capability Map

- `cli-command-surface`: CLI parsing, aliases, global repo selection, default
  behavior, path normalization, and user-facing command routing.
- `password-store-entries`: pass-compatible `.gpg` entry storage, listing,
  reading, parsing, insert/generate/edit/move/copy/delete behavior.
- `pgp-and-key-management`: GPG/rPGP backend configuration, `.gpg-id`
  recipient validation, PGP key lifecycle, SSH key lifecycle, and key import
  detection.
- `git-integration`: automatic CLI commits, explicit CLI Git passthrough,
  bridge Git command validation, GUI Git operations, and remote parsing.
- `configuration-and-runtime`: config schema, defaults, environment overrides,
  executable selection, Flutter runtime defaults, and mobile pure-rust setup.
- `shell-completions`: completion script generation, installation, and
  uninstallation for supported shells.
- `native-bridge-api`: typed Flutter/Rust bridge request/response API surface
  and bridge failure mapping.
- `flutter-vault-and-manage`: Flutter repository-backed vault browsing, search,
  recent/favorite metadata, entry detail, and manage workflows.
- `flutter-security-and-onboarding`: local lock, gesture verifier, biometrics,
  PGP passphrase session/cache, and onboarding flow.
- `store-lifecycle`: GUI/bridge password store discovery, create/import/clone,
  selection, removal, deletion, and app-state issue reporting.

## Needs Verification

- There are no HTTP routes or web server routes in the current repository.
  OpenSpec "routes" for this onboarding are interpreted as CLI commands,
  Flutter app screens, and Flutter/Rust bridge methods.
- CLI tests currently provide limited command-level assertions. Many CLI
  behaviors are documented from parser, command wrapper, operation, and core
  tests rather than end-to-end CLI tests.
- `cli/README.md` says only PowerShell completion is supported, but code and
  bundled files implement bash, zsh, fish, and PowerShell completion support.
- Flutter entry detail includes visible Edit, Regenerate, and Delete buttons
  whose callbacks are currently no-ops in `gui/lib/screens/vault/entry_detail_sheet.dart`.
- The gesture verifier is a compact local verifier, not a documented
  cryptographic password hash. Its intended security strength needs review.
- Pure Rust OpenPGP is configured for mobile runtime and covered by tests, but
  broader compatibility with existing GnuPG-managed stores needs more
  verification.
