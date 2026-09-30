## ADDED Requirements

### Requirement: Git settings SHALL group sync, commit, remote, and maintenance controls

The Git synchronization sheet SHALL use shared section rows and button groups, arranged in four sections:

- **Sync**: current status summary with last fetch time, Sync, Pull and Push as a button pair, the "Check remote on launch" setting, and the integration strategy (Rebase or Merge, default Rebase).
- **Commits**: commit identity, the "Commit every change" setting, and Commit now.
- **Remotes and authentication**: remotes, selected SSH key, and stored HTTPS credentials with Forget.
- **Maintenance**: History, Switch branch, and Reset to remote.

Sections that need a remote SHALL be disabled or hidden when Git mode is local. All labels SHALL be localized in English and Chinese. Destructive actions SHALL use a destructive yes/no dialog.

#### Scenario: Remote store shows all four sections

- **GIVEN** Git mode is remote
- **WHEN** the Git synchronization sheet opens
- **THEN** it shows Sync, Commits, Remotes and authentication, and Maintenance sections

#### Scenario: Local store hides remote-only actions

- **GIVEN** Git mode is local
- **WHEN** the Git synchronization sheet opens
- **THEN** Commits and remote configuration are available
- **AND** Sync, Pull, Push, Switch branch, and Reset to remote are not offered as executable

#### Scenario: Integration strategy defaults to rebase

- **GIVEN** the integration strategy has never been changed
- **WHEN** the Sync section renders
- **THEN** Rebase is shown as the selected strategy
- **AND** choosing Merge persists and applies to the next sync

#### Scenario: Identity row shows the current author

- **GIVEN** the repository-local identity is `Ada Lovelace <ada@example.invalid>`
- **WHEN** the Commits section renders
- **THEN** the identity row shows that name and email on one line with ellipsis

#### Scenario: Stored HTTPS credentials can be forgotten

- **GIVEN** HTTPS credentials are stored for the remote
- **WHEN** the user chooses Forget and confirms
- **THEN** the credentials are removed from secure storage

#### Scenario: Git sheet survives large text

- **WHEN** the Git synchronization sheet renders at 200% text scale on a phone width
- **THEN** no layout overflow occurs
