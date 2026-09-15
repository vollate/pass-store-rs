## MODIFIED Requirements

### Requirement: Config schema SHALL include print, path, executable, PGP, and feature sections

The config schema SHALL include `print_config`, `path_config`, `executable_config`, `pgp_config`, and `feature_config` sections with defaults matching generated sample config. `path_config.default_repo` SHALL be the canonical configured password-store path. During the compatibility window, `path_config.repos` SHALL contain either no paths or exactly the canonical path and SHALL NOT act as a GUI-visible store registry.

Sources: `core/src/config/cli.rs`, `config/cli/pars_config.toml`, `core/tests/pgp_backend_test.rs`

#### Scenario: Default feature config is populated

- **WHEN** `ParsConfig::default()` is created
- **THEN** clip time is `45`
- **AND** fuzzy search is enabled
- **AND** vim mode is disabled
- **AND** exit-on-copy is disabled

#### Scenario: Config round-trips through TOML

- **WHEN** a default config is saved and loaded
- **THEN** the loaded config equals the original config
- **AND** `repos` contains at most the canonical `default_repo`

#### Scenario: Legacy multi-store config chooses only the prior default

- **GIVEN** a legacy config has a non-empty `default_repo` and multiple `repos`
- **WHEN** GUI configuration is normalized
- **THEN** `default_repo` remains the canonical path
- **AND** the compatibility `repos` mirror becomes `[default_repo]` on the next successful config write
- **AND** no other configured directory is deleted

#### Scenario: Legacy empty default can recover one path

- **GIVEN** a legacy config has an empty `default_repo`
- **AND** `repos` contains at least one non-empty path
- **WHEN** GUI configuration is normalized
- **THEN** the first non-empty legacy path becomes the canonical path
- **AND** no second path becomes selectable in the GUI

### Requirement: Runtime defaults SHALL define executable paths and default password-store path

Default CLI config SHALL use `gpg2`, `git`, and `vim` on Unix or `notepad` on Windows. Default path config SHALL use the user's home directory with `.password-store` as the canonical store. The compatibility `repos` mirror SHALL contain that same path and SHALL NOT imply multi-store GUI behavior.

Sources: `core/src/constants.rs`, `core/src/config/cli.rs`, `config/cli/pars_config.toml`

#### Scenario: Default store points under home

- **WHEN** the home directory is available
- **THEN** `default_repo` is `<home>/.password-store`
- **AND** `repos` contains only that same path

#### Scenario: CLI explicit repository override remains available

- **GIVEN** config contains one canonical password store
- **WHEN** the CLI receives `-R/--repo <path>`
- **THEN** the command uses the explicit path for that invocation
- **AND** the GUI canonical store is not changed
