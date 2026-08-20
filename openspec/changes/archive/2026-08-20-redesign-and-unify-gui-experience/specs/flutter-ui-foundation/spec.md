## ADDED Requirements

### Requirement: Flutter UI SHALL use one semantic design foundation

The production Flutter UI SHALL derive color, typography, spacing, shape, status, component, and motion treatments from shared theme tokens or focused shared components. Success, warning, error, busy, unavailable, selected, and destructive states SHALL use matching visual and semantic treatments in light and dark themes. Screen-local hard-coded colors SHALL NOT be used when a semantic theme role exists.

#### Scenario: Failure status uses failure semantics
- **GIVEN** Git status is failed
- **WHEN** Vault renders its status badge
- **THEN** the badge uses a localized failure label
- **AND** its icon, color, and semantics indicate failure rather than success

#### Scenario: Destructive action is visually distinct
- **WHEN** a user is offered an entry or key deletion action
- **THEN** the action uses the shared destructive treatment
- **AND** it is not visually equivalent to an ordinary secondary action

#### Scenario: Shared surfaces remain legible in both themes
- **WHEN** a shared row, status, input, detail surface, modal, or notification renders in light or dark mode
- **THEN** its foreground and background come from semantic theme roles
- **AND** small text meets a contrast ratio of at least 4.5:1

### Requirement: Flutter shell and surfaces SHALL adapt to available width and text scale

Production Flutter routes SHALL classify compact, medium, and expanded window widths from layout constraints, SHALL bound readable content on wide windows, and SHALL avoid clipping ordinary controls or confirmation actions at up to 200% text scaling. Compact layouts SHALL use phone-appropriate navigation and one-column content; wider layouts SHALL use an appropriate rail, pane, or constrained dialog without stretching phone cards across the full window.

#### Scenario: Compact authenticated shell uses bottom navigation
- **GIVEN** the authenticated window is narrower than the compact breakpoint
- **WHEN** the main shell renders
- **THEN** Vault and Settings are reachable through a Material 3 bottom navigation surface
- **AND** ordinary content remains single-column

#### Scenario: Wide authenticated shell uses bounded navigation and content
- **GIVEN** the authenticated window is at or above the medium breakpoint
- **WHEN** the main shell renders
- **THEN** it uses a navigation rail or equivalent wide-screen navigation
- **AND** route content is bounded or composed into useful panes rather than stretched without limit

#### Scenario: Large text keeps critical action reachable
- **GIVEN** text scaling is 200%
- **WHEN** a form, destructive confirmation, lock surface, or entry detail renders on a compact phone
- **THEN** labels may wrap without horizontal overflow
- **AND** the primary or destructive submit action remains reachable by scrolling

### Requirement: Flutter UI SHALL support persisted System, English, and Chinese locale selection

Pars SHALL provide a Settings language selector with System, English, and Chinese choices. The selected value SHALL be stored in a non-secret UI preference store, applied to `MaterialApp` without restarting, and restored on later launches. Missing, invalid, or unreadable preference data SHALL fall back to System locale without blocking app startup.

#### Scenario: User switches to Chinese
- **WHEN** the user selects Chinese in Settings
- **THEN** the active Flutter locale changes to Chinese immediately
- **AND** a later app launch restores Chinese

#### Scenario: User follows system locale
- **GIVEN** the stored preference is System
- **WHEN** the platform locale changes between supported locales
- **THEN** Pars follows the platform locale

#### Scenario: Locale preference is invalid
- **GIVEN** persisted UI preferences contain an unsupported locale value
- **WHEN** Pars starts
- **THEN** it uses System locale
- **AND** vault, lock, and onboarding startup remain available

### Requirement: Every production-facing string SHALL be localized in English and Chinese

Every production Flutter label, tooltip, semantic label, validation message, empty state, status summary, notification, dialog, sheet, and error summary SHALL be sourced from localization resources with English and Chinese values. Native Android and iOS Pars presentation strings SHALL provide equivalent English and Chinese resources. Machine data such as user-entered paths, commands, fingerprints, usernames, and diagnostic values SHALL remain unchanged.

