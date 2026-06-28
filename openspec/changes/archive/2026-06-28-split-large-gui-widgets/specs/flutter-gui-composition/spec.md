## ADDED Requirements

### Requirement: Flutter GUI SHALL compose large screens from focused widgets

Hand-written Flutter GUI screens SHALL be composed from focused widget modules
when a screen file contains multiple independent UI domains such as sections,
sheets, dialogs, forms, or repeated row renderers. The top-level screen file
SHALL remain responsible for route-level state, repositories, callbacks, and
cross-widget orchestration, while extracted widgets SHALL own only the local UI
state and callbacks needed for their specific surface. Generated bridge files
are excluded from this composition requirement.

#### Scenario: Settings screen is split by settings domain

- **WHEN** Settings contains security, key, store, Git, diagnostics, and helper
  UI in one file
- **THEN** those settings domains are extracted into focused widgets or sheet
  bodies under the Settings screen area
- **AND** the `SettingsScreen` class continues to expose the same constructor
  and app-level behavior

#### Scenario: Manage screen operation sheets are split by workflow

- **WHEN** Manage contains single-entry workflows, batch workflows, entry
  pickers, commit controls, and operation sheet layout in one file
- **THEN** those workflow surfaces are extracted into focused widgets or sheet
  bodies under the Manage screen area
- **AND** the `ManageScreen` class continues to coordinate repository actions
  and user feedback

#### Scenario: Onboarding screen steps are split by setup area

- **WHEN** Onboarding contains step rendering, key setup forms, store setup
  actions, picker flows, and review UI in one file
- **THEN** those step and form surfaces are extracted into focused widgets or
  sheet bodies under the Onboarding screen area
- **AND** the onboarding step order, completion rules, and callbacks remain
  unchanged

#### Scenario: Refactor preserves observable behavior

- **WHEN** the GUI composition refactor is complete
- **THEN** existing widget tests for Settings, Manage, Onboarding, Vault, lock,
  and shell behavior continue to pass
- **AND** visible labels, semantics, navigation, repository calls, and error
  handling remain behavior-equivalent

#### Scenario: Shared widgets are promoted only after reuse is clear

- **WHEN** an extracted widget is only used by one screen domain
- **THEN** it remains in that screen domain's local widget area
- **WHEN** the same focused widget behavior is needed by multiple screen
  domains
- **THEN** it may be promoted to `gui/lib/widgets/` with a narrow constructor
  API
