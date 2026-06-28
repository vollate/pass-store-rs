## Baseline

Recorded before widget extraction on 2026-06-28.

Largest hand-written GUI files:

- `gui/lib/screens/settings/settings_screen.dart`: 2206 lines
- `gui/lib/screens/manage/manage_screen.dart`: 1530 lines
- `gui/lib/screens/onboarding/onboarding_screen.dart`: 1273 lines
- `gui/lib/screens/vault/entry_detail_sheet.dart`: 580 lines
- `gui/lib/screens/vault/vault_screen.dart`: 277 lines

Generated bridge files are excluded from this refactor.

Focused baseline verification:

- `flutter test test/mobile_gui_smoke_test.dart --name "settings|manage|onboarding"`
- Result: 52/52 tests passed

## Post-Extraction Line Counts

Recorded after screen-local widget extraction and review follow-ups.

Coordinator files:

- `gui/lib/screens/settings/settings_screen.dart`: 179 lines
- `gui/lib/screens/manage/manage_screen.dart`: 521 lines
- `gui/lib/screens/onboarding/onboarding_screen.dart`: 546 lines

Largest extracted screen-local widget files:

- `gui/lib/screens/settings/widgets/settings_security_widgets.dart`: 645 lines
- `gui/lib/screens/settings/widgets/settings_key_management_widgets.dart`: 583 lines
- `gui/lib/screens/settings/widgets/settings_git_widgets.dart`: 490 lines
- `gui/lib/screens/settings/widgets/settings_store_widgets.dart`: 470 lines
- `gui/lib/screens/onboarding/widgets/onboarding_store_setup_widgets.dart`: 460 lines
- `gui/lib/screens/manage/widgets/manage_batch_widgets.dart`: 423 lines
- `gui/lib/screens/manage/widgets/manage_single_entry_widgets.dart`: 399 lines

Focused integration verification:

- From `gui/`: `dart analyze lib/screens/settings lib/screens/manage lib/screens/onboarding`
- Result: no issues found
- `flutter test test/mobile_gui_smoke_test.dart --name "settings|manage|onboarding"`
- Result: 52/52 tests passed
- `dart format gui/lib/screens/settings/settings_screen.dart gui/lib/screens/settings/widgets gui/lib/screens/manage/manage_screen.dart gui/lib/screens/manage/widgets gui/lib/screens/onboarding/onboarding_screen.dart gui/lib/screens/onboarding/widgets`
- Result: 16 files checked, 0 changed

Final verification:

- `flutter test`
- Result: 116/116 tests passed
- `flutter analyze`
- Result: no issues found
- `openspec validate split-large-gui-widgets --strict`
- Result: valid
- `git diff --check`
- Result: clean

Review follow-ups:

- Converted Settings sheet bodies from extension-only inline builders into named
  widget classes for security, diagnostics, Git, and store surfaces.
- Moved Manage edit repository operations back into `ManageScreen` callbacks.
- Moved Onboarding store create/import/clone repository operations back into
  `OnboardingScreen` callbacks.
