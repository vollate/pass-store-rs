## ADDED Requirements

### Requirement: Entry detail SHALL honor the active color theme

The entry detail sheet SHALL derive PGP passphrase input and masked or revealed password surface colors from the active Flutter theme. These surfaces SHALL remain visually appropriate and their text and icons SHALL remain legible in both light and dark modes without a hard-coded light-only fill overriding dark mode.

#### Scenario: Password surface is rendered in dark mode

- **WHEN** an entry detail sheet displays a masked or revealed password while the active theme uses dark brightness
- **THEN** the password surface uses the configured dark theme surface treatment
- **AND** it does not use the light theme's hard-coded input fill
- **AND** the password text and reveal icon remain legible

#### Scenario: Passphrase input is rendered in either theme

- **WHEN** an entry requires a PGP passphrase in light or dark mode
- **THEN** the passphrase input derives its fill and foreground treatment from the active input decoration theme

### Requirement: Entry detail SHALL preserve modal width across asynchronous states

The entry detail sheet SHALL occupy the available width permitted by its modal route constraints in passphrase, decrypting, decryption-error, empty, and loaded-content states. Transitioning between these states SHALL NOT collapse the modal to the intrinsic width of a progress indicator or other compact child.

#### Scenario: Entry is being decrypted

- **WHEN** the entry detail modal is waiting for an asynchronous secret read
- **THEN** the loading presentation occupies the available modal width
- **AND** the modal does not shrink to the loading indicator's intrinsic width

#### Scenario: Decryption completes

- **WHEN** an entry detail modal transitions from decrypting to loaded content or a decryption error
- **THEN** its width remains stable within the same route constraints

#### Scenario: Passphrase unlock starts secret loading

- **WHEN** a user submits a valid PGP passphrase and the sheet transitions from the passphrase prompt to decrypting and then loaded content
- **THEN** each state uses the same available modal width
