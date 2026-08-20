## MODIFIED Requirements

### Requirement: Android Autofill SHALL present renderable matched and unmatched states

The Android AutofillService SHALL use a localized, system-safe `RemoteViews` presentation for every candidate. A matched candidate SHALL keep service and authoritative username legible and SHALL identify Pars as the source when the system-owned presentation area permits it without displacing credential identity. When a fillable username or password form is recognized but the query returns no candidates, the service SHALL return a visibly distinct localized no-match presentation anchored to the recognized fields instead of returning a null response. The no-match presentation SHALL NOT fill an empty value, alter a form field, decrypt an entry, or expose secret data. Presentation polish SHALL NOT introduce package-name matching or non-allowlisted view classes.

#### Scenario: Candidate presentation uses system-safe views
- **WHEN** Android renders a Pars Autofill candidate
- **THEN** its `RemoteViews` hierarchy contains only classes accepted by the system Autofill UI
- **AND** service and authoritative username remain visible at supported font scales
- **AND** presentation does not depend on a network-fetched icon

#### Scenario: Candidate presentation is localized
- **GIVEN** Android resolves a supported English or Chinese platform locale
- **WHEN** matched or no-match Pars Autofill text renders
- **THEN** user-facing source and no-match labels use the corresponding native resources
- **AND** service and username data remain unchanged

#### Scenario: Recognized form has no matching credential
- **GIVEN** Android exposes a fillable username or password field
- **AND** Pars finds no matching indexed credential
- **WHEN** the AutofillService responds
- **THEN** the Autofill popup displays that no matching password was found
- **AND** the presentation is distinguishable from a fillable credential where system styling permits
- **AND** selecting or dismissing that message does not modify any form field
- **AND** no entry is decrypted

#### Scenario: Presentation refinement does not restore package matching
- **GIVEN** Android identifies only a package name and has no matching website, human-readable app label, or text query
- **WHEN** Autofill presentation is requested
- **THEN** the shared matcher does not create a package-name candidate
- **AND** presentation code does not add package identifiers to index or request data

### Requirement: Settings SHALL control path indexing and optional enrichment

Settings SHALL show a concise localized system Autofill state such as Ready with indexed count, Needs rebuild, Busy, Unavailable, or Disabled. It SHALL provide actions to open platform Autofill setup, explicitly rebuild path-derived data, clear Autofill data, and separately enable, run, clear, or disable encrypted website-field enrichment. Raw parser field lists, private app-storage paths, and backend error strings SHALL NOT be used as the Settings tile subtitle; bounded non-secret diagnostics SHALL be available only through explicit Details or Runtime diagnostics. A normal rebuild SHALL NOT require a PGP session or passphrase and SHALL NOT decrypt entries. Enrichment SHALL remain disabled by default and SHALL clearly disclose that selected encrypted entries will be read.

#### Scenario: Ready status is concise
- **GIVEN** the Autofill index is valid and contains entries
- **WHEN** Settings renders its Autofill summary
- **THEN** it shows a localized Ready state and indexed count
- **AND** the tile does not contain raw index JSON or filesystem details

#### Scenario: Invalid index offers rebuild without raw parser text
- **GIVEN** the Autofill index fails closed because it uses an invalid schema
- **WHEN** Settings renders Autofill state
- **THEN** it shows a localized Needs rebuild summary and Rebuild action
- **AND** raw parser fields and private app-storage paths are available only through explicit bounded diagnostics

#### Scenario: Refresh rebuilds from paths only
- **GIVEN** Autofill data may be stale
- **WHEN** the user selects Refresh or Rebuild Autofill data
- **THEN** Pars rebuilds the index from password-entry paths and ranking metadata
- **AND** no entry is decrypted

#### Scenario: Clearing Autofill data removes shared candidates
- **GIVEN** Autofill data exists for the selected store
- **WHEN** the user clears Autofill data from Settings and confirms the destructive action
- **THEN** shared Autofill index data is removed
- **AND** iOS credential identities are removed when running on iOS
- **AND** the resulting localized status is visible

