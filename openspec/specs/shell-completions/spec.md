# shell-completions Specification

## Purpose

Document implemented shell completion generation, installation, and
uninstallation behavior.

## Requirements

### Requirement: CLI SHALL support completion actions for supported shells

The CLI SHALL expose `completion generate`, `completion install`, and
`completion uninstall`, each accepting an optional shell value. Supported shell
values SHALL be bash, zsh, fish, and PowerShell.

Sources: `cli/src/parser/sub_command.rs`, `cli/src/command/completion.rs`,
`cli/completion/`, `completion/`

#### Scenario: Generate action resolves shell

- WHEN `pars completion generate --shell bash` is called
- THEN bash completion content is printed to stdout
- AND usage guidance is printed to stderr

#### Scenario: Missing shell attempts detection

- WHEN no shell is supplied
- THEN `$SHELL` is checked for bash, zsh, or fish
- AND Windows or `$PSModulePath` selects PowerShell
- OTHERWISE an error requests `--shell`

### Requirement: Completion scripts SHALL be embedded in the CLI crate

The CLI completion command SHALL embed scripts from `cli/completion/` so the
published crate includes bash, zsh, fish, and PowerShell completion resources.

Sources: `cli/src/command/completion.rs`, `cli/completion/bash/pars.bash`,
`cli/completion/zsh/_pars`, `cli/completion/fish/pars.fish`,
`cli/completion/pwsh/ParsCompletion.psm1`,
`cli/completion/pwsh/ParsCompletion.psd1`

#### Scenario: Bash completion is embedded

- WHEN the CLI binary is built
- THEN bash completion content is included via `include_str!`

### Requirement: Install SHALL write completion files to shell-specific locations

Install SHALL create the required directory and write completion files to a
shell-specific path: bash-completion user data directory for bash, `~/.zfunc`
for zsh, fish completions config directory for fish, and a PowerShell module
directory for PowerShell.

Sources: `cli/src/command/completion.rs`

#### Scenario: Zsh install updates shell startup when needed

- WHEN zsh completion is installed
- THEN `_pars` is written under `~/.zfunc`
- AND `.zshrc` is appended with marked `fpath` and `compinit` lines when those
  lines are absent

#### Scenario: PowerShell install writes module files

- WHEN PowerShell completion is installed
- THEN `ParsCompletion.psm1` and `ParsCompletion.psd1` are written
- AND `Import-Module ParsCompletion` is appended to the profile when absent

### Requirement: Uninstall SHALL remove completion artifacts and marker lines

Uninstall SHALL remove shell-specific completion files. Zsh and PowerShell
uninstall SHALL remove profile lines containing the `# Added by pars completion`
marker.

Sources: `cli/src/command/completion.rs`

#### Scenario: Fish uninstall removes completion file

- WHEN fish completion is uninstalled
- THEN `pars.fish` is removed when present
- AND a message is printed when it is not installed

#### Scenario: Marker cleanup preserves unrelated profile lines

- WHEN zsh or PowerShell profile cleanup runs
- THEN only lines containing the pars completion marker are filtered out

## Needs Verification

- `cli/README.md` currently states only PowerShell completion is supported, but
  code and bundled completion files support bash, zsh, fish, and PowerShell.
  Documentation needs verification.
- Sync between repo-root `completion/` and crate-local `cli/completion/` is
  described in a code comment but not enforced by tests found during onboarding.
