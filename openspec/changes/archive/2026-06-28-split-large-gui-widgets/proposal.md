## Why

Several Flutter UI files have grown large enough that routine changes require
holding too much unrelated UI state, form logic, and layout code in one place.
Splitting the largest hand-written screens into focused widgets will make the
GUI easier to review, test, and safely evolve without changing user-facing
behavior.

## What Changes

- Split oversized hand-written Flutter UI files into smaller widget modules with
  clear ownership boundaries.
- Keep top-level screen classes as orchestration points for repositories,
  callbacks, tabs, and route-level state.
- Move repeated sections, dialogs, sheets, form bodies, and row builders into
  private or reusable widgets under screen-local `widgets/` folders where
  appropriate.
- Preserve existing behavior, visible copy, semantics, navigation, repository
  calls, and test coverage.
- Leave generated bridge files and non-UI services out of scope.

## Capabilities

### New Capabilities

- `flutter-gui-composition`: Documents maintainability expectations for
  composing large Flutter GUI screens from focused widgets without behavior
  regressions.

### Modified Capabilities

- None.

## Impact

- Affected code: primarily `gui/lib/screens/settings/settings_screen.dart`,
  `gui/lib/screens/manage/manage_screen.dart`, and
  `gui/lib/screens/onboarding/onboarding_screen.dart`, plus new widget files
  beneath those screen directories.
- Affected tests: existing Flutter widget tests in `gui/test/` should continue
  to pass; focused tests may be adjusted only to account for widget extraction
  while preserving behavioral assertions.
- APIs/dependencies: no bridge API, repository API, route, or package dependency
  changes are expected.
