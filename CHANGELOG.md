# Pars Changelog

## [Unreleased]

### Addded

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
