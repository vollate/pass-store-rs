## Context

Autofill currently treats decrypted entry fields as its source of truth. `refresh_autofill_index_with_backend` recursively lists the store, decrypts each `.gpg` file, and extracts username, URL, service, and Android package fields. Flutter invokes that refresh from vault mutation paths, and metadata-only actions previously reached the same operation. With roughly 220 entries and a calibrated private-key unlock cost of about 55–65 ms per entry, this creates a 12–13 second serial delay even though one credential decrypt is already below the target.

Password-store paths already expose enough non-secret metadata for the desired convention. A logical path such as `github.com/alice` corresponds to `github.com/alice.gpg`: the immediate parent `github.com` is the service name and the final stem `alice` is the username. The SDK in this design means all shared integration surfaces: Rust core APIs and index schema, Flutter Rust Bridge DTOs, the native C/JNI JSON ABI, Dart repositories, and Android/iOS adapters.

The feature is unpublished. The existing index format and API can therefore be replaced directly; there is no compatibility or migration obligation.

## Goals / Non-Goals

**Goals:**

- Make default index creation, rebuild, candidate matching, and metadata maintenance perform zero PGP decryptions.
- Derive service identity from the immediate parent directory and username from the filename stem.
- Update one affected index entry or ranking record after ordinary vault operations instead of rebuilding every entry.
- Keep selected-credential resolution behind platform authentication and decrypt exactly the selected entry.
- Support native-app matching by human-readable app name without indexing or matching Android package identifiers.
- Keep encrypted URL-field matching available only through a separate, explicit opt-in enrichment operation.
- Replace the unpublished SDK and on-disk schema without legacy readers, wrappers, aliases, or fallback behavior.

**Non-Goals:**

- Android package-name matching, package-to-entry mappings, or `android-package` fields.
- Reading encrypted username fields for normal indexing or credential output.
- Automatic URL enrichment during rebuild, vault reads, ranking updates, or credential resolution.
- Private-key caches, plaintext secret caches, password-store format changes, or changes to platform authentication policy.
- Compatibility with any index or API shape created before this change.

## Decisions

### 1. The path is the authoritative autofill identity

For each normalized logical password path, the core derives:

- `username`: the final path component, equivalent to the `.gpg` filename stem;
- `service_name`: the immediate parent directory name;
- `path_website`: the normalized host form of `service_name` when it is host-like;
- `display_name`: `service_name` when present, otherwise `username` for a root-level entry.

A root-level entry has no exact service or website identity. It remains available through explicit text fallback using its path/stem. Encrypted username-like fields never override the path-derived username.

This makes the convention deterministic and testable without secret access. Searching all path ancestors was rejected because it makes nested category layouts ambiguous; the immediate parent is the single contract.

### 2. Replace the index schema in place

`AutofillIndexEntry` will contain path-derived metadata, ranking data, and optional enriched website aliases:

- `path`, `display_name`, `service_name`, `username`;
- `path_website` and `enriched_websites` kept separately so enrichment can be cleared without changing path identity;
- `is_favorite`, `recent_rank`, and update timestamp.

`android_packages` is removed. Raw URLs, decrypted fields, passwords, notes, and TOTP values are never persisted. The first released schema is written as the only supported schema; readers do not detect, migrate, or accept the previous development format. Invalid index data fails closed and produces no candidates until an explicit rebuild overwrites it.

Separate path and enrichment fields were chosen over one `websites` list because provenance is needed to disable or replace opt-in enrichment safely.

### 3. Replace the SDK with path-only lifecycle operations

The Rust core and FRB layer expose these operations, with corresponding request DTOs:

- `rebuild_autofill_index`: initialize or explicitly rebuild from the store path plus favorite/recent metadata; it has no PGP backend, executable, or passphrase arguments.
- `upsert_autofill_index_entry`: derive and insert/replace one created or edited path if an index exists.
- `move_autofill_index_entry`: replace an old path with a newly derived path while preserving ranking and existing enriched aliases.
- `remove_autofill_index_entry`: remove one deleted path or a path prefix for a deleted folder.
- `patch_autofill_index_ranking`: update favorite/recent fields for supplied paths only.
- `enrich_autofill_index_websites`: explicitly decrypt a non-empty set of indexed paths and replace their normalized URL aliases transactionally.
- `query_autofill_candidates`, `resolve_autofill_credential`, and `clear_autofill_index`: retain their roles with replaced request models.

Incremental operations are no-ops when the user has not initialized an autofill index. All mutating operations perform an atomic temporary-file write and rename. The JSON file is serialized as a whole, but only affected logical records are re-derived; there is no entry decryption.

