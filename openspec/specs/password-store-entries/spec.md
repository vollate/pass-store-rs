# password-store-entries Specification

## Purpose

Document implemented behavior for pass-compatible password store entries and
entry mutations.

## Requirements

### Requirement: Entries SHALL be stored as encrypted `.gpg` files

Password entries SHALL be addressed by store-relative paths and stored on disk
as `<entry>.gpg` files. Directory entries SHALL be represented by filesystem
directories.

Sources: `core/src/operation/insert.rs`, `core/src/operation/generate.rs`,
`core/src/operation/ls_or_show.rs`, `core/src/gui/mod.rs`,
`core/tests/gui_api_test.rs`

#### Scenario: GUI list returns password files without suffix

- GIVEN a store contains `work/dev/github.gpg`
- WHEN GUI `list_entries` is called recursively
- THEN the returned entry path is `work/dev/github`
- AND the entry type is `Password`

#### Scenario: CLI tree output strips `.gpg` suffix

- GIVEN the CLI lists a directory tree
- WHEN `.gpg` files are printed
- THEN the `.gpg` suffix is removed from printed entry names

### Requirement: Entry path validation SHALL prevent store escape

Core entry operations SHALL reject paths that escape the selected password store
root. GUI entry references SHALL reject parent components, root components, and
platform prefixes.

Sources: `core/src/util/fs_util.rs`, `core/src/operation/copy_or_rename.rs`,
`core/src/gui/mod.rs`, `core/tests/gui_api_test.rs`

#### Scenario: Parent traversal is rejected

- WHEN a GUI entry reference is created for `../outside`
- THEN creation fails with an outside-password-store validation error

#### Scenario: Copy or rename cannot target parent directories

- WHEN copy or rename receives a source or destination outside the root
- THEN the operation returns an error

### Requirement: Insert SHALL encrypt user-supplied content for nearest recipients

Insert SHALL create missing parent directories, read password content from
stdin, validate confirmation for single-line mode, optionally echo the password,
resolve recipients from the nearest `.gpg-id`, and encrypt the content.

Sources: `core/src/operation/insert.rs`, `cli/src/command/insert.rs`,
`core/src/util/fs_util.rs`, `core/tests/gui_api_test.rs`

#### Scenario: Single-line insert requires matching confirmation

- GIVEN insert is not in multiline mode
- WHEN the entered password and confirmation differ
- THEN the insert returns `false`
- AND the password file is not written

#### Scenario: Insert creates parent directories

- GIVEN an entry path `work/dev/github`
- WHEN GUI insert saves the entry
- THEN `work/dev/github.gpg` exists
- AND missing parent directories are created

#### Scenario: Insert requires explicit overwrite in GUI

- GIVEN `github.gpg` already exists
- WHEN GUI insert is called with `overwrite=false`
- THEN it returns an `EntryAlreadyExists` conflict

### Requirement: Generate SHALL create and save generated passwords

Generate SHALL create passwords with requested length, lowercase letters,
uppercase letters, numbers, optional symbols, no spaces, strict generation, and
similar-character exclusion. CLI generation SHALL default to length 20 when no
length is supplied.

Sources: `core/src/operation/generate.rs`, `cli/src/command/generate.rs`,
`cli/src/constants.rs`, `core/tests/gui_api_test.rs`

#### Scenario: GUI generate saves requested password shape

- WHEN GUI generate is called with length `24` and `no_symbols=true`
- THEN the returned password length is `24`
- AND every character is ASCII alphanumeric
- AND the encrypted entry file is saved

#### Scenario: CLI generate can replace only the first line

- GIVEN an existing multi-line entry
- WHEN CLI generate is called with `--in-place`
- THEN only the first line is replaced
- AND following lines are preserved

### Requirement: Read and parse SHALL treat the first line as password

Entry parsing SHALL use the first line as the password. Following lines SHALL be
parsed as known metadata fields when they use a supported `key: value` format;
unknown or non-empty unparsable lines SHALL be preserved as raw notes.

Sources: `core/src/gui/mod.rs`, `gui/lib/services/pass_entry_parser.dart`,
`core/tests/gui_api_test.rs`, `gui/test/pass_entry_parser_test.dart`

#### Scenario: Known fields are parsed

