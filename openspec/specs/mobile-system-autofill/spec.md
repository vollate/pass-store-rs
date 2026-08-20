# mobile-system-autofill Specification

## Purpose

Document implemented Android and iOS system password autofill provider,
metadata indexing, matching, authentication, credential resolution, and
Settings behavior.

## Requirements

### Requirement: Mobile apps SHALL register as system password autofill providers

The Android app SHALL declare an AutofillService and an Android Credential
Manager password provider. The iOS app SHALL ship a Credential Provider
extension and maintain credential identities for indexed entries.

#### Scenario: Android system settings can list Pars

- WHEN the installed Android app is inspected by system autofill settings
- THEN Pars is available as a password autofill provider

#### Scenario: iOS Password AutoFill can list Pars

- WHEN the installed iOS app is inspected by Password AutoFill settings
- THEN Pars is available as a credential provider

### Requirement: Autofill index SHALL persist path-derived matching metadata only

Default autofill index data SHALL derive Username from the final password-entry path component, equivalent to the `.gpg` filename stem, and SHALL derive Website/App service name from the immediate parent directory. It SHALL include entry path, path-derived display and service names, path-derived username, host-normalized parent-directory identity when valid, ranking metadata, selected store identity, freshness metadata, and separately identified opt-in website aliases. It SHALL NOT include plaintext passwords, raw URLs, Android package identifiers, raw decrypted notes, TOTP values, encrypted username-field values, or full decrypted entry content.

#### Scenario: Path-derived entry is indexed without decryption

- **GIVEN** the store contains `github.com/alice.gpg`
- **WHEN** the default autofill index is built
- **THEN** the indexed service name is `github.com`
- **AND** the indexed username is `alice`
- **AND** the indexed website identity is `github.com`
- **AND** no PGP decrypt operation occurs

#### Scenario: Root-level entry has no exact service identity

- **GIVEN** the store contains the root-level entry `alice.gpg`
- **WHEN** the default autofill index is built
- **THEN** the indexed username and display fallback are `alice`
- **AND** no service name or path-derived website identity is stored

#### Scenario: Default index omits secret content and package identifiers

- **GIVEN** an encrypted entry contains a password, username field, URL field, TOTP field, and `android-package` field
- **WHEN** the default autofill index is built or incrementally updated
- **THEN** none of those decrypted field values is read or stored
- **AND** no Android package identifier is stored

### Requirement: Autofill matching SHALL use path services and optional website aliases

Autofill matching SHALL rank an exact normalized parent-directory website match and an exact case-insensitive parent-directory app-name match above an exact opt-in enriched website alias, and SHALL rank those exact matches above path, display-name, service-name, or username text fallbacks. Favorite and recent metadata SHALL only reorder otherwise equivalent match classes. Android package identifiers SHALL NOT be accepted, stored, mapped, or used for matching.

#### Scenario: Website request matches parent directory

- **GIVEN** an indexed entry has path `example.com/alice`
- **WHEN** an autofill request is made for `https://www.example.com/login`
- **THEN** that entry is returned as an exact path-derived website candidate

#### Scenario: Native app request matches human-readable app name

- **GIVEN** an indexed entry has path `GitHub/alice`
- **WHEN** an autofill request is made with human-readable app name `github`
- **THEN** that entry is returned as an exact app-name candidate
- **AND** no Android package identifier is sent to or compared by the shared matcher

#### Scenario: Package identifier alone does not match

- **GIVEN** an indexed entry has path `Bank/alice`
- **WHEN** an Android caller is known only as package `com.example.bank` and no matching website, app label, or text query is available
- **THEN** the shared matcher returns no exact package candidate

#### Scenario: Favorite and recent metadata break equivalent ties

- **GIVEN** multiple entries have the same exact service match class
- **WHEN** candidates are ranked
- **THEN** favorite and more-recent entries rank above otherwise equivalent entries
- **AND** neither bonus outranks a stronger match class

### Requirement: Autofill SHALL authenticate before returning credentials

System autofill providers SHALL require platform local authentication before
decrypting and returning a selected credential. Failed or canceled
authentication SHALL return no credential.

#### Scenario: Authentication cancellation does not fill

- GIVEN a user selects an autofill candidate
- WHEN platform authentication is canceled
- THEN Pars does not decrypt the entry
- AND no username or password is returned to the requesting app or website

### Requirement: Autofill SHALL decrypt credentials only on demand

Autofill providers SHALL decrypt only the selected indexed entry after successful platform authentication. Decryption SHALL use the selected mobile PGP backend and the key-bound cached PGP passphrase when available. The returned username SHALL be the filename-stem username stored in the index, and the returned password SHALL be the decrypted entry's first line. Credential resolution SHALL NOT update or enrich the index. If no usable passphrase or key is available for the selected entry, autofill SHALL fail closed.

#### Scenario: Selected entry is the only decrypted entry

- **GIVEN** multiple entries are indexed
- **AND** a usable key-bound PGP passphrase is available
- **WHEN** local authentication succeeds for one selected candidate
- **THEN** Pars decrypts exactly that selected entry once
- **AND** returns its path-derived username and first-line password
- **AND** does not write the autofill index

