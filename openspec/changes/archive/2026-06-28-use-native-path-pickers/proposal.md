## Why

Several Settings and Onboarding flows ask users to type filesystem paths by
hand. That feels rough on desktop, awkward on mobile, and makes it too easy to
submit invalid store roots or key-file paths when the platform can provide a
native chooser.

## What Changes

- Replace primary manual filesystem path inputs with platform-native file or
  folder selectors.
- Show a compact no-icon picker row in each affected form: label, default/base
  path, and a trailing Choose action.
- After selection, replace the default path display with the selected path and
  change the action label from Choose to Change.
- Keep store-folder selection and key-file selection in their existing separate
  Settings and Onboarding interfaces; do not merge them into one popup or form.
- Disable submit actions that require a path until a selector returns a path.
- Preserve existing repository and bridge APIs by passing the selected path
  string to the existing operations.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `flutter-security-and-onboarding`: Settings and Onboarding path-entry flows
  use native file/folder pickers with visible default and selected paths.

## Impact

- Affected Flutter UI: `gui/lib/screens/settings/settings_screen.dart` and
  `gui/lib/screens/onboarding/onboarding_screen.dart`.
- Likely new Flutter abstraction for path picking so widget tests can fake file
  and folder selection, cancellation, unsupported platforms, and base paths.
- Likely dependency impact in `gui/pubspec.yaml` for a cross-platform native
  file/folder selector package.
- Existing repository, bridge, and core APIs should remain unchanged.
