# Verification: GUI Empty-Implementation Audit

## Scope and Method

The audit covers non-generated production sources under:

- `gui/lib/**/*.dart`
- `gui/android/app/src/main/**/*.{kt,java}`
- `gui/ios/**/*.{swift,m,mm}` excluding test and generated/vendor folders

The scan looks for literal empty action callbacks, empty method bodies,
unimplemented markers, placeholder copy, and action handlers that are always
`null`. Every match is manually classified because an empty closure can still
have framework semantics (for example, `setState(() {})` triggers a rebuild).

## Before-Implementation Inventory

| Finding | Location | Reachability | Classification | Planned treatment |
| --- | --- | --- | --- | --- |
| Edit uses `onPressed: () {}` | `gui/lib/screens/vault/entry_detail_sheet.dart` | Reachable after entry decrypt | User-visible defect | Route to focused edit workflow |
| Regenerate uses `onPressed: () {}` | `gui/lib/screens/vault/entry_detail_sheet.dart` | Reachable after entry decrypt | User-visible defect | Route to focused single-entry regeneration |
| Delete uses `onPressed: () {}` | `gui/lib/screens/vault/entry_detail_sheet.dart` | Reachable after entry decrypt | User-visible defect | Route to focused confirmed deletion |
| Directory branch supplies `onCopy: () {}` | `gui/lib/screens/vault/vault_screen.dart` | Callback is unreachable because `EntryTile` omits Copy for directories | Callback-plumbing debt | Make `onCopy` nullable and pass `null` |
| Git fallback says it is mocked and will be wired later | `gui/lib/screens/settings/widgets/settings_security_widgets.dart` | Reachable only when `GitRepository` lacks `GitOperationsRepository`; production bridge repository supports it | Stale unavailable-state copy | Replace with explicit unavailable explanation |
| Empty `setState(() {})` closures | Flutter widgets under `gui/lib/` | Reachable | Intentional framework behavior: schedules rebuild | Preserve; source regression only targets action properties |
| Empty methods in `FakeParsRepository` | `gui/lib/services/fake_pars_repository.dart` | Used by `ParsGuiApp.fake()` tests/demo, not production `main.dart` | Test fixture | Preserve unless a focused test needs a recording fake |
| Empty FRB initializer | `gui/lib/bridge/frb_generated/frb_generated.dart` | Generated | Generated implementation | Preserve and exclude from audit guard |
| `UnimplementedError` references in path picker | `gui/lib/services/path_picker_service.dart` | Error handlers around plugin calls | Plugin capability error handling, not a thrown stub | Preserve |
| Android `result.notImplemented()` | `MainActivity.kt`, `ManagedStoreImporter.kt` | Unknown method-channel names only | Required framework response | Preserve |
| iOS `FlutterMethodNotImplemented` | `gui/ios/Runner/AppDelegate.swift` | Unknown method-channel names only | Required framework response | Preserve |
| Android application/signing TODO comments | `gui/android/app/build.gradle.kts` | Build configuration | Deployment configuration debt, outside GUI action behavior | Preserve for a dedicated signing change |
| Conditional `onChanged: null` | Manage shared entry picker | Only when the caller disables selection | Intentional disabled state | Preserve |

No production Kotlin or Swift method body was found empty. No additional
reachable literal empty `onPressed`, `onTap`, or `onLongPress` implementation
was found beyond the three entry-detail defects and the unreachable directory
copy callback described above.

## After-Implementation Inventory

The post-implementation scan found:

- **0** literal empty production action handlers assigned to `onPressed`,
  `onTap`, `onLongPress`, `onDoubleTap`, `onSecondaryTap`, or `onSubmitted`.
- **0** stale `coming soon`, `not implemented`, `mocked in phase`, or
  `wired ... later` production placeholder messages.
- **6** syntactically empty methods, all classified and intentionally retained:
  five fixture methods in `FakeParsRepository` and one generated FRB
  initializer.
- **2** `UnimplementedError` catches in the path picker, both plugin capability
  error handling.
- **2** Android and **2** iOS unknown-method responses, all standard
  MethodChannel behavior.
- No empty production Kotlin or Swift method body.

The three entry-detail controls now emit concrete actions, the directory copy
callback is nullable instead of a dummy closure, and the Git fallback presents
an explicit unavailable state.

## Behavioral Verification

Focused Flutter tests:

- `gui/test/gui_empty_action_regression_test.dart`
- `gui/test/vault_entry_actions_test.dart`
- Result: **9/9 passed**.

The focused tests verify disabled unsupported controls, all three callbacks,
detail disposal before mutation navigation, cancellation, exact edit path,
one-entry regeneration with length 24 and symbol policy, metadata/note
preservation, display-label delete confirmation, non-recursive entry deletion,
success notifications, actionable errors, and explicit post-mutation Git
commit failure wording.

Full Flutter validation:

- `flutter test`: **180 tests passed**.
- `flutter analyze`: **No issues found**.
- `dart format --output=none --set-exit-if-changed` on all files changed by this
  change: **11 files, 0 changes required**.
- A broader package format probe identified two pre-existing unrelated files
  (`lib/component/search_bar.dart` and `test/pgp_import_service_test.dart`);
  they were not modified by this focused change.

Final planning validation:

- `openspec validate audit-and-complete-gui-actions --strict`: **passed**.
- `git diff --check`: **passed**.
- Dart LSP diagnostics across all changed production and test files: **0**.
