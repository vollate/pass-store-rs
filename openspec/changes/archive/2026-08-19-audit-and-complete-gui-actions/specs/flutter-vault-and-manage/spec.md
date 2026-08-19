## ADDED Requirements

### Requirement: Entry detail SHALL expose working single-entry mutation actions

When the loaded entry-detail sheet is backed by a `ManageRepository`, Edit, Regenerate, and Delete SHALL invoke focused workflows for the displayed entry. The detail sheet SHALL clear its decrypted content before a mutation workflow is presented. Successful mutations SHALL use existing repository semantics and SHALL produce a visible result notification; cancellation SHALL perform no mutation.

#### Scenario: Edit opens the displayed entry

- **GIVEN** entry detail is displaying a decrypted entry
- **AND** the vault repository supports manage operations
- **WHEN** the user selects Edit
- **THEN** the detail sheet closes and clears its secret
- **AND** a focused edit workflow loads that same entry
- **AND** saving uses the existing edit or first-line replacement operation

#### Scenario: Regenerate replaces one entry password

- **GIVEN** entry detail is displaying an entry with parsed fields or raw notes
- **WHEN** the user selects Regenerate and confirms the focused workflow
- **THEN** regeneration targets exactly that entry
- **AND** the existing replacement behavior preserves parsed fields and raw notes
- **AND** the result is visibly reported

#### Scenario: Delete requires the existing human-readable confirmation

- **GIVEN** entry detail is displaying an entry
- **WHEN** the user selects Delete
- **THEN** the detail sheet closes and a focused delete workflow displays the full path
- **AND** deletion is blocked until confirmation equals the entry display label
- **AND** successful deletion is visibly reported

#### Scenario: Mutation workflow is cancelled

- **WHEN** the user closes an Edit, Regenerate, or Delete workflow without submitting it
- **THEN** no repository mutation is performed
- **AND** the user returns to Vault with no success notification

### Requirement: Production GUI actions SHALL NOT silently invoke empty handlers

Every rendered production GUI control that appears actionable SHALL either invoke a concrete callback, be disabled, or present an explicit unavailable-state explanation. Production action properties SHALL NOT be assigned literal empty callbacks. Framework lifecycle rebuild closures, unknown platform-channel method responses, generated code, and test fixtures are not user-action implementations and SHALL be classified separately during audits.

#### Scenario: Supported action is tapped

- **GIVEN** a production control is enabled and appears actionable
- **WHEN** the user taps the control
- **THEN** it invokes a concrete operation or navigation callback
- **AND** it does not silently return from a literal empty handler

#### Scenario: Repository lacks an optional capability

- **GIVEN** a screen is supplied a repository that lacks an optional operation interface
- **WHEN** the related control is rendered or opened
- **THEN** the control is disabled or the screen explains that the operation is unavailable
- **AND** the screen does not present mocked-future copy as though the operation were active

#### Scenario: New empty action callback is introduced

- **WHEN** production GUI source assigns a literal empty closure to an action property such as `onPressed` or `onTap`
- **THEN** automated regression validation fails
- **AND** the finding must be implemented, disabled, or explicitly classified before validation passes
