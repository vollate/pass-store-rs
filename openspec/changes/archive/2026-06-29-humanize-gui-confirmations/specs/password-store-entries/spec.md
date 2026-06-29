## ADDED Requirements

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
