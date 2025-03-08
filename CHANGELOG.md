# Pars Changelog

## [Unreleased]

### Addded

- Add changes to git staged area and commit after operation(for `init`, `generate`, `rm`, `cp`, `mv`, `edit`).
- Command `show` now support qr code generation and display.
- Documentation for `pars`.

### Changed

- Remove bundle pgp and bundle git support.
- Change show logic, only clip or generate qr code for the first line of the file if no line number is provided.

### Fixed

- Fix interactive operations input read (comformation for overwrite or delete). Now there's no need to input EOF to finish input.

## [0.1.0] - 2025-03-05

### Added

- Pass basic operations:
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
