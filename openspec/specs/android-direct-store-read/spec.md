# android-direct-store-read Specification

## Purpose

Document authorized Android direct-filesystem recovery of a user-selected
password store when the DocumentsProvider cannot enumerate the granted tree.

## Requirements

### Requirement: Direct store reading SHALL run only after provider enumeration fails

The Android importer SHALL expose direct-filesystem enumeration only as a recovery from a provider fault reported by Import. It SHALL NOT run when the provider enumerated the selected root, SHALL NOT run before provider enumeration has been attempted with its loading retries, and SHALL NOT be selected merely because the required authorization is already held.

Sources: `gui/android/app/src/main/kotlin/top/vollate/pars_gui/ManagedStoreImporter.kt`, `gui/lib/services/path_picker_service.dart`

#### Scenario: Working provider never reaches the direct path

- **GIVEN** the provider returns children for the granted root
- **WHEN** Import stages the selected tree
- **THEN** staging uses provider enumeration only
- **AND** the direct-read entry point is not invoked

#### Scenario: Held authorization does not bypass the provider

- **GIVEN** all-files access is already granted
- **AND** the provider can enumerate the granted root
- **WHEN** Import stages the selected tree
- **THEN** staging still uses provider enumeration
- **AND** no direct filesystem read occurs

### Requirement: Direct store reading SHALL require explicit contextual authorization

The direct read SHALL require all-files access and SHALL verify that authorization immediately before each attempt rather than caching an earlier result. Authorization SHALL be requested only at the moment a provider fault has already been reported, through the system settings destination for this package, and SHALL NOT be requested at startup, during onboarding, or as a precondition for ordinary Import. A declined, dismissed, or revoked authorization SHALL leave Import reporting the provider fault.

Sources: `gui/android/app/src/main/kotlin/top/vollate/pars_gui/ManagedStoreImporter.kt`, `gui/android/app/src/main/AndroidManifest.xml`, `gui/lib/services/path_picker_service.dart`

#### Scenario: Authorization is requested only after a provider fault

- **GIVEN** a user starts Import and the provider enumerates normally
- **WHEN** the import completes
- **THEN** all-files access was never requested

#### Scenario: Declining authorization preserves the provider fault

- **GIVEN** Import reported a provider fault and offered the direct read
- **WHEN** the user declines or returns from settings without granting access
- **THEN** no filesystem read is attempted
- **AND** Import reports the localized provider-fault outcome

#### Scenario: Revoked authorization is detected before reading

- **GIVEN** all-files access was granted earlier in the session
- **WHEN** it has been revoked before a direct read attempt
- **THEN** the attempt is refused
- **AND** Import reports the provider-fault outcome without reading the filesystem

### Requirement: Direct store reading SHALL accept only a picker-granted tree URI it can resolve

The direct read SHALL accept a tree URI obtained from the directory picker and SHALL NOT accept a caller-supplied filesystem path. It SHALL resolve a path only for the platform external-storage authority, by splitting the tree document ID into volume and relative parts and mapping the volume through the system storage volumes. The resolved path SHALL be canonicalized and SHALL be an existing directory contained within that volume's directory. An unsupported authority, an unresolvable volume, or a containment failure SHALL be reported as an unrecoverable provider fault rather than read from a guessed location.

Sources: `gui/android/app/src/main/kotlin/top/vollate/pars_gui/ManagedStoreImporter.kt`

#### Scenario: Primary volume tree resolves to its directory

- **GIVEN** a granted tree URI for the external-storage authority with document ID `primary:password-store`
- **WHEN** the direct read resolves the selection
- **THEN** the resolved directory is `password-store` within the primary volume directory
- **AND** the resolved path is canonicalized and confirmed to be an existing directory

#### Scenario: Cloud or unknown authority is unrecoverable

- **GIVEN** a granted tree URI whose authority is not the platform external-storage provider
- **WHEN** the direct read is attempted
- **THEN** no path is resolved
- **AND** Import reports an unrecoverable provider fault

#### Scenario: Caller-supplied path is refused

- **WHEN** the direct-read entry point receives a filesystem path instead of a tree URI
- **THEN** the request fails closed
- **AND** no directory is read or staged

#### Scenario: Resolution outside the volume is refused

- **GIVEN** a document ID whose relative part escapes the volume directory
- **WHEN** the direct read resolves the selection
- **THEN** containment validation fails
- **AND** no directory is read or staged

### Requirement: Direct store reading SHALL be read-only and reuse the existing staging transaction

The direct read SHALL open files read-only and SHALL NOT create, modify, move, or delete anything in shared storage. It SHALL confine traversal to the resolved selected directory and SHALL produce the same staging directory, opaque handle, and destination as the provider path, handing off to the unchanged finalize, commit, and rollback seams. It SHALL re-apply the traversal rejections used by the provider path, including unsafe names, duplicate names, directory cycles, path escape, non-regular entries such as symbolic links, and the maximum directory depth. Staged results SHALL still undergo Git classification.

Sources: `gui/android/app/src/main/kotlin/top/vollate/pars_gui/ManagedStoreImporter.kt`

#### Scenario: Source tree is left unchanged

- **GIVEN** a direct read of a selected store folder
- **WHEN** staging completes
- **THEN** the source directory contents and modification state are unchanged
- **AND** no file was opened for writing

#### Scenario: Recovered import uses the normal transaction

- **GIVEN** a successful direct read
- **WHEN** staging completes
- **THEN** it returns an opaque handle and the app-managed destination
- **AND** finalize, commit, and rollback behave as they do for a provider-staged import

#### Scenario: Unsafe entries are rejected during direct traversal

- **GIVEN** the selected directory contains a symbolic link, a directory cycle, or an unsafe name
- **WHEN** the direct read traverses it
- **THEN** the import fails closed
- **AND** no staging directory is left behind

#### Scenario: Recovered store is still classified for Git

- **GIVEN** a direct read staged a store without `.git`
- **WHEN** Import classifies the staged result
- **THEN** the absent-Git decision is presented as it is for provider-staged imports