#### Scenario: Localization resources remain complete
- **WHEN** localization validation runs
- **THEN** English and Chinese resources contain the same message keys
- **AND** production widget source contains no unapproved user-facing English literal

#### Scenario: Chinese layout renders a complete workflow
- **WHEN** Vault, entry detail, Settings, onboarding, and lock are rendered in Chinese
- **THEN** their actions, statuses, validation, and navigation labels are Chinese
- **AND** untranslated English fallback text is not mixed into the workflow

### Requirement: Interactive UI SHALL expose accessible names, states, and actions

Every actionable control SHALL expose an accessible name and enabled, selected, expanded, obscured, busy, or destructive state as applicable. Icon-only controls SHALL have localized tooltips and semantic labels. Dynamic errors and operation outcomes SHALL be announced through live regions without announcing passwords, passphrases, private-key material, or other secrets.

#### Scenario: Screen reader reaches an icon-only action
- **WHEN** assistive technology focuses a copy, favorite, reveal, close, overflow, lock, or selection control
- **THEN** it announces a localized purpose and current state
- **AND** activating it invokes the same concrete action as touch input

#### Scenario: Busy state is announced
- **WHEN** key preparation, decryption, rebuild, or mutation is in progress
- **THEN** the affected control is disabled against duplicate submission
- **AND** assistive technology receives a localized busy status

### Requirement: User-facing failures SHALL be concise, localized, and sanitized

Primary UI surfaces SHALL show a stable localized summary and recovery action for known failures. Raw `error.toString()`, private app-storage paths, parser field lists, command output, stack details, passwords, passphrases, private-key material, and decrypted entry contents SHALL NOT appear in ordinary tile subtitles or transient summaries. Bounded non-secret diagnostics MAY be exposed behind an explicit Details or Runtime diagnostics action.

#### Scenario: Autofill schema is invalid
- **GIVEN** the Autofill index fails closed because its schema is invalid
- **WHEN** Settings renders Autofill status
- **THEN** the tile shows a localized Needs rebuild summary and recovery action
- **AND** raw parser fields and private app-storage paths are absent from the tile

#### Scenario: User requests diagnostic details
- **GIVEN** a failure has bounded non-secret technical details
- **WHEN** the user explicitly opens Details
- **THEN** the details can be viewed or copied
- **AND** secret redaction rules still apply

### Requirement: Feedback persistence SHALL match operation consequence

Copy and routine success feedback SHALL be transient and announced as a live region. Recoverable failures SHALL remain available long enough to invoke their recovery action. Destructive confirmation SHALL block submission until its existing confirmation contract is satisfied. Partial success and post-mutation Git commit failure SHALL use a durable result surface that states what changed and whether rollback occurred.

#### Scenario: Password copy succeeds
- **WHEN** a password is copied
- **THEN** a short localized confirmation is shown and announced
- **AND** it does not obscure a later high-severity result

#### Scenario: Optional Git commit fails after mutation
- **GIVEN** a vault mutation has succeeded
- **WHEN** its optional Git commit fails
- **THEN** a durable warning states that the vault mutation succeeded
- **AND** it states that the mutation was not rolled back
- **AND** diagnostic or recovery actions remain reachable

### Requirement: UI regression validation SHALL cover representative visual and accessibility states

The GUI test suite SHALL include deterministic coverage for light and dark themes, English and Chinese, compact and expanded widths, 200% text scaling, keyboard-visible forms, semantics, navigation-state preservation, empty/loading/error states, and representative Vault, entry-detail, Settings, onboarding, and lock surfaces. Native presentation tests SHALL continue to validate platform-safe Autofill layouts.

#### Scenario: Representative visual matrix is validated
- **WHEN** GUI verification runs
- **THEN** deterministic golden, screenshot, or equivalent structural tests cover the required theme, locale, width, and state matrix
- **AND** unexpected overflow or semantics regressions fail validation

#### Scenario: Accessibility audit has no unclassified blocker
- **WHEN** semantics and interaction tests run
- **THEN** every primary workflow is operable with exposed semantic actions
- **AND** any platform-owned limitation is explicitly documented and tested at the integration boundary
