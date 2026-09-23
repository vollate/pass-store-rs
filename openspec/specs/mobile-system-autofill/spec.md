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

Default autofill index data SHALL derive Username from the final password-entry path component, equivalent to the `.gpg` filename stem, and SHALL derive Website/App service name from the immediate parent directory. Version 3 SHALL include entry path, path-derived display and service names, path-derived username, host-normalized parent-directory identity when valid, an internal successful-Autofill completion rank, selected store identity, freshness metadata, and separately identified opt-in `login` and normalized `url` metadata. An opted-in `login` value SHALL become the effective Autofill username while retaining the path-derived username as a fallback. It SHALL NOT include plaintext passwords, raw URLs, Android package identifiers, raw decrypted notes, TOTP values, full decrypted entry content, Vault-view history, or favorite state.

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
- **THEN** none of those decrypted field values is read or stored by automatic path indexing
- **AND** no Android package identifier is stored

### Requirement: Autofill matching SHALL use path services and optional website aliases

Autofill matching SHALL rank an exact normalized parent-directory website match and an exact case-insensitive parent-directory app-name match above an exact opt-in normalized URL website/app alias, and SHALL rank those exact matches above path, display-name, service-name, or effective-username text fallbacks. Successful-Autofill completion metadata SHALL only reorder otherwise equivalent match classes. An Autofill rank from 0 through 19 SHALL add `50 - rank` points. Android package identifiers SHALL NOT be accepted, stored, mapped, or used for matching.

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

#### Scenario: Autofill completion history breaks equivalent ties

- **GIVEN** multiple entries have the same exact service match class
- **WHEN** candidates are ranked
- **THEN** more recently completed Autofill entries rank above otherwise equivalent entries
- **AND** neither bonus outranks a stronger match class

### Requirement: Autofill SHALL authorize decryption with the PGP passphrase, not the app lock

Autofill is not app re-entry. System autofill providers SHALL NOT ask for the
Pars gesture, the device passcode/pattern, or any other app-unlock step.
Returning a selected credential SHALL instead require the PGP private-key
passphrase, obtained exactly as the app obtains it:

- When biometric unlock is enabled in Pars and a key-bound passphrase is
  stored, the provider SHALL show a biometric-only prompt (no device-credential
  fallback) whose success releases the stored passphrase, with an explicit
  option to type the passphrase instead.
- Otherwise the provider SHALL go directly to a passphrase sheet whose layout,
  wording, and colors match the Vault entry sheet's passphrase step.

Flutter SHALL publish the biometric-unlock setting with native state and SHALL
publish the stored passphrase only while biometric unlock is enabled; native
state SHALL ignore a stored passphrase when the published setting is off.
Security-setting changes SHALL republish native state. Canceling the biometric
prompt or the passphrase sheet SHALL return no credential; biometric lockout,
missing enrollment, or unavailable hardware SHALL fall back to the passphrase
sheet.

Sources: `gui/android/app/src/main/kotlin/top/vollate/pars_gui/autofill/ParsAutofillUnlockActivity.kt`,
`gui/ios/ParsCredentialProvider/CredentialProviderViewController.swift`,
`gui/lib/services/autofill_repository.dart`

#### Scenario: Biometrics disabled never shows a biometric or device prompt

- **GIVEN** biometric unlock is disabled in Pars and the app unlocks with a gesture
- **WHEN** a user selects an autofill candidate
- **THEN** no fingerprint, face, device-credential, or gesture prompt is shown
- **AND** the provider shows the PGP passphrase sheet directly

#### Scenario: Biometrics release only the stored passphrase

- **GIVEN** biometric unlock is enabled and a key-bound passphrase is stored
- **WHEN** a user selects an autofill candidate
- **THEN** a biometric-only prompt is shown
- **AND** success decrypts the entry with the stored passphrase
- **AND** choosing to type instead opens the PGP passphrase sheet

#### Scenario: Cancellation does not fill

- **GIVEN** a user selects an autofill candidate
- **WHEN** the biometric prompt or passphrase sheet is canceled
- **THEN** Pars does not decrypt the entry
- **AND** no username or password is returned to the requesting app or website

### Requirement: Autofill SHALL decrypt credentials only on demand

Autofill providers SHALL decrypt only the selected indexed entry, and only after the passphrase has been authorized as above. Decryption SHALL use the selected mobile PGP backend and either the typed passphrase or the biometric-released key-bound passphrase published from system-keystore storage. The returned username SHALL be the opted-in `login` value when available and otherwise the filename-stem username stored in the index; the returned password SHALL be the decrypted entry's first line. The credential-resolution primitive SHALL NOT update or enrich the index.

