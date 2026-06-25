# cli-command-surface Specification

## Purpose

Document the implemented `pars` CLI command surface and command routing.

## Requirements

### Requirement: CLI command parser SHALL expose pass-compatible subcommands

The CLI SHALL expose subcommands for initializing, listing/showing, inserting,
editing, generating, removing, finding, grepping, copying, moving, Git
passthrough, completion, and external commands.

Sources: `cli/src/parser/sub_command.rs`, `cli/src/parser/mod.rs`,
`cli/src/main.rs`, `cli/tests/pars_test.rs`

#### Scenario: Help is available

- WHEN `pars --help` is executed
- THEN the process exits successfully
- AND stdout contains `Usage:`

#### Scenario: Aliases route to the same command variant

- WHEN the parser receives `find` or `search`
- THEN it routes to the find command
- AND when it receives `ls` or `list`
- THEN it routes to the list command
- AND when it receives `insert` or `add`
- THEN it routes to the insert command
- AND when it receives `rm`, `remove`, or `delete`
- THEN it routes to the remove command
- AND when it receives `mv` or `rename`
- THEN it routes to the move command
- AND when it receives `cp` or `copy`
- THEN it routes to the copy command

### Requirement: CLI SHALL support global repository selection

The CLI SHALL accept global `-R` / `--repo` and use that path as the password
store root when present; otherwise it SHALL use `path_config.default_repo` from
the loaded configuration.

Sources: `cli/src/parser/mod.rs`, `cli/src/util.rs`,
`core/src/config/cli.rs`

#### Scenario: Global repo overrides config default

- GIVEN a command is parsed with `--repo <path>`
- WHEN the command wrapper resolves the root path
- THEN `<path>` is used as the command root

#### Scenario: No global repo uses configured default

- GIVEN a command has no `--repo`
- WHEN the command wrapper resolves the root path
- THEN `config.path_config.default_repo` is used as the command root

### Requirement: CLI SHALL normalize entry paths before command execution

For commands that accept password entry paths, the CLI SHALL remove leading `/`
and `\` characters before invoking command handlers.

Sources: `cli/src/parser/mod.rs`, `cli/src/util.rs`

#### Scenario: Absolute-looking entry path becomes store-relative

- WHEN an entry path starts with `/` or `\`
- THEN leading separators are stripped
- AND the normalized path is passed to insert, edit, generate, remove, move,
  copy, list, or show handlers as applicable

### Requirement: CLI SHALL preprocess optional clip and QR line arguments

The CLI SHALL accept `-c<num>` and `-q<num>` forms and convert them to
`-c=<num>` / `-q=<num>`. It SHALL also convert `-c <num>` and `-q <num>` when
the next token is numeric, while preserving non-numeric positional arguments.

Sources: `cli/src/main.rs`, `cli/src/parser/sub_command.rs`,
`cli/src/command/ls.rs`

#### Scenario: Numeric short flag suffix is accepted

- WHEN the raw argv contains `-c2` or `-q3`
- THEN the parser receives `-c=2` or `-q=3`

#### Scenario: Missing line number defaults to first line

- WHEN `--clip` or `--qrcode` is supplied without a value
- THEN clap uses line number `1`
- AND command handling treats line number `0` as line number `1`

### Requirement: CLI SHALL define fallback behavior when no subcommand is supplied

When no subcommand is supplied, the CLI SHALL run an external shell command if
trailing args exist. If no trailing args exist, it SHALL run interactive fuzzy
search when `feature_config.fuzzy_search` is true; otherwise it SHALL list the
password store.

Sources: `cli/src/parser/mod.rs`, `cli/src/fuzzy/mod.rs`,
`cli/src/command/shell.rs`

#### Scenario: No subcommand with trailing args runs external command

- GIVEN the parsed CLI has no subcommand
- AND trailing args are present
- WHEN command dispatch executes
- THEN the first trailing arg is used as the program
- AND remaining trailing args are passed as its arguments
- AND the command runs with the password store as current directory

#### Scenario: No subcommand without args uses configured fallback

- GIVEN the parsed CLI has no subcommand
- AND no trailing args exist
- WHEN `feature_config.fuzzy_search` is true
- THEN interactive fuzzy search is started
- WHEN `feature_config.fuzzy_search` is false
- THEN the password store is listed

### Requirement: CLI SHALL map command errors to documented exit code categories

The CLI SHALL print command errors to stderr, log debug error details, and exit
with the command-supplied `ParsExitCode` conversion.

Sources: `cli/src/main.rs`, `cli/src/constants.rs`, command wrappers under
`cli/src/command/`

#### Scenario: Config load failure exits as generic error

- GIVEN the configured config path exists
- AND loading that config fails
- WHEN CLI startup processes the config
- THEN it prints `Failed to load config file`
- AND exits with `ParsExitCode::Error`

## Needs Verification

- End-to-end tests are sparse for command aliases and most subcommands; many
  command surface facts are currently sourced from parser and command-wrapper
  code.
- External command behavior is implemented through clap external subcommands and
  the no-subcommand trailing-args branch, but shell quoting behavior is not
  covered by tests.