#### Scenario: Encrypted username does not override filename stem

- **GIVEN** the selected path is `example.com/alice`
- **AND** its encrypted content contains `username: bob`
- **WHEN** the credential is successfully resolved
- **THEN** the returned username is `alice`

#### Scenario: Missing passphrase fails closed

- **GIVEN** a selected entry requires a passphrase-protected private key
- **AND** no usable cached passphrase is available
- **WHEN** autofill tries to resolve the selected entry
- **THEN** no plaintext credential is returned

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

### Requirement: Autofill index lifecycle SHALL support non-decrypting incremental updates

After an autofill index has been initialized, successful vault add, edit, move, delete, favorite, and recent operations SHALL update only affected logical index records. These operations SHALL NOT accept a PGP backend or passphrase and SHALL NOT decrypt entries. If no autofill index exists, ordinary vault mutations SHALL remain successful without implicitly creating one. Index updates SHALL be atomically published so platform providers never observe a partially written document.

#### Scenario: Entry creation upserts one path-derived record

- **GIVEN** an autofill index exists
- **WHEN** a new entry `gitlab.com/alice.gpg` is successfully created
- **THEN** one record with service `gitlab.com` and username `alice` is upserted
- **AND** no other entry is re-derived or decrypted

#### Scenario: Entry move preserves optional aliases

- **GIVEN** an indexed entry has ranking metadata and opt-in website aliases
- **WHEN** the entry is successfully renamed or moved
- **THEN** the old path is removed and the new path metadata is derived
- **AND** existing ranking metadata and opt-in aliases are preserved
- **AND** no entry is decrypted

#### Scenario: Entry deletion removes only affected paths

- **GIVEN** an autofill index exists
- **WHEN** an entry or folder is successfully deleted
- **THEN** the matching entry path or path-prefix records are removed
- **AND** unrelated records remain logically unchanged

#### Scenario: Metadata-only read patches ranking without rebuild

- **GIVEN** an indexed entry is opened, favorited, or marked recent
- **WHEN** its ranking metadata changes
- **THEN** only supplied favorite and recent fields are patched
- **AND** no full index rebuild or entry decryption occurs

### Requirement: Encrypted website enrichment SHALL be explicit and transactional

The system SHALL provide a separate opt-in operation that accepts an explicit non-empty set of indexed paths, decrypts only those entries, normalizes values from `url`, `website`, and `service` fields, and stores only normalized website aliases separately from path-derived identity. If any selected entry cannot be decrypted or validated, the existing index SHALL remain unchanged. Normal rebuild, incremental mutation, candidate query, metadata update, and credential resolution flows SHALL NOT invoke enrichment.

#### Scenario: Explicit enrichment adds normalized aliases

- **GIVEN** an indexed entry contains `url: https://www.example.com/login`
- **WHEN** the user explicitly enriches that selected entry
- **THEN** exactly that entry is decrypted
- **AND** `example.com` is stored as an enriched website alias
- **AND** the raw URL and other decrypted content are not stored

#### Scenario: Enrichment failure preserves the previous index

- **GIVEN** multiple paths are selected for one enrichment operation
- **AND** one selected entry cannot be decrypted
- **WHEN** enrichment runs
- **THEN** the operation fails
- **AND** none of the staged alias replacements is committed

#### Scenario: Disabling enrichment clears aliases without decryption

- **GIVEN** enriched website aliases exist
- **WHEN** the user disables or clears URL enrichment
- **THEN** enriched aliases are removed without decrypting entries
- **AND** path-derived services, usernames, and ranking metadata remain available

### Requirement: Autofill SDK SHALL expose only the replacement path-first contract

The Rust core, Flutter Rust Bridge, native C/JNI JSON ABI, Dart repository, Android adapter, and iOS adapter SHALL use the replacement path-first models and operations. Refresh and incremental requests SHALL omit PGP executable and passphrase fields; query requests SHALL expose website, human-readable app name, text query, and limit but SHALL omit Android package fields. The implementation SHALL NOT contain compatibility readers, deprecated aliases, dual-write behavior, or fallback calls for the previous unpublished contract.

#### Scenario: Default lifecycle API cannot request decryption

- **WHEN** an SDK client constructs a rebuild, upsert, move, remove, or ranking-patch request
- **THEN** the request model has no PGP backend, executable, passphrase, or decrypted-field input

#### Scenario: Query ABI has no package parameter

- **WHEN** Android or iOS constructs a native candidate query
- **THEN** the JSON request can contain website, app name, text query, and limit
- **AND** it cannot contain an Android package matching field

#### Scenario: Development-era index is not migrated

- **GIVEN** an index document does not conform to the replacement schema
- **WHEN** a provider attempts to read it
- **THEN** candidate lookup fails closed
- **AND** no legacy parser or migration path is invoked

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

## Needs Verification

- Android Credential Manager provider behavior depends on Android version and
  device services.
- iOS Credential Provider extension availability requires matching app group
  and keychain entitlements in Apple developer provisioning.
- End-to-end autofill fill flows require simulator or physical-device checks.