When the released passphrase does not decrypt the selected entry, the provider SHALL fall back to the passphrase sheet. A typed passphrase SHALL be used for that single decryption only and SHALL NOT be persisted or published. Attempts SHALL be bounded, and cancellation or exhausted attempts SHALL return no credential. Every other resolution failure — disabled native state, store-root or generation mismatch, missing index, or missing entry — SHALL fail closed without asking for input.

#### Scenario: Selected entry is the only decrypted entry

- **GIVEN** multiple entries are indexed
- **AND** a usable key-bound PGP passphrase is available
- **WHEN** the passphrase is authorized for one selected candidate
- **THEN** Pars decrypts exactly that selected entry once
- **AND** returns its opted-in login or path-derived fallback username and first-line password
- **AND** the credential-resolution primitive does not write the Autofill index

#### Scenario: Opted-in login overrides filename stem

- **GIVEN** the selected path is `example.com/alice`
- **AND** its encrypted content contains `login: bob`
- **AND** the user has explicitly refreshed encrypted login and URL fields
- **WHEN** the credential is successfully resolved
- **THEN** the returned username is `bob`

#### Scenario: Unpublished passphrase is requested instead of failing silently

- **GIVEN** a selected entry requires a passphrase-protected private key
- **AND** no passphrase is stored, or biometric unlock is disabled
- **WHEN** the user selects the entry
- **THEN** the provider asks for the PGP private-key passphrase
- **AND** a correct passphrase decrypts only that entry and returns its credential
- **AND** the typed passphrase is not written to secure storage or to native published state

#### Scenario: Cancelled or exhausted passphrase entry returns nothing

- **GIVEN** the provider is asking for the PGP private-key passphrase
- **WHEN** the user cancels or the bounded number of incorrect attempts is reached
- **THEN** no plaintext credential is returned

#### Scenario: Non-passphrase failures never ask for input

- **GIVEN** native state is disabled, its generation is stale, or the selected entry is absent
- **WHEN** autofill tries to resolve the selected entry
- **THEN** it fails closed without asking for a passphrase

### Requirement: Native providers SHALL record only successful Autofill completions

Android Autofill, Android Credential Manager, and the iOS Credential Provider SHALL record a completion only after passphrase authorization and credential resolution succeed and the platform response has been constructed for return. Recording SHALL atomically move the selected path to rank 0, shift other distinct paths, and retain at most 20 ranked paths. Candidate display, user cancellation, resolution failure, Vault access, and Vault copy SHALL NOT record completion. A recording failure SHALL affect only future ordering and SHALL NOT prevent the current credential from being returned.

#### Scenario: Successful return records bounded MRU history

- **GIVEN** an authenticated credential has been resolved and its platform response is ready
- **WHEN** the provider is about to return it to the operating system
- **THEN** its path is atomically moved to Autofill rank 0
- **AND** duplicate history is removed and only the 20 most recent distinct paths remain ranked

#### Scenario: Cancellation and failure do not record

- **WHEN** a candidate is only displayed, authentication is canceled, or credential resolution fails
- **THEN** Autofill completion history remains unchanged

#### Scenario: History failure does not block the fill

- **GIVEN** a credential response is ready to return
- **WHEN** recording its completion fails
- **THEN** the provider still returns the credential response

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

### Requirement: Settings SHALL expose automatic path indexing and optional enrichment

Settings SHALL show a concise localized system Autofill state such as Ready with indexed count, Busy, or Unavailable. Path-derived data SHALL be created and reconciled automatically whenever a valid store is loaded. Settings SHALL expose exactly two metadata actions: use encrypted login and URL fields, and forget encrypted login and URL fields. Raw parser field lists, private app-storage paths, and backend error strings SHALL NOT be used as the Settings tile subtitle; bounded non-secret diagnostics SHALL be available only through explicit Details or Runtime diagnostics. Automatic path indexing SHALL NOT require a PGP session or passphrase and SHALL NOT decrypt entries. Encrypted-field enrichment SHALL remain disabled by default and SHALL clearly disclose that every encrypted entry will be read once. Disabling durable passphrase storage SHALL discard encrypted-field enrichment and rebuild the path-derived index, and SHALL NOT clear the index or disable native Autofill.

#### Scenario: Ready status is concise
- **GIVEN** the Autofill index is valid and contains entries
- **WHEN** Settings renders its Autofill summary
- **THEN** it shows a localized Ready state and indexed count
- **AND** the tile does not contain raw index JSON or filesystem details

#### Scenario: Invalid index self-heals without raw parser text
- **GIVEN** the Autofill index fails closed because it uses an invalid schema
- **WHEN** the GUI refreshes a valid password store
- **THEN** it replaces the index automatically from folder paths
- **AND** raw parser fields and private app-storage paths are available only through explicit bounded diagnostics

