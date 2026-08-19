## MODIFIED Requirements

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

### Requirement: Settings SHALL control path indexing and optional enrichment

Settings SHALL show system autofill setup status where available, provide actions to open platform autofill setup screens, explicitly rebuild path-derived autofill data, clear autofill data, and separately enable, run, clear, or disable encrypted website-field enrichment. A normal rebuild SHALL NOT require a PGP session or passphrase and SHALL NOT decrypt entries. Enrichment SHALL be disabled by default and SHALL clearly disclose that selected encrypted entries will be read.

#### Scenario: Refresh rebuilds from paths only

- **GIVEN** autofill data may be stale
- **WHEN** the user selects Refresh autofill data
- **THEN** Pars rebuilds the index from password-entry paths and ranking metadata
- **AND** no entry is decrypted

#### Scenario: Clearing autofill data removes shared candidates

- **GIVEN** autofill data exists for the selected store
- **WHEN** the user clears autofill data from Settings
- **THEN** shared autofill index data is removed
- **AND** iOS credential identities are removed when running on iOS

#### Scenario: URL enrichment is visibly separate

- **GIVEN** URL enrichment is disabled
- **WHEN** the user views autofill settings
- **THEN** default path refresh and encrypted URL enrichment are presented as separate actions
- **AND** enrichment is not run until the user explicitly opts in and supplies a non-empty entry selection

## ADDED Requirements

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
