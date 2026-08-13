## ADDED Requirements

### Requirement: Protected PGP sessions SHALL start only after private-key preparation

Flutter PGP orchestration SHALL await pure-Rust private-key import
re-protection, or existing-key preparation and migration, before starting a
fingerprint-bound in-memory PGP session. Preparation SHALL NOT change the
configured session expiration, enable durable passphrase storage, or retain an
unlocked key beyond existing policy. A failed preparation SHALL not create or
extend a session.

#### Scenario: Imported key session waits for commit

- **GIVEN** the shared Settings or Onboarding flow is importing a protected
  private key into the pure-Rust backend
- **WHEN** the user submits the correct passphrase
- **THEN** the import remains pending while the backend validates and
  re-protects the key
- **AND** the session for the returned fingerprint starts only after commit
  succeeds

#### Scenario: Existing legacy key migrates before session activation

- **GIVEN** an existing selected private key uses legacy protection
- **WHEN** a manually entered or securely restored passphrase is used to start
  its PGP session
- **THEN** Flutter awaits fingerprint-bound backend preparation and migration
- **AND** starts the session only after preparation succeeds

#### Scenario: Preparation failure does not start or extend session

- **GIVEN** no active PGP session exists for fingerprint `ABC`
- **WHEN** import re-protection or existing-key preparation for `ABC` fails
- **THEN** no session is started for `ABC`
- **AND** the user can retry without the failed passphrase remaining in the
  input field

#### Scenario: Existing expiration policy remains authoritative

- **GIVEN** private-key preparation succeeds and the configured PGP session
  expiration is five minutes
- **WHEN** Flutter starts the fingerprint-bound session
- **THEN** the session expires under the existing five-minute policy
- **AND** successful migration does not extend, persist, or bypass that policy

### Requirement: Private-key preparation feedback SHALL use existing UI and i18n

Settings, Onboarding, and existing-key unlock flows SHALL present private-key
preparation as part of their established pending and error states. Every new
user-facing progress, success, and failure string introduced by this change
SHALL come from the configured Flutter i18n resources. The change SHALL NOT add
a separate visual style, import sheet, or hard-coded English fallback for the
new states.

#### Scenario: Slow one-time preparation remains visibly pending

- **GIVEN** a legacy key requires a long one-time source S2K operation
- **WHEN** preparation is running
- **THEN** the existing action shows a localized pending state
- **AND** duplicate submission is disabled
- **AND** completion produces a localized success or sanitized failure result

#### Scenario: Typed failure maps to localized text

- **GIVEN** the bridge returns a typed re-protection or migration failure
- **WHEN** Flutter renders the failure
- **THEN** it selects the message through the existing i18n system
- **AND** the rendered message contains no passphrase or private-key material

### Requirement: GUI PGP deletion SHALL reflect verified managed-key removal

Settings SHALL retain human-readable typed confirmation and SHALL NOT request
the PGP passphrase merely to delete the encrypted private-key file. When a PGP
identity is displayed as `Display Name <email>`, the required confirmation
SHALL be only `Display Name`; the email address SHALL NOT be required. After the
bridge confirms that managed private material is absent,
Settings SHALL clear the matching active session and securely stored
passphrase, refresh the key list, and show localized outcome text. If private
removal fails, Settings SHALL preserve matching security state and keep the key
visible. If only public cleanup fails, Settings SHALL report localized partial
success and SHALL NOT claim the private key remains installed. `.gpg-id`
references SHALL remain unchanged.

#### Scenario: Complete GUI deletion clears matching authorization

- **GIVEN** Settings displays protected PGP key `ABC` and its matching session or
  securely stored passphrase exists
- **WHEN** the user types the displayed human-readable key name and deletion
  confirms both private and public records absent
- **THEN** Settings clears the session and stored passphrase for `ABC`
- **AND** refreshes the list and shows a localized deletion success

#### Scenario: Deletion does not request the private-key passphrase

- **GIVEN** the delete confirmation is open for protected PGP key `ABC`
- **WHEN** the user supplies the required human-readable key-name confirmation
- **THEN** Settings submits deletion without requesting or transmitting the PGP
  passphrase

#### Scenario: PGP email is excluded from typed confirmation

- **GIVEN** Settings displays PGP identity `Alice <alice@example.com>`
- **WHEN** the user opens its delete confirmation
- **THEN** the required confirmation value is `Alice`
- **AND** the user is not required to type `<alice@example.com>`

#### Scenario: Delete confirmation remains usable above the keyboard

- **GIVEN** the PGP delete confirmation is displayed on a phone-sized viewport
- **WHEN** the software keyboard opens for the confirmation field
- **THEN** the dialog content can scroll within the remaining height
- **AND** the confirmation field and delete action remain reachable without a
  layout overflow

#### Scenario: Private removal failure preserves security state and visibility

- **GIVEN** deletion of `ABC` cannot confirm its private record absent
- **WHEN** Settings receives the failure
- **THEN** it does not clear `ABC`'s matching session or stored passphrase
- **AND** it refreshes or preserves the visible key record and shows a localized
  failure

#### Scenario: Public cleanup failure clears secrets and reports partial success

- **GIVEN** deletion confirms `ABC`'s private record absent but public cleanup
  failed
- **WHEN** Settings handles the structured bridge response
- **THEN** it clears `ABC`'s matching session and stored passphrase
- **AND** refreshes the list and shows a localized partial-success warning
- **AND** any `.gpg-id` reference remains visible as missing local key material