#### Scenario: Refresh reconciles from paths only
- **GIVEN** Autofill data may be stale
- **WHEN** the GUI loads or refreshes the valid password store
- **THEN** Pars rebuilds the index from password-entry paths while preserving valid same-store completion history by unchanged path
- **AND** no entry is decrypted

#### Scenario: Encrypted-field enrichment is visibly separate
- **GIVEN** encrypted-field enrichment is disabled
- **WHEN** the user views Autofill settings
- **THEN** automatic path indexing is described separately from the two encrypted-field actions
- **AND** enrichment is not run until the user explicitly confirms decrypting every entry

#### Scenario: Status refresh remains non-decrypting
- **WHEN** Settings refreshes or re-renders the concise Autofill status
- **THEN** it reads public index/platform status only
- **AND** status presentation does not decrypt an entry or start a PGP session

#### Scenario: Disabling passphrase storage keeps path-derived indexing
- **GIVEN** enriched login and URL metadata exists and durable passphrase storage is enabled
- **WHEN** the user disables durable passphrase storage
- **THEN** enriched logins and aliases are discarded
- **AND** the index is rebuilt from password-entry paths without decryption
- **AND** native Autofill stays enabled and keeps offering path-derived candidates

### Requirement: Autofill index lifecycle SHALL support non-decrypting incremental updates

Valid-store load and refresh SHALL create a missing index and replace a malformed or different-store index automatically. After an Autofill index has been initialized for the canonical store, successful Vault add, edit, move, and delete operations SHALL update only affected logical index records. These operations SHALL NOT accept a PGP backend or passphrase and SHALL NOT decrypt entries. Vault read, reveal, and copy SHALL NOT mutate the index. Ordinary Vault mutations SHALL remain successful if no Autofill index exists or an index update fails, without implicitly creating an index. Index updates SHALL be atomically published so platform providers never observe a partially written document. Before Disconnect or Delete mutates the store, native providers SHALL synchronously persist a disabled tombstone and reject all candidate/credential reads, then remove the shared index and platform identities. Every enabled native publication SHALL carry an unguessable generation in candidates and credential identities, and providers SHALL revalidate enabled state, root, index, and generation after query or decryption before returning a result. A later store SHALL require an explicit non-decrypting rebuild; reconciliation SHALL reject and remove an index whose store ID or root differs.

#### Scenario: Entry creation upserts one path-derived record

- **GIVEN** an Autofill index exists
- **WHEN** a new entry `gitlab.com/alice.gpg` is successfully created
- **THEN** one record with service `gitlab.com` and username `alice` is upserted
- **AND** no other entry is re-derived or decrypted

#### Scenario: Entry move preserves public metadata but resets path-bound history

- **GIVEN** an indexed entry has completion history and opt-in website aliases
- **WHEN** the entry is successfully renamed or moved
- **THEN** the old path is removed and new path metadata is derived
- **AND** opt-in aliases are preserved
- **AND** path-bound Autofill completion history is not inherited by the new path
- **AND** no entry is decrypted

#### Scenario: Entry deletion removes only affected paths

- **GIVEN** an Autofill index exists
- **WHEN** an entry or folder is successfully deleted
- **THEN** matching entry path or path-prefix records are removed
- **AND** unrelated records remain logically unchanged

#### Scenario: Same-store publication preserves only valid completion history

- **GIVEN** iOS has shared version 3 completion history for the current store
- **WHEN** the same store publishes a rebuilt index
- **THEN** ranks are merged only for unchanged paths with the same store ID and root
- **AND** replacement stores, removed paths, and moved paths do not inherit old history

#### Scenario: Store removal clears all Autofill candidates

- **GIVEN** the canonical store has a published shared Autofill index
- **WHEN** its Disconnect or Delete flow starts
- **THEN** Android and iOS persist disabled native state before filesystem or config mutation
- **AND** candidate and credential reads fail closed even when a stale index file remains
- **AND** shared index and iOS credential identities are then removed
- **AND** no entry is decrypted during cleanup

#### Scenario: Tombstone cancels in-flight resolution

- **GIVEN** a candidate or identity was issued for publication generation `A`
- **AND** native query or credential decryption has started
- **WHEN** removal writes a disabled tombstone or a replacement publishes generation `B`
- **THEN** the provider returns no result from generation `A`
- **AND** no removed-store password reaches an intent, log, or platform response

#### Scenario: Store replacement cannot inherit old candidates

- **GIVEN** a prior canonical store was removed and a replacement is created, imported, or cloned
- **WHEN** the replacement becomes ready
- **THEN** the prior store's paths, aliases, completion history, and credential identities remain absent
- **AND** candidates appear only after an explicit path-derived rebuild for the replacement

