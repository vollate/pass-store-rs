## Context

A production-source audit of `gui/` found three genuine user-visible empty handlers, all in `gui/lib/screens/vault/entry_detail_sheet.dart`: Edit, Regenerate, and Delete each use `onPressed: () {}`. The same condition is already recorded under `flutter-vault-and-manage` Needs Verification.

The audit also found code that looks empty but has different semantics:

- `setState(() {})` closures intentionally schedule a rebuild and are not no-ops.
- The directory branch in `VaultScreen` supplies `onCopy: () {}`, but `EntryTile` does not render its copy control for directories; this is unreachable callback plumbing rather than a user-visible defect.
- `SystemPathPickerService` catches plugin `UnimplementedError`; it does not throw one as an implementation stub.
- Android/iOS method channels return `notImplemented` only for unknown method names, as required by Flutter channel conventions.
- Empty methods in `FakeParsRepository`, test doubles, and generated FRB initialization are fixtures/generated behavior and are not used by the production app in `main.dart`.
- Android debug-key release signing TODOs are deployment configuration debt, not empty GUI actions.
- The Settings Git placeholder is a fallback reached only when the supplied `GitRepository` lacks `GitOperationsRepository`; production uses the bridge-backed operations repository, but the fallback copy should describe an unavailable capability instead of claiming a future mocked phase.

Existing edit, regenerate, delete, commit, confirmation, and error behavior already exists in the Manage screen. The defect is orchestration and reuse, not missing repository or bridge operations.

## Goals / Non-Goals

**Goals:**

- Make every action displayed in loaded entry detail perform a visible, testable operation.
- Reuse existing `ManageRepository` mutation semantics and confirmation rules.
- Clear the decrypted detail sheet before opening a mutation workflow.
- Remove unreachable literal empty callback plumbing and stale placeholder wording identified by the audit.
- Add a narrowly scoped source-regression check for literal empty user-action handlers.
- Preserve a documented classification of intentional empty-looking constructs.

**Non-Goals:**

- Implement or alter Rust/bridge entry mutation APIs.
- Change password generation policy, ciphertext format, PGP preparation, Autofill contracts, or Git commit semantics.
- Turn all test doubles into persistent in-memory repositories.
- Replace framework-standard unknown-method responses or generated code.
- Configure production Android signing as part of this GUI behavior fix.

## Decisions

### 1. Entry detail emits an action; Vault owns mutation workflow navigation

`EntryDetailSheet` will receive non-empty Edit, Regenerate, and Delete callbacks. `VaultScreen` will close the detail route with a typed action result and only then open the selected operation sheet.

This keeps entry detail responsible for displaying one decrypted secret while Vault coordinates routes and repository capabilities. Closing first invokes detail disposal and secret clearing, avoids stacked mutation sheets, and prevents stale decrypted content from remaining visible after edit or deletion.

**Alternative considered:** Call `ManageRepository` directly inside `EntryDetailSheet`. This couples secret presentation to mutation forms and leaves the loaded sheet needing complex reload/removal behavior after success.

### 2. Extract reusable focused launchers from existing Manage workflows

The Manage library will expose focused single-entry sheet launchers that internally reuse the existing private widgets and helpers:

- Edit loads the selected entry and supports saving reconstructed content or replacing only the first line.
- Regenerate presents a single-entry title/options and calls `batchRegenerateEntries` with exactly one entry, preserving parsed fields and notes through the existing replacement path.
- Delete shows the full path, requires the existing human-readable display-label confirmation, and calls `deleteEntry` non-recursively for the detail entry.
- Optional commit uses the same repository `commitChanges` messages and result decoration as Manage.

Focused launchers avoid duplicating field reconstruction, submit state, confirmation, and error handling. Existing Manage screen behavior remains unchanged.

**Alternative considered:** Navigate users to the Manage tab. That loses entry context and does not satisfy the immediate action implied by the detail controls.

### 3. Mutation results return to Vault for notification

After a focused sheet succeeds, Vault will show the existing `EntryOperationResult` or `BatchOperationResult` summary through `AppNotification` and rebuild from repository state. Cancellation returns silently to Vault. Errors remain visible in the operation sheet and do not dismiss it.

If the supplied vault repository does not implement `ManageRepository`, action callbacks will be absent and controls will be disabled rather than wired to a no-op. The production bridge-backed repository implements `ManageRepository`.

### 4. Remove dummy callbacks instead of allowlisting them

`EntryTile.onCopy` will become nullable so directory tiles can pass `null`; the tile already omits the copy button for directories. A test will scan production Dart source for literal empty user-action handlers such as `onPressed: () {}` and `onTap: () {}`. It will not scan generated files, tests, or generic closures such as `setState(() {})`.

This creates a focused guard without treating legitimate framework patterns as defects.

### 5. Replace stale fallback copy, not missing platform functionality

The Git fallback sheet will report that Git operations are unavailable for the supplied repository. It will not claim to be a mocked phase or offer controls that cannot run. No platform service is added because production already provides the operations repository.

## Risks / Trade-offs

- **[Private Manage widgets become reusable API surface]** → Expose only top-level focused launcher functions; keep form widget classes private to the Manage library.
- **[Detail closes before a user cancels the mutation form]** → This deliberately clears decrypted content; cancellation returns to Vault and the entry can be reopened.
- **[Single-entry regenerate uses a batch repository method]** → Pass exactly one selected entry and present singular UI copy; retain the established metadata-preserving implementation until generator policy is changed separately.
- **[Source-regression regex produces false positives]** → Restrict it to action-property assignments in non-generated `gui/lib` Dart files and require manual classification for any future exception.
- **[Repository mutation succeeds but optional Git commit fails]** → Preserve existing Manage behavior: surface the error without pretending the underlying mutation rolled back.
