## MODIFIED Requirements

### Requirement: Delete local store SHALL require exact confirmation and configured root

Delete-local-store SHALL require confirmation equal to the final store name
derived from the normalized store root basename, require the root to be
configured and exist as a directory, refuse filesystem root deletion, remove
the root from config, save config, and delete the directory tree. User-facing
delete confirmation UI SHALL display the full store root as read-only context
but SHALL ask the user to type only the final store name.

Sources: `bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`,
`gui/lib/screens/settings/widgets/settings_store_widgets.dart`

#### Scenario: Confirmation must match store name

- **GIVEN** a configured store root `/data/user/0/top.vollate.pars_gui/files/stores/work`
- **WHEN** delete-local-store receives confirmation `work`
- **THEN** validation succeeds and the store directory tree is deleted

#### Scenario: Full path is not required for confirmation

- **GIVEN** a configured store root `/data/user/0/top.vollate.pars_gui/files/stores/work`
- **WHEN** the delete confirmation UI is shown
- **THEN** the full root is displayed as read-only context
- **AND** the confirmation field asks for `work`

#### Scenario: Mismatched store name is rejected

- **GIVEN** a configured store root `/data/user/0/top.vollate.pars_gui/files/stores/work`
- **WHEN** delete-local-store receives confirmation `stores/work` or any value other than `work`
- **THEN** validation fails without deleting files
