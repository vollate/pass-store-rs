## MODIFIED Requirements

### Requirement: Flutter GUI SHALL compose large screens from focused widgets

Hand-written Flutter GUI routes SHALL be composed from focused widget modules when a route contains independent sections, adaptive surfaces, forms, dialogs, repeated rows, or workflow orchestration. Route-level widgets SHALL own repository dependencies, navigation, non-secret route state, and cross-widget orchestration. Extracted widgets SHALL own only the local presentation state and callbacks needed for their surface. Shared design-system components SHALL be promoted to `gui/lib/widgets/` or the app theme only when the same semantic behavior is required across domains. Generated bridge files are excluded from this composition requirement.

#### Scenario: Settings screen is split by settings domain
- **WHEN** Settings contains appearance, security, vault/sync, Autofill, key, store, Git, diagnostics, and helper UI
- **THEN** those settings domains are composed from focused sections, routes, or adaptive surface bodies under the Settings area
- **AND** Settings retains route-level responsibility for repositories, category navigation, and refresh orchestration

#### Scenario: Vault management workflows are split by task
- **WHEN** Vault exposes create, direct copy, detail, selection, single-entry mutation, batch mutation, commit controls, and result feedback
- **THEN** row, detail, selection, and operation surfaces are separated into focused widgets or workflow modules
- **AND** the Vault route continues to coordinate repository operations and secret-disposal boundaries

#### Scenario: Onboarding screen is split by setup capability
- **WHEN** Onboarding contains required unlock/store setup, optional biometric or SSH setup, key setup forms, picker flows, conflict handling, and review UI
- **THEN** setup capabilities and forms are extracted into focused widgets or adaptive route bodies
- **AND** the top-level onboarding route coordinates completion prerequisites and history

#### Scenario: Redesign preserves authoritative behavior rather than legacy presentation
- **WHEN** the GUI redesign changes labels, navigation, density, modal type, or visual hierarchy
- **THEN** existing repository calls, confirmation contracts, transactional outcomes, secret-clearing rules, and unsupported-action handling remain authoritative
- **AND** tests are updated to assert the new specified presentation rather than requiring legacy tabs or labels

#### Scenario: Shared widgets are promoted only after semantic reuse is clear
- **WHEN** an extracted widget is only used by one route domain
- **THEN** it remains in that route domain's local widget area
- **WHEN** the same status, action, row, error, modal, or layout behavior is needed by multiple domains
- **THEN** it is implemented through a narrow shared component or theme role

## ADDED Requirements

### Requirement: Authenticated shell SHALL own durable non-secret destination state

The authenticated shell SHALL keep Vault and Settings destination state independently addressable across destination switches. Search query, browse directory, non-secret selection, category, nested non-secret route, and scroll state SHALL be preserved when safe. Decrypted entry content, passphrases, passwords, QR payloads, and private-key material SHALL NOT be retained merely to restore a destination.

#### Scenario: Returning to Vault restores public view state
- **GIVEN** a user has entered a Vault query or browsed into a directory
- **WHEN** the user opens Settings and returns to Vault without locking
- **THEN** the previous query or directory and scroll position are restored
- **AND** returning does not require an otherwise unnecessary vault refresh

#### Scenario: Leaving a decrypted detail clears the secret
- **GIVEN** entry detail currently contains decrypted content
- **WHEN** the user changes destination, locks the app, backgrounds into a protected state, or closes the detail surface
- **THEN** decrypted content is disposed
- **AND** restoring Vault may restore only the public list/detail selection needed to request the secret again

### Requirement: Adaptive surfaces SHALL share route, modal, and keyboard behavior

Complex configuration and detail workflows SHALL use adaptive route or pane framing, while short choices and confirmations SHALL use adaptive modal framing. Shared framing SHALL provide consistent title, close/back, safe-area, maximum-width, scrolling, software-keyboard inset, and accessibility behavior.

#### Scenario: Phone form remains usable with keyboard
- **GIVEN** a compact phone displays a form that requires text confirmation
- **WHEN** the software keyboard opens
- **THEN** the form scrolls within the remaining height
- **AND** its confirmation field and submit action remain reachable

#### Scenario: Wide-window workflow is constrained
- **GIVEN** a workflow opens on an expanded window
- **WHEN** its adaptive surface renders
- **THEN** it uses a bounded pane or dialog appropriate to its complexity
- **AND** phone-width content is not stretched across the entire window
