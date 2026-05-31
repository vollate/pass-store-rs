# pars-cli Changelog

## [0.2.0] - 2026-05-31

### Added

- Interactive fuzzy-search TUI: running `pars` with no subcommand opens an
  fzf-style interactive finder with live filtering, fzf-style tiered ranking
  (exact > contiguous substring > subsequence) with match-character
  highlighting, and lazy PGP decryption (only decrypts when an action that
  needs the plaintext is invoked).
- Per-entry action popup with Copy, Display, QR, Edit, and Regenerate.
- Generate / Insert new entries from inside the TUI (`Ctrl-G` / `Ctrl-N`)
  via a separate name-input popup, with overwrite confirmation when the
  entry already exists.
- Optional vim-mode bindings (`feature_config.vim_mode`): `Esc`/`i` to
  switch modes, `j/k`, `g/G`, `dd`/`D` to clear input, `Ctrl-U/D/F/B` for
  half/full page navigation.
- Mouse support: scroll, click to position cursor, double-click to open
  the action popup, click-outside-popup to dismiss.
- Dedicated full-screen Display view so terminal-native multi-line text
  selection only ever picks up password content (no border glyphs, no
  neighboring entry names).
- New config flags: `feature_config.fuzzy_search` (default on),
  `feature_config.vim_mode` (default off), `feature_config.exit_on_copy`
  (default off). Env overrides: `PARS_VIM_MODE`, `PARS_NO_FUZZY`.
- Multi-shell completion installer: `pars completion {install|uninstall|generate}`
  for bash / zsh / fish / PowerShell with auto-detection from `$SHELL`.

### Changed

- External-subcommand dispatch error message now identifies the failing
  command name (`Failed to execute external command 'name': ...`) so
  unknown shortcuts are obvious instead of producing a bare `os error 2`.
- Vim-like clean exit: terminal cleared, alternate screen left, mouse
  capture released, cursor restored.

### Fixed

- Windows ConPTY: drop non-`KeyEventKind::Press` events at the top of the
  TUI event loop so the Enter that launched the binary doesn't get
  re-delivered as a Release-then-Press and auto-select the first entry.
- Stdout corruption when launching external editors (`vim` / `nano`) or
  child commands (`generate`, `insert`) — alt-screen is torn down and
  re-entered with a full clear so child TUIs render correctly.
- Test (`pars-core`): portable BSD/GNU sed in the fake editor used by the
  edit integration test (was failing on macOS with "invalid command code f").

## [Unreleased]

### Added

- Support `getopt` like cli argument parsing.

### Changed

- Refactor fuction to lessen arguments and improve readability.

## [0.1.2] - 2025-04-25

### Added

- Add changes to git staged area and commit after operation(for `init`, `generate`, `rm`, `cp`, `mv`, `edit`).
- Command `show` now support qr code generation and display.
- Powershell, bash and zsh completion support.
- Homepage readme doc.

### Changed

- Remove bundle pgp and bundle git support. (Nologer scheduled for bundle support).
- Change `show` logic, only clip or generate qr code for the first line of the file if no line number is provided. (Original behavior is to show the whole file content).
- Change `insert` logic, now it will ask user to re-enter the password if the "--mutiline" flag is not provided.

### Fixed

- Fix interactive operations input read (comformation for overwrite or delete). Now there's no need to input EOF to finish input.
- Fix windows clipboard protential error.
- Fix generate operation file extension error.
- Fix grep command logic error.

## [0.1.0] - 2025-03-05

### Added

- Implement pass basic operations:
  - init
  - generate
  - show
  - ls
  - rm
  - cp
  - mv
  - edit
  - find
  - git
