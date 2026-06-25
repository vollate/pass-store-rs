# store-lifecycle Specification

## Purpose

Document implemented password store lifecycle, app-state inspection, and
onboarding recovery behavior.

## Requirements

### Requirement: App-state inspection SHALL report config, selected store, stores, issues, and onboarding state

Bridge app-state inspection SHALL return whether config exists, selected store
ID/root, all configured store statuses, aggregated issues, and an onboarding
state string.

Sources: `bridge/src/api.rs`, `gui/lib/services/store_lifecycle.dart`,
`bridge/tests/bridge_smoke_test.rs`

#### Scenario: Missing config returns no_config

- GIVEN the config path does not exist
- WHEN app state is inspected
- THEN `config_exists` is false
- AND `onboarding_state` is `no_config`
- AND issues include `no_config`

### Requirement: Store inspection SHALL detect missing store, missing `.gpg-id`, missing remote, and missing private key

For each configured store, inspection SHALL check directory existence, root
`.gpg-id`, Git remote when the store is a Git repository, and missing private
PGP keys when a PGP executable is provided.

Sources: `bridge/src/api.rs`, `bridge/tests/bridge_smoke_test.rs`

#### Scenario: Non-Git local store can be ready

- GIVEN a local store exists
- AND it has `.gpg-id`
- AND it is not a Git repository
- WHEN app state is inspected
- THEN onboarding state can be `ready`
- AND `git_remote_missing` is not reported

#### Scenario: Git repo without remote reports remote issue

- GIVEN a store exists
- AND it is a Git repository
- AND `git remote` returns no remotes
- WHEN app state is inspected
- THEN issues include `git_remote_missing`

### Requirement: List stores SHALL derive store info from config repos

Bridge list-stores SHALL load config when a config path is supplied, or default
config otherwise. It SHALL return store IDs as `store-<index>`, names from the
root directory basename, roots as configured paths, and `is_default` based on
`path_config.default_repo`.

Sources: `bridge/src/api.rs`, `gui/lib/services/settings_repository.dart`

#### Scenario: Default store is identified by root path

- GIVEN a repo path equals `path_config.default_repo`
- WHEN stores are listed
- THEN that store has `is_default=true`

### Requirement: Store selection SHALL require configured store root

Selecting a store SHALL normalize the requested root, require it to already
exist in `path_config.repos`, set it as `default_repo`, and save config.

Sources: `bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Unknown store root is rejected

- GIVEN a requested root is not in config repos
- WHEN store selection runs
- THEN a validation error is returned

### Requirement: Create, import, and clone SHALL add stores to config

Create-local-store SHALL create the root, write `.gpg-id` from non-empty PGP
keys, optionally initialize Git, add the root to config repos, and optionally
make it default. Import-local-store SHALL require an existing directory and add
it to config. Clone-store SHALL reject existing target path, create the parent
directory when needed, run `git clone`, and add the cloned root to config.

Sources: `bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`,
`bridge/tests/bridge_smoke_test.rs`

#### Scenario: Create local store validates PGP keys

- WHEN create-local-store receives only blank PGP keys
- THEN validation fails with an at-least-one-key error

#### Scenario: App-managed repository skips local Git initialization

- GIVEN Flutter repository has managed store base directory
- WHEN createLocalStore is requested with `initializeGit=true`
- THEN the bridge request sends `initializeGit=false`

### Requirement: Remove store SHALL update config without deleting files

Remove-store SHALL remove the normalized root from config repos and adjust
`default_repo` to the first remaining repo or empty string when the removed
root was default. It SHALL not delete the store directory.

Sources: `bridge/src/api.rs`, `gui/lib/services/settings_repository.dart`

#### Scenario: Default root removal selects next repo

- GIVEN the removed root is the default repo
- WHEN remove-store saves config
- THEN default repo becomes the first remaining configured repo or empty string

### Requirement: Delete local store SHALL require exact confirmation and configured root

Delete-local-store SHALL require confirmation equal to the full normalized
store root, require the root to be configured and exist as a directory, refuse
filesystem root deletion, remove the root from config, save config, and delete
the directory tree.

Sources: `bridge/src/api.rs`, `gui/lib/services/bridge_backed_repository.dart`

#### Scenario: Confirmation must match root

- GIVEN confirmation does not equal the store root
- WHEN delete-local-store runs
- THEN validation fails

### Requirement: Onboarding store actions SHALL offer create, import, and clone paths

Flutter onboarding SHALL offer local store creation, local store import, and Git
store clone when store lifecycle requires setup. When app-managed paths are
available, store roots SHALL be derived from store name or remote URL.

Sources: `gui/lib/screens/onboarding/onboarding_screen.dart`,
`gui/lib/services/bridge_backed_repository.dart`,
`gui/test/bridge_backed_repository_test.dart`

#### Scenario: Remote URL derives app-managed store root

- GIVEN managed store base `/app/support/stores`
- WHEN remote URL is `git@example.com:org/passwords.git`
- THEN derived root is `/app/support/stores/passwords`

## Needs Verification

- The create-local-store request has a `name` field, but bridge create logic
  does not currently use that field except through callers that may derive the
  root path. Intended semantics need verification.
- Clone-store invokes literal `git clone`, not configured Git executable.
- Store deletion is intentionally destructive; UI/UX confirmation coverage was
  inspected in code but not through an end-to-end test.
