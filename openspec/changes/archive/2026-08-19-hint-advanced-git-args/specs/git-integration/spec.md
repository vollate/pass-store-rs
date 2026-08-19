## ADDED Requirements

### Requirement: Advanced Git args input SHALL use placeholder examples instead of prefilled args

The Advanced Git args sheet SHALL open with an empty arguments input. Example
arguments SHALL be presented only as dim hint or placeholder text and SHALL NOT
be treated as executable command input.

#### Scenario: Advanced Git args opens empty with example hint

- **WHEN** the Advanced Git args sheet is opened
- **THEN** the Git args input is empty
- **AND** it shows example arguments such as `status, log` as hint text
- **AND** the selected command preview does not show `git status`

#### Scenario: Placeholder text is not executed

- **GIVEN** the Advanced Git args sheet is open
- **AND** the user has not typed any arguments
- **WHEN** the user attempts to run the selected command
- **THEN** no Git command is executed
- **AND** the user is told to enter at least one Git argument

#### Scenario: Typed arguments update the selected command

- **GIVEN** the Advanced Git args sheet is open
- **WHEN** the user types `status --bad`
- **THEN** the selected command preview shows `git status --bad`
- **AND** running the command executes the typed arguments
