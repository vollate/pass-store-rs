## MODIFIED Requirements

### Requirement: Autofill index lifecycle SHALL support non-decrypting incremental updates

After an Autofill index has been initialized for the canonical store, successful Vault add, edit, move, delete, favorite, and recent operations SHALL update only affected logical index records. These operations SHALL NOT accept a PGP backend or passphrase and SHALL NOT decrypt entries. If no Autofill index exists, ordinary Vault mutations SHALL remain successful without implicitly creating one. Index updates SHALL be atomically published so platform providers never observe a partially written document. Before Disconnect or Delete mutates the store, native providers SHALL synchronously persist a disabled tombstone and reject all candidate/credential reads, then remove the shared index and platform identities. Every enabled native publication SHALL carry an unguessable generation in candidates and credential identities, and providers SHALL revalidate enabled state, root, index, and generation after query or decryption before returning a result. A later store SHALL require an explicit non-decrypting rebuild; reconciliation SHALL reject and remove an index whose store ID or root differs.

#### Scenario: Entry creation upserts one path-derived record

- **GIVEN** an Autofill index exists
- **WHEN** a new entry `gitlab.com/alice.gpg` is successfully created
- **THEN** one record with service `gitlab.com` and username `alice` is upserted
- **AND** no other entry is re-derived or decrypted

#### Scenario: Entry move preserves optional aliases

- **GIVEN** an indexed entry has ranking metadata and opt-in website aliases
- **WHEN** the entry is successfully renamed or moved
- **THEN** the old path is removed and new path metadata is derived
- **AND** existing ranking metadata and opt-in aliases are preserved
- **AND** no entry is decrypted

#### Scenario: Entry deletion removes only affected paths

- **GIVEN** an Autofill index exists
- **WHEN** an entry or folder is successfully deleted
- **THEN** matching entry path or path-prefix records are removed
- **AND** unrelated records remain logically unchanged

#### Scenario: Metadata-only read patches ranking without rebuild

- **GIVEN** an indexed entry is opened, favorited, or marked recent
- **WHEN** its ranking metadata changes
- **THEN** only supplied favorite and recent fields are patched
- **AND** no full index rebuild or entry decryption occurs

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
- **THEN** the prior store's paths, aliases, ranking metadata, and credential identities remain absent
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