#### Scenario: URL enrichment is visibly separate
- **GIVEN** URL enrichment is disabled
- **WHEN** the user views Autofill settings
- **THEN** default path refresh and encrypted URL enrichment are presented as separate actions
- **AND** enrichment is not run until the user explicitly opts in and supplies a non-empty entry selection

#### Scenario: Status refresh remains non-decrypting
- **WHEN** Settings refreshes or re-renders the concise Autofill status
- **THEN** it reads public index/platform status only
- **AND** status presentation does not decrypt an entry or start a PGP session

## ADDED Requirements

### Requirement: Mobile Autofill presentation SHALL remain accessible within platform constraints

Android and iOS Autofill presentation SHALL expose the service/source, candidate username, matched/no-match state, and authentication result through platform-supported accessible labels and localization resources. Layouts SHALL tolerate supported font scaling without intentionally clipping the authoritative username or converting a no-match state into an empty credential.

#### Scenario: Assistive technology identifies a matched candidate
- **WHEN** platform assistive technology focuses a Pars Autofill candidate
- **THEN** it can identify Pars or the provider source, service, and authoritative username through platform-supported semantics
- **AND** no password value is announced before successful authentication and selection

#### Scenario: Assistive technology identifies no match
- **WHEN** a recognized form has no candidate
- **THEN** platform-supported semantics announce the localized no-match state
- **AND** no empty username or password is offered as a credential

### Requirement: Autofill visual changes SHALL preserve path-first security and performance boundaries

Changes to Flutter Autofill settings, Android `RemoteViews`, Android authentication UI, or iOS credential-provider presentation SHALL NOT change the shared path-first schema, matching inputs, ranking rules, fail-closed behavior, platform authentication requirement, or selected-path-only resolution. Presentation state SHALL NOT cause whole-vault decryption or index rebuilding.

#### Scenario: Rendering a candidate performs no decryption
- **WHEN** Android or iOS renders one or more candidate presentations
- **THEN** it uses public indexed metadata
- **AND** no entry is decrypted until one authenticated candidate is selected

#### Scenario: Rendering Settings performs no implicit rebuild
- **WHEN** the redesigned Settings home or Autofill detail route renders
- **THEN** it does not implicitly rebuild the index, enrich URLs, or decrypt entries
- **AND** those operations remain explicit user actions

#### Scenario: Session-only passphrase is not published durably
- **GIVEN** Flutter has an active in-memory PGP session
- **AND** the user did not explicitly enable durable passphrase storage
- **WHEN** Pars publishes native Autofill state
- **THEN** the native state contains no passphrase
- **AND** locking or backgrounding republishes the passphrase-free state

### Requirement: Android Autofill SHALL target current fields across duplicate and multi-step forms

Android field parsing SHALL prefer the focused visible username/password form over earlier hidden or duplicate forms. If focus metadata is absent, it SHALL choose the latest adjacent visible username/password pair. Username-only and password-only pages SHALL remain fillable independently. For multi-step flows, Pars SHALL use field IDs only from the latest FillContext while it MAY inherit website, human-readable app, and username-query context from earlier FillContexts.

#### Scenario: Focused login form wins when one page exposes multiple login methods
- **GIVEN** one webpage exposes multiple login methods or form variants with earlier hidden username/password fields and a later focused visible login form
- **WHEN** Pars parses the latest AssistStructure
- **THEN** the Dataset binds to the focused visible form IDs
- **AND** it does not bind to an earlier hidden or inactive pair

#### Scenario: Latest visible pair wins without focus metadata
- **GIVEN** a browser exposes multiple visible username/password pairs without marking one focused
- **WHEN** Pars parses the form
- **THEN** it chooses the latest adjacent pair

#### Scenario: Username-only first step remains fillable
- **GIVEN** the latest login page contains a username field but no password field
- **WHEN** Pars returns candidates
- **THEN** the Dataset binds only to the username field
- **AND** authentication fills no absent password field

#### Scenario: Password-only second step inherits service context
- **GIVEN** a prior FillContext identified the website or account query
- **AND** the latest page contains only a password field
- **WHEN** Pars returns candidates for the latest page
- **THEN** it inherits matching metadata from the earlier context
- **AND** binds and fills only the latest password field after authentication
