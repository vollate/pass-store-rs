## 1. Widget Coverage

- [x] 1.1 Add failing Settings widget tests for store create/import/clone forms showing compact no-icon picker rows instead of editable local path fields.
- [x] 1.2 Add failing Settings widget tests for PGP/SSH key-file import showing a compact no-icon key-file picker row in the existing key import interface.
- [x] 1.3 Add failing Onboarding widget tests for store import/manual path flows using native folder picker rows instead of editable local path fields.
- [x] 1.4 Add widget tests that default paths are shown before selection and selected paths replace them after picker success.
- [x] 1.5 Add widget tests for picker cancellation and unsupported-picker errors keeping submit disabled.
- [x] 1.6 Add widget tests proving store-folder selection and key-file selection remain in separate existing forms/sheets.

## 2. Picker Infrastructure

- [x] 2.1 Add a Flutter path picker abstraction with folder and file selection methods, initial/base path input, cancellation, and unsupported/error reporting.
- [x] 2.2 Add or configure the native file/folder selector dependency in `gui/pubspec.yaml`.
- [x] 2.3 Implement the production path picker service using the platform-native selector package.
- [x] 2.4 Add fake picker support for widget tests to return selected paths, cancellation, and errors.
- [x] 2.5 Wire the picker service into app construction, Settings, and Onboarding without changing repository or bridge APIs.

## 3. Compact Picker Row

- [x] 3.1 Create a reusable compact no-icon picker row widget with title, `Default:` or `Selected:` path subtitle, and trailing Choose/Change action.
- [x] 3.2 Ensure long paths truncate cleanly without resizing forms or overflowing controls.
- [x] 3.3 Ensure row semantics expose the path label, current path, and picker action for tests and accessibility.

## 4. Settings Integration

- [x] 4.1 Replace Settings store create/import/clone editable local path fields with folder picker rows.
- [x] 4.2 For Settings create/clone, derive final target roots from the selected base folder plus store name or remote URL slug when needed.
- [x] 4.3 Replace Settings PGP/SSH key-file import editable path fields with file picker rows inside the existing key import flow.
- [x] 4.4 Keep Settings store-management forms and key-management import forms separate; only share reusable picker-row/service code.
- [x] 4.5 Keep submit disabled until required picker selections are available and route selected paths to existing repository calls.

## 5. Onboarding Integration

- [x] 5.1 Replace Onboarding store import/manual path fields with folder picker rows where a user-selected path is required.
- [x] 5.2 Preserve app-managed path derivation for Onboarding create/clone while showing the derived default path when relevant.
- [x] 5.3 For manual create/clone fallback, derive final target roots from the selected base folder plus store name or remote URL slug.
- [x] 5.4 Keep Onboarding steps and store setup flow unchanged except for native path selection UI.

## 6. Verification

- [x] 6.1 Run focused Settings and Onboarding widget tests covering native path picker flows.
- [x] 6.2 Run `flutter test`.
- [x] 6.3 Run `flutter analyze`.
- [x] 6.4 Run `openspec validate use-native-path-pickers --strict`.
