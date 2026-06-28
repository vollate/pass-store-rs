## Why

The Advanced git args sheet currently pre-fills `status`, so opening the sheet
looks like a command is already selected. This makes a risky/debug-oriented
control feel more automatic than it is and adds friction for users who want to
type another command.

## What Changes

- Start the Advanced git args input empty instead of pre-filled with `status`.
- Show dim example text, such as `status, log`, as a hint/placeholder rather
  than editable input content.
- Keep the existing command preview and validation behavior, but require actual
  user-entered arguments before running a command.
- Update widget coverage so the empty initial value and hint behavior are
  protected.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `git-integration`: Advanced Git args UI behavior changes from a pre-filled
  default command to an empty input with example placeholder text.

## Impact

- Affected UI: `gui/lib/screens/settings/settings_screen.dart`
- Affected tests: `gui/test/mobile_gui_smoke_test.dart`
- Affected specs: `openspec/specs/git-integration/spec.md`
