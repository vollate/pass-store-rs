## MODIFIED Requirements

### Requirement: Vault SHALL expose contextual single-entry and batch management workflows

Vault SHALL expose generated-password creation and manual credential creation through a prominent create action. It SHALL expose edit, move, rename, regenerate, and delete beside the relevant credential, and SHALL expose batch move, batch rename, batch regenerate, and batch delete only after entering explicit multi-select mode. All workflows SHALL reuse existing repository mutation semantics. Git commits after a mutation SHALL follow the "Commit every change" setting and SHALL run only when Git mode is local or remote. Mutation sheets SHALL NOT show a per-operation commit control. Git-disabled mutations SHALL remain successful without a Git warning.

#### Scenario: Create action offers existing creation workflows

- **WHEN** the user invokes Create from Vault
- **THEN** generated-password and manual-existing-password workflows are available
- **AND** they call the same repository operations and overwrite handling as before

#### Scenario: Explicit selection mode exposes batch actions

- **GIVEN** Vault is not in selection mode
- **WHEN** the user invokes Select or long-presses a selectable credential
- **THEN** Vault enters selection mode and shows selected count
- **AND** no batch operation is shown until at least one credential is selected
- **AND** selecting the first credential reveals only supported batch actions

#### Scenario: Focused single-entry workflow does not ask for an entry again

- **GIVEN** the user invokes Edit, Move, Rename, Regenerate, or Delete from a credential detail
- **WHEN** the focused workflow opens
- **THEN** it is bound to the displayed credential
- **AND** it does not show a secondary entry picker

#### Scenario: Leaving selection mode clears selection

- **GIVEN** one or more credentials are selected
- **WHEN** the user cancels selection mode or changes destination
- **THEN** public selection state is cleared or safely preserved according to shell state policy
- **AND** no repository mutation occurs

#### Scenario: Batch operation preserves per-entry outcomes

- **WHEN** a contextual batch operation runs
- **THEN** successful paths and per-entry failures are collected through existing batch semantics
- **AND** the result surface distinguishes complete success, partial success, and failure

#### Scenario: Mutation sheets have no commit checkbox

- **WHEN** any single-entry or batch mutation sheet opens
- **THEN** it does not show a "commit after operation" control

#### Scenario: Automatic Git commit failure is durable

- **GIVEN** a contextual mutation succeeds with Git enabled and "Commit every change" on
- **AND** its automatic Git commit fails
- **WHEN** the result is presented
- **THEN** the warning states that the Vault mutation was not rolled back
- **AND** it remains available long enough to inspect or recover

#### Scenario: Missing identity pauses the automatic commit

- **GIVEN** a contextual mutation succeeds and no commit identity is configured
- **WHEN** the automatic commit is about to run
- **THEN** the identity sheet opens
- **AND** cancelling it leaves the mutation in place, uncommitted

#### Scenario: Git-disabled mutation does not report sync failure

- **GIVEN** the canonical store has Git disabled
- **WHEN** a contextual mutation succeeds
- **THEN** no Git commit is attempted
- **AND** the mutation is reported as successful without a Git failure warning

### Requirement: Vault SHALL present repository and Git status with truthful semantics

Vault SHALL present canonical password-store state separately from optional Git state. Git-disabled, local Git without remote, remote Git, failed, warning, busy, uncommitted, pull-needed, push-needed, diverged, conflicted, and clean states SHALL have localized labels, icons, tooltips, and semantic states appropriate to their actual meaning. The header badge SHALL show only the short state word, never a Git mode sentence. Git disabled and missing remote SHALL NOT be presented as failures. Diverged and conflicted SHALL use warning semantics and SHALL offer recovery. Status details and recovery actions SHALL remain reachable without placing raw command or parser output in the header.

#### Scenario: Git-disabled store is neutral

- **GIVEN** the canonical password store has no `.git`
- **WHEN** Vault renders status
- **THEN** password-store readiness remains successful
- **AND** Git is shown as disabled/local-only rather than failed

#### Scenario: Local Git without remote is not sync failure

- **GIVEN** the canonical store is a valid Git repository without a remote
- **WHEN** Vault renders status
- **THEN** it identifies local Git or remote-not-configured neutrally
- **AND** it does not show a failed-sync icon

#### Scenario: Sync failure is not shown as success

- **GIVEN** remote Git status is `syncFailed`
- **WHEN** Vault renders the status control
- **THEN** it uses an error or warning icon and localized failure semantics
- **AND** it does not display a success check icon

#### Scenario: Unpushed commits are not shown as clean

- **GIVEN** remote Git status is `needPush`
- **WHEN** Vault renders the status control
- **THEN** it shows the localized push-needed label
- **AND** it does not display a success check icon

#### Scenario: Conflict offers recovery

- **GIVEN** the last sync returned a conflict with a backup branch
- **WHEN** the user activates the conflicted badge
- **THEN** a dialog offers Push backup as the secondary action and Use remote as the destructive primary action
- **AND** the dialog names the backup branch

#### Scenario: Status details are progressively disclosed

- **WHEN** the user activates a non-clean or configurable status
- **THEN** Pars presents a concise explanation and available recovery action
- **AND** bounded diagnostic details are separate from the header label

## ADDED Requirements

### Requirement: Vault pull-to-refresh SHALL run a full Git sync

When Git mode is remote, Vault pull-to-refresh SHALL run Git sync: commit pending changes according to the "Commit every change" setting or the user's answer, fetch, fast-forward or integrate with the configured strategy, then push. It SHALL then reload entries. When Git mode is local or disabled, pull-to-refresh SHALL only reload entries and status. Sync results SHALL be summarized in one localized notification. Conflicts SHALL set the conflicted state instead of a generic failure, and a sync blocked by uncommitted changes SHALL keep the uncommitted state and say that a commit is needed.

#### Scenario: Pull-to-refresh pushes pending edits

- **GIVEN** Git mode is remote, "Commit every change" is on, and the work tree has one changed entry
- **WHEN** the user pulls to refresh
- **THEN** the change is committed and pushed
- **AND** the badge shows clean

#### Scenario: Pull-to-refresh asks when automatic commits are off

- **GIVEN** Git mode is remote, "Commit every change" is off, and the work tree has one changed entry
- **WHEN** the user pulls to refresh
- **THEN** a dialog asks whether to commit before syncing
- **AND** no Git operation runs until the user chooses

#### Scenario: Pull-to-refresh on a local-only store does not sync

- **GIVEN** Git mode is local
- **WHEN** the user pulls to refresh
- **THEN** no fetch, commit, or push runs
- **AND** entries and status are reloaded

#### Scenario: Conflict during pull-to-refresh is not sync failed

- **WHEN** sync during pull-to-refresh returns a conflict
- **THEN** the badge shows conflicted
- **AND** it does not show sync failed
