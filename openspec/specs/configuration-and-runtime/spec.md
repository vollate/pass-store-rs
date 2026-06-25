# configuration-and-runtime Specification

## Purpose

Document implemented configuration schema, defaults, environment overrides, and
runtime setup.

## Requirements

### Requirement: CLI config SHALL load from configured path or defaults

CLI startup SHALL determine the config path from `PARS_CONFIG_PATH`, falling
back to the platform default config path. If the file exists it SHALL load TOML
and apply selected environment overrides; if it does not exist it SHALL use
`ParsConfig::default()`.

Sources: `cli/src/main.rs`, `core/src/config/cli.rs`,
`core/src/util/fs_util.rs`, `core/src/constants.rs`

#### Scenario: Missing config file uses defaults

- GIVEN the resolved config path does not exist
- WHEN CLI startup processes configuration
- THEN `ParsConfig::default()` is used

#### Scenario: Existing invalid config exits

- GIVEN the resolved config path exists
- AND TOML loading fails
- WHEN CLI startup processes configuration
- THEN it prints a load failure
- AND exits with generic error

### Requirement: Config schema SHALL include print, path, executable, PGP, and feature sections

The config schema SHALL include `print_config`, `path_config`,
`executable_config`, `pgp_config`, and `feature_config` sections with defaults
matching generated sample config.

Sources: `core/src/config/cli.rs`, `config/cli/pars_config.toml`,
`core/tests/pgp_backend_test.rs`

#### Scenario: Default feature config is populated

- WHEN `ParsConfig::default()` is created
- THEN clip time is `45`
- AND fuzzy search is enabled
- AND vim mode is disabled
- AND exit-on-copy is disabled

#### Scenario: Config round-trips through TOML

- WHEN a default config is saved and loaded
- THEN the loaded config equals the original config

### Requirement: Environment overrides SHALL affect configured runtime features

After TOML loading, `PARS_CLIP_TIME`, `PARS_NO_FUZZY`, and `PARS_VIM_MODE` SHALL
override feature config values. `PARS_EDITOR` SHALL override the configured
editor for CLI edit command execution.

Sources: `core/src/config/cli.rs`, `cli/src/command/edit.rs`,
`core/src/constants.rs`

#### Scenario: Clip time zero disables clearing

- WHEN `PARS_CLIP_TIME` parses as `0`
- THEN `feature_config.clip_time` becomes `None`

#### Scenario: Vim mode env enables vim mode

- WHEN `PARS_VIM_MODE` is present
- THEN `feature_config.vim_mode` becomes `true`

### Requirement: Runtime defaults SHALL define executable paths and default password-store path

Default CLI config SHALL use `gpg2`, `git`, and `vim` on Unix or `notepad` on
Windows. Default path config SHALL use the user's home directory with
`.password-store`.

Sources: `core/src/constants.rs`, `core/src/config/cli.rs`,
`config/cli/pars_config.toml`

#### Scenario: Default repo points under home

- WHEN home directory is available
- THEN default repo is `<home>/.password-store`
- AND `repos` contains that same path

### Requirement: Flutter desktop runtime SHALL use system GPG from PATH by default

On non-mobile platforms, Flutter runtime configuration SHALL use the desktop
config path and diagnostics label `System GPG from PATH`, without overriding
the PGP executable.

Sources: `gui/lib/main.dart`, `gui/lib/services/mobile_pgp_backend.dart`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Non-mobile runtime returns desktop config path

- GIVEN runtime environment is non-mobile
- WHEN default PGP runtime is configured
- THEN returned config path is the supplied desktop config path
- AND the diagnostics label is `System GPG from PATH`

### Requirement: Flutter mobile runtime SHALL configure pure-rust OpenPGP under app support directory

On Android or iOS, Flutter runtime configuration SHALL create app support
directories for `pgp`, `ssh`, and `stores`, configure the bridge PGP backend as
`pure_rust`, and return diagnostics label `Pure Rust OpenPGP (rPGP)`.

Sources: `gui/lib/services/mobile_pgp_backend.dart`,
`bridge/src/api.rs`, `gui/test/bridge_backed_repository_test.dart`

#### Scenario: Mobile runtime prepares app support directories

- GIVEN runtime environment is mobile
- WHEN default PGP runtime is configured
- THEN `<support>/pgp`, `<support>/ssh`, and `<support>/stores` are created
- AND bridge `configure_pgp_backend` is called with backend `pure_rust`

### Requirement: Project tooling config SHALL constrain bridge generation

Bridge tooling config SHALL use `flutter_rust_bridge` v2.12.0, define
`bridge/src/api.rs` as Rust entrypoint, define generated Rust/Dart outputs, and
state that `pars-bridge` depends on `pars-core` and must not depend on
`pars-cli`.

Sources: `gui/bridge/bridge_config.toml`, `bridge/Cargo.toml`,
`gui/lib/bridge/pars_bridge_api.dart`

#### Scenario: Bridge method list is declared in tooling config

- WHEN bridge tooling config is read
- THEN it lists the generated bridge methods exposed to Dart

## Needs Verification

- CLI uses `PARS_CONFIG_PATH`; Flutter `BridgeBackedRepository.defaultConfigPath`
  reads `PARS_CONFIG`. The intended environment variable naming consistency
  needs verification.
- `feature_config.exit_on_copy` exists in config but no current behavior was
  found during onboarding. Its intended status needs verification.
