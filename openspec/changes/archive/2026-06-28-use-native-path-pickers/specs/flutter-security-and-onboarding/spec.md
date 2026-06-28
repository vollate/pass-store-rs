## ADDED Requirements

### Requirement: Settings and Onboarding SHALL use native path selectors for filesystem paths

Flutter Settings and Onboarding SHALL use platform-native file or folder
selectors as the primary UI for user-facing filesystem path choices. Affected
forms SHALL show a compact no-icon picker row that displays the default/base
path before selection and the selected path after selection. The store-folder
selection UI and key-file selection UI SHALL remain in their existing separate
interfaces and SHALL NOT be merged into one popup or form.

#### Scenario: Store folder picker shows default path before selection

- **GIVEN** a Settings or Onboarding store form needs a filesystem folder path
- **WHEN** the form is opened before the user chooses a folder
- **THEN** the form shows a compact no-icon row for the store folder
- **AND** the row displays `Default: <path>` using the best available base or
  derived store path
- **AND** the row exposes a Choose action instead of an editable path text field

#### Scenario: Store folder picker shows selected path after selection

- **GIVEN** a Settings or Onboarding store form shows a store folder picker row
- **WHEN** the platform folder selector returns a folder path
- **THEN** the row displays `Selected: <path>` with the returned or derived
  store path
- **AND** the row action changes to Change
- **AND** submitting the form passes that selected path to the existing store
  repository operation

#### Scenario: Create and clone derive target root from selected base folder

- **GIVEN** a create-store or clone-store form needs a target root that may not
  exist yet
- **WHEN** the user chooses a base folder from the native folder selector
- **THEN** the final store root is derived from the selected base folder and the
  store name or remote URL slug
- **AND** the derived root is shown as the selected path before submission

#### Scenario: Key file import uses a separate file picker row

- **GIVEN** the user opens a PGP or SSH key-file import flow
- **WHEN** the import file form is shown
- **THEN** the form shows a compact no-icon row for the key file
- **AND** the row displays `Default: <path>` before selection
- **AND** the key-file picker remains inside the key import interface, separate
  from store folder selection interfaces
- **AND** the form does not show an editable path text field

#### Scenario: Key file import submits selected file path

- **GIVEN** a PGP or SSH key-file import form shows a key file picker row
- **WHEN** the platform file selector returns a file path
- **THEN** the row displays `Selected: <path>` with that file path
- **AND** submitting the form passes that selected file path to the existing key
  import repository operation

#### Scenario: Picker cancellation preserves default state

- **GIVEN** a path picker row is shown before a required path has been selected
- **WHEN** the native selector is canceled
- **THEN** the row continues to display the default path
- **AND** the submit action for that required path remains disabled

#### Scenario: Unsupported picker reports an error without manual fallback

- **GIVEN** a platform-native selector is unavailable or fails before returning
  a path
- **WHEN** the user invokes the Choose action
- **THEN** Settings or Onboarding shows a clear error notification
- **AND** the form does not enable submission using a manually typed path