#### Scenario: No-store native state publishes no passphrase

- **GIVEN** Flutter secure storage retains an explicitly remembered PGP passphrase
- **WHEN** no canonical ready store exists after removal
- **THEN** native Autofill remains disabled and publishes no passphrase
- **AND** the durable secure-storage preference is not itself exposed or deleted by index cleanup

#### Scenario: Replacement passphrase must match current recipients

- **GIVEN** secure storage retains a passphrase for fingerprint `ABC`
- **AND** a replacement store requires only fingerprint `DEF`
- **WHEN** native Autofill publication is evaluated
- **THEN** no passphrase is published
- **AND** the durable `ABC` record remains in secure storage

#### Scenario: Cleanup failure cannot revive a stale index

- **GIVEN** native state is disabled for store removal
- **AND** shared-index deletion fails
- **WHEN** a provider or replacement refresh observes the leftover index
- **THEN** the provider returns no candidates or credentials
- **AND** root-mismatched reconciliation removes the stale index and reports that an explicit rebuild is required

### Requirement: Encrypted login and URL enrichment SHALL be explicit and transactional

The system SHALL provide a separate opt-in operation that decrypts every indexed entry, stores a trimmed non-empty `login` value as the effective Autofill username, and stores only normalized `url` values as website/app aliases separately from path-derived identity. If any entry cannot be decrypted or validated, the existing index SHALL remain unchanged. Automatic reconciliation, incremental mutation, candidate query, metadata update, and credential resolution flows SHALL NOT invoke enrichment.

#### Scenario: Explicit enrichment adds login and normalized URL data

- **GIVEN** indexed entries contain `login` and `url` fields
- **WHEN** the user explicitly refreshes encrypted login and URL fields
- **THEN** every indexed entry is decrypted exactly once
- **AND** a non-empty `login` becomes that entry's effective Autofill username
- **AND** `example.com` is stored as an enriched website alias
- **AND** the raw URL and other decrypted content are not stored

#### Scenario: Enrichment failure preserves the previous index

- **GIVEN** one indexed entry cannot be decrypted
- **WHEN** enrichment runs
- **THEN** the operation fails
- **AND** none of the staged alias replacements is committed

#### Scenario: Forgetting enrichment clears login and URL data without decryption

- **GIVEN** enriched login and URL metadata exists
- **WHEN** the user chooses Forget login and URL fields
- **THEN** enriched logins and aliases are removed without decrypting entries
- **AND** path-derived services, usernames, and Autofill completion history remain available

### Requirement: Autofill SDK SHALL expose only the replacement path-first contract

The Rust core, Flutter Rust Bridge, native C/JNI JSON ABI, Dart repository, Android adapter, and iOS adapter SHALL use the version 3 path-first models and operations. Refresh and incremental requests SHALL omit PGP executable and passphrase fields; query requests SHALL expose website, human-readable app name, text query, and limit but SHALL omit Android package or favorite fields. Native providers SHALL use a dedicated completion-recording operation.

#### Scenario: Default lifecycle API cannot request decryption

- **WHEN** an SDK client constructs a rebuild, upsert, move, or remove request
- **THEN** the request model has no PGP backend, executable, passphrase, or decrypted-field input

#### Scenario: Query ABI has no package parameter

- **WHEN** Android or iOS constructs a native candidate query
- **THEN** the JSON request can contain website, app name, text query, and limit
- **AND** it cannot contain an Android package matching field

#### Scenario: Older schemas self-heal through automatic reconciliation

- **GIVEN** an Autofill index uses an older schema
- **WHEN** the GUI refreshes a valid password store
- **THEN** version 3 replaces it from current folder paths
- **AND** no entry is decrypted

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

Changes to Flutter Autofill settings, Android `RemoteViews`, Android authentication UI, or iOS credential-provider presentation SHALL NOT change the shared path-first schema, matching inputs, ranking rules, fail-closed behavior, passphrase authorization requirement, or selected-path-only resolution. Presentation state SHALL NOT cause whole-vault decryption or index rebuilding.

#### Scenario: Rendering a candidate performs no decryption
- **WHEN** Android or iOS renders one or more candidate presentations
- **THEN** it uses public indexed metadata
- **AND** no entry is decrypted until one authenticated candidate is selected

#### Scenario: Rendering Settings performs no secret enrichment
- **WHEN** the redesigned Settings home or Autofill detail route renders
- **THEN** it does not enrich login or URL fields or decrypt entries
- **AND** secret enrichment remains an explicit user action while path reconciliation remains automatic

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
