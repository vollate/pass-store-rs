## 1. Widget Coverage

- [x] 1.1 Add failing Settings widget tests that PGP and SSH key sheets remain separate and do not show the other key type.
- [x] 1.2 Add failing Settings widget tests that sheet-level actions for both PGP and SSH are limited to Create and Import.
- [x] 1.3 Add failing Settings widget tests that PGP row menus expose Export public, Export private, Add to `.gpg-id`, and Delete for the selected key.
- [x] 1.4 Add failing Settings widget tests that SSH row menus expose Export public, Export private, and Delete for the selected key.
- [x] 1.5 Update existing deletion/export/import tests to use the redesigned per-key menus and the consolidated Import entry point.

## 2. Settings Sheet Redesign

- [x] 2.1 Refactor key sheet rendering so PGP and SSH still open as separate bottom sheets while sharing row/menu helpers where practical.
- [x] 2.2 Replace the bottom action cluster with only Create and Import sheet-level actions.
- [x] 2.3 Move PGP Export public, Export private, Add to `.gpg-id`, and Delete into each PGP key row overflow menu.
- [x] 2.4 Move SSH Export public, Export private, and Delete into each SSH key row overflow menu.
- [x] 2.5 Route all moved actions through the selected key rather than `keys.first`.
- [x] 2.6 Consolidate text/file import behind the Import entry point without changing repository APIs.
- [x] 2.7 Remove GitHub settings from the redesigned SSH key sheet.

## 3. Verification

- [x] 3.1 Run focused Settings widget tests covering PGP/SSH key sheet actions.
- [x] 3.2 Run `flutter analyze`.
- [x] 3.3 Run `openspec validate redesign-key-management-sheets --strict`.