- GIVEN plaintext contains `username: alice` and `url: https://example.com`
- WHEN the entry is parsed
- THEN `username` and `url` are returned as structured fields

#### Scenario: Unknown metadata is preserved

- GIVEN plaintext contains `project=demo`
- WHEN the entry is parsed
- THEN it is included in `raw_notes`

### Requirement: Edit SHALL re-encrypt changed content and preserve original on encryption failure

CLI edit SHALL decrypt to a temporary plaintext file, invoke the configured
editor, compare old and new content, and re-encrypt only when content changed.
When re-encryption fails after backup creation, it SHALL restore the backup.

Sources: `core/src/operation/edit.rs`, `cli/src/command/edit.rs`

#### Scenario: Unchanged edit does not require commit

- GIVEN the editor exits successfully
- AND the plaintext content is unchanged
- WHEN CLI edit completes
- THEN it returns `false`
- AND the command wrapper skips the Git commit

#### Scenario: Changed edit writes encrypted content

- GIVEN the editor changes plaintext content
- WHEN CLI edit completes successfully
- THEN the entry is encrypted back to the original `.gpg` path
- AND the command wrapper commits the update

### Requirement: Move, copy, and delete SHALL handle overwrite and recursive rules

Move and copy SHALL operate on files or directories, prompt before overwriting
unless forced in CLI operations, and support re-encryption when moving/copying a
GPG file between directories with different `.gpg-id` recipients. Delete SHALL
remove files directly and require explicit recursive mode for directories.

Sources: `core/src/operation/copy_or_rename.rs`,
`core/src/operation/remove.rs`, `core/src/gui/mod.rs`,
`core/tests/gui_api_test.rs`

#### Scenario: GUI move rejects destination conflict without overwrite

- GIVEN `archive/github.gpg` already exists
- WHEN GUI move targets `archive/github` with `overwrite=false`
- THEN it returns an `EntryAlreadyExists` conflict
- AND the source and destination files remain present

#### Scenario: GUI delete requires recursive for directories

- GIVEN an entry path refers to a directory
- WHEN GUI delete is called with `recursive=false`
- THEN it returns a validation error mentioning `recursive=true`
- AND the directory remains present

#### Scenario: CLI remove force ignores missing entry

- GIVEN the requested entry does not exist
- WHEN CLI remove is called with force
- THEN it prints `Noting to remove`
- AND returns successfully

### Requirement: Flutter single-entry deletion SHALL use human-readable confirmation

The Flutter manage UI SHALL require confirmation before deleting one password
entry, but the typed confirmation SHALL use the entry's human-readable display
label rather than the full password-store path. The full path SHALL remain
visible as read-only context so the user can verify the target without typing
the entire path.

Sources: `gui/lib/screens/manage/widgets/manage_single_entry_widgets.dart`,
`gui/lib/screens/manage/manage_screen.dart`, `gui/test/mobile_gui_smoke_test.dart`

#### Scenario: Single-entry delete confirms by display label

- GIVEN the selected entry path is `work/accounts/github`
- AND the entry display label is `github`
- WHEN the user types `github` in the delete confirmation field
- THEN the delete action is allowed for `work/accounts/github`

#### Scenario: Single-entry delete does not require full path input

- GIVEN the selected entry path is `work/accounts/github`
- WHEN the delete confirmation sheet renders
- THEN the required typed confirmation text is `github`
- AND the full path `work/accounts/github` is displayed only as target context

#### Scenario: Incorrect single-entry delete confirmation blocks deletion

- GIVEN a single-entry delete confirmation sheet is open
- WHEN the user enters text that does not match the selected entry display label
- THEN the delete action is not submitted
- AND the UI shows the expected human-readable confirmation text

## Needs Verification

- CLI directory listing can include non-`.gpg` files in tree output, while GUI
  listing returns only directories and `.gpg` password files. The intended
  compatibility boundary needs verification.
- CLI re-encryption during copy/move currently creates PGP clients with the
  literal executable `gpg` instead of the configured PGP executable. Intended
  behavior needs verification.
- GUI move currently renames encrypted files without re-encrypting for different
  destination `.gpg-id` recipients. Intended parity with CLI copy/move needs
  verification.
