## MODIFIED Requirements

### Requirement: Store import SHALL stage the complete visible tree and classify Git metadata

App-managed Import SHALL copy every provider-visible file and directory, including dotfiles such as `.git` and `.gpg-id`, into staging before changing the canonical store. It SHALL reject path overlap/escape, cycles, unsupported links, duplicate names, and unsafe entries. Before filesystem installation it SHALL classify Git as valid, absent, or invalid. Installation SHALL retain any prior-destination backup until registration and atomic config persistence succeed; registration failure SHALL trigger verified rollback. An externally owned desktop folder MAY be inspected and registered directly without copying.

Import SHALL always attempt provider enumeration first, including its loading retries. A selected root that enumerates zero children after all attempts SHALL be classified as a provider fault rather than as a successful import of an empty store, and SHALL be reported with an outcome distinct from a genuinely empty selection. Import MAY then offer the authorized direct read defined by `android-direct-store-read`, and SHALL NOT register or finalize any store when that recovery is declined, unavailable, or also yields nothing. A zero-child result below a root that did enumerate SHALL remain a legitimate empty directory and SHALL NOT trigger recovery.

#### Scenario: Valid Git metadata is preserved

- **GIVEN** the selected tree exposes a valid `.git` work tree with branch, refs, objects, config, and remote metadata
- **WHEN** Import stages and validates the tree
- **THEN** all exposed Git metadata is copied unchanged
- **AND** Import does not run `git init`
- **AND** Git status, history, branch, and remote remain available after finalization

#### Scenario: Missing Git asks before finalization

- **GIVEN** the staged tree contains no `.git`
- **WHEN** Import classifies Git metadata
- **THEN** the user is told that the source may be local-only or the provider may have hidden Git metadata
- **AND** the user can initialize Git, continue without Git, or cancel

#### Scenario: User continues without Git

- **GIVEN** staged import contains no `.git`
- **WHEN** the user declines Git initialization and chooses Continue
- **THEN** the staged password store is finalized and registered
- **AND** its Git mode is disabled rather than failed

#### Scenario: User initializes Git only in staging

- **GIVEN** staged import contains no `.git`
- **WHEN** the user chooses Initialize Git
- **THEN** `git init` runs in staging and not in the source tree
- **AND** the initialized tree is finalized only after initialization succeeds

#### Scenario: User cancels missing-Git import

- **GIVEN** staged import contains no `.git`
- **WHEN** the user chooses Cancel
- **THEN** staging is deleted
- **AND** no destination is replaced or registered

#### Scenario: Present but invalid Git aborts import

- **GIVEN** staged import contains `.git`
- **AND** Git cannot validate the staged root as a usable work tree
- **WHEN** Import classifies the result
- **THEN** Import reports invalid Git metadata
- **AND** it does not discard, reinitialize, finalize, or register the staged tree

#### Scenario: Registration failure restores the prior destination

- **GIVEN** an app-managed import has installed staging and retained the prior destination backup
- **WHEN** Rust registration or config persistence fails
- **THEN** the installed tree is removed and the backup is restored and verified
- **AND** the failed import is not reported as complete

#### Scenario: Full-store import does not merge repositories

- **GIVEN** the derived app-managed destination already exists
- **WHEN** Import resolves the conflict
- **THEN** it offers atomic replacement or cancellation
- **AND** it does not merge two `.git` trees

#### Scenario: Provider is attempted before any recovery

- **GIVEN** a selected tree that the provider can enumerate
- **WHEN** Import stages the tree
- **THEN** enumeration uses the provider, including its loading retries
- **AND** no direct-filesystem recovery is attempted or authorized

#### Scenario: Unlistable root is reported as a provider fault

- **GIVEN** the granted root reports zero children with loading finished on every attempt
- **WHEN** Import classifies the enumeration result
- **THEN** Import reports a provider fault distinct from an empty selection
- **AND** it does not stage, finalize, or register an empty store

#### Scenario: Declined recovery does not register a store

- **GIVEN** Import reported a provider fault for the selected root
- **WHEN** the user declines the authorized direct read, or it is unavailable or also finds nothing
- **THEN** Import reports the provider fault outcome
- **AND** no staging, destination, or registration remains

#### Scenario: Empty directory below an enumerated root stays legitimate

- **GIVEN** the selected root enumerated children successfully
- **AND** one of its subdirectories contains no entries
- **WHEN** Import stages the tree
- **THEN** the empty subdirectory is staged as an ordinary empty directory
- **AND** no provider fault is reported and no recovery is offered
