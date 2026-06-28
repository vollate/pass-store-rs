## Why

The current PGP and SSH key management sheets expose too many global actions at
the bottom of each sheet. Export and store-targeted actions operate on a
specific key, but the current layout makes them feel like sheet-level commands
and defaults them to the first key.

## What Changes

- Redesign both the PGP keys sheet and SSH keys sheet while keeping them as
  separate popups.
- Keep only key-creation and key-import entry points as sheet-level actions.
- Move key-specific actions into each key row's overflow menu:
  - PGP: export public, export private, add to `.gpg-id`, delete.
  - SSH: export public, export private, delete.
- Preserve existing create/import/delete/export behavior and confirmation
  flows; only change where actions are exposed and which key they target.
- Remove first-key default behavior for export and `.gpg-id` actions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-security-and-onboarding`: Settings key management sheets are
  reorganized so global actions are limited to create/import and per-key actions
  live in row overflow menus.

## Impact

- Affected UI: `gui/lib/screens/settings/settings_screen.dart`
- Affected tests: `gui/test/mobile_gui_smoke_test.dart`
- No bridge/core API changes expected.