A generic “refresh with backend” operation and compatibility overloads were rejected because they preserve the accidental ability to decrypt the vault from routine lifecycle code.

### 4. Candidate queries use website, app name, or text—never package name

`AutofillQueryRequest` contains `website`, `app_name`, `query`, and `limit`; `android_package` is removed from Rust, FRB, C/JNI JSON, Kotlin, and Swift request models.

Matching uses these score bands:

1. exact normalized `path_website` match;
2. exact case-insensitive `service_name`/human-readable app-name match;
3. exact opt-in `enriched_websites` match;
4. path, display-name, service-name, or username text fallback.

Favorite and recent bonuses remain smaller than the gaps between match classes, so they reorder equivalent matches but never turn a fallback into an exact match.

Android obtains a caller's human-readable application label through `PackageManager` and passes only that label as `app_name`. The package identifier is not sent to the core or stored. Web domains continue through `website`. iOS uses service identifiers for websites and the extension's query text for fallback; only host-like identities are registered with `ASCredentialIdentityStore`.

Using package identifiers as a hidden fallback was rejected because it would recreate the mapping model that this change deliberately removes.

### 5. Credential resolution decrypts one entry and trusts the index for username

After platform local authentication, `resolve_autofill_credential` verifies that the requested normalized path is indexed, decrypts that one `.gpg` file, and returns:

- the path-derived indexed username;
- the first-line password from the decrypted entry.

Resolution does not inspect username or URL fields for output/index updates and does not write the index. This gives the selected flow a measurable invariant: one successful request equals one backend decrypt call.

### 6. URL enrichment is explicit, bounded, and transactional

Default rebuild and incremental APIs have no secret-bearing arguments. The separate enrichment request requires an explicit non-empty path list plus the normal PGP configuration/passphrase. It decrypts only those paths, extracts and normalizes values from `url`, `website`, and `service` fields, and stages all replacements in memory. If any path cannot be decrypted or validated, the existing index remains unchanged.

Settings exposes enrichment as a separate opt-in action with clear wording that it reads encrypted entries. Disabling enrichment clears `enriched_websites`; it does not rebuild path metadata. Normal entry opens and selected credential resolution do not opportunistically enrich.

### 7. Flutter owns mutation-to-index orchestration

`BridgeBackedRepository` calls an incremental autofill operation only after the corresponding vault mutation succeeds:

- insert/edit: upsert the resulting path;
- rename/move: move the old path to the new path;
- delete: remove the path or prefix;
- favorite/recent: patch ranking only.

Metadata-only entry reads never invoke rebuild. Batch changes from Git/store refresh use a path-only reconciliation of before/after entry summaries; the Settings “Refresh autofill data” action is the only ordinary full rebuild. Platform-state publication follows successful index writes and iOS identity synchronization uses the updated path-derived hosts.

## Risks / Trade-offs

- **[Existing stores may not follow `service/username.gpg`]** → Document the convention, retain text fallback, and make root-level entries queryable but not exact service matches.
- **[Android app labels can differ from directory spelling or locale]** → Compare case-insensitively after trimming/collapsing whitespace and allow manual text fallback; do not introduce package mappings.
- **[Optional URL enrichment still costs one decrypt per selected path]** → Keep it disabled by default, explicit, bounded by a supplied path list, and transactional.
- **[Concurrent app/provider reads could observe partial JSON]** → Use atomic replace for every index write and publish/sync platform state only after success.
- **[A moved entry's enriched alias may no longer describe its directory]** → Preserve it because it came from encrypted content; users can clear or rerun enrichment explicitly.
- **[Direct replacement rejects development-era index files]** → Fail closed and require explicit rebuild; do not add migration or compatibility code.

## Replacement Plan

1. Replace core models, path derivation, matching, atomic persistence, lifecycle APIs, and tests.
2. Replace bridge DTOs/functions and regenerate Rust/Dart FRB bindings; delete old refresh/package symbols.
3. Replace Dart repository orchestration with incremental calls and a path-only explicit rebuild.
4. Replace Android and iOS ABI/request models and platform matching adapters.
5. Replace settings labels/actions and iOS identity publication; add separate enrichment controls.
6. Delete tests and fixtures for decrypted username/package indexing, then add zero/one-decrypt invariants and platform integration coverage.
7. Clear developer indexes during test setup and build new release artifacts. No migration, dual-write, rollout flag, or rollback compatibility path is included.

## Open Questions

None.
