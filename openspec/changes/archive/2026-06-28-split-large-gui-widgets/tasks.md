## 1. Baseline and Boundaries

- [x] 1.1 Record current line counts for hand-written GUI screen files and identify the largest non-generated targets.
- [x] 1.2 Run the current focused Flutter widget tests that cover Settings, Manage, and Onboarding behavior.
- [x] 1.3 Create screen-local widget folders for Settings, Manage, and Onboarding without moving behavior yet.

## 2. Settings Extraction

- [x] 2.1 Extract reusable Settings section/tile/diagnostic widgets into Settings-local widget files.
- [x] 2.2 Extract security, biometric, PGP session, and passphrase storage sheet bodies into focused Settings widgets.
- [x] 2.3 Extract PGP and SSH key-management sheet content, row menus, import forms, export forms, and delete confirmation surfaces into focused Settings widgets.
- [x] 2.4 Extract password-store management forms and native path picker form bodies into focused Settings widgets.
- [x] 2.5 Extract Git sync, remotes, advanced args, and output panel surfaces into focused Settings widgets.
- [x] 2.6 Run focused Settings widget tests and fix any behavior-equivalent test imports or finders broken by extraction.

## 3. Manage Extraction

- [x] 3.1 Extract single-entry operation sheet bodies for generate, save, edit, move/rename, and delete into Manage-local widgets.
- [x] 3.2 Extract batch operation sheet bodies for move, rename, delete, and regenerate into Manage-local widgets.
- [x] 3.3 Extract entry picker, batch selection, selected preview, commit checkbox, submit button, error text, action card, and operation sheet layout into focused Manage widgets.
- [x] 3.4 Keep repository operations and user feedback coordination in `ManageScreen`.
- [x] 3.5 Run focused Manage widget tests and fix any behavior-equivalent test imports or finders broken by extraction.

## 4. Onboarding Extraction

- [x] 4.1 Extract step rail, biometric setup, empty step, review tile, and review step surfaces into Onboarding-local widgets.
- [x] 4.2 Extract PGP and SSH setup step bodies plus create/import key forms into focused Onboarding widgets.
- [x] 4.3 Extract store setup actions, store picker forms, and native path picker form bodies into focused Onboarding widgets.
- [x] 4.4 Keep step ordering, history navigation, finish rules, and app-level callbacks in `OnboardingScreen`.
- [x] 4.5 Run focused Onboarding widget tests and fix any behavior-equivalent test imports or finders broken by extraction.

## 5. Cleanup and Verification

- [x] 5.1 Remove dead private builders/helpers left behind by widget extraction.
- [x] 5.2 Re-check line counts and confirm the largest screen files now act primarily as coordinators.
- [x] 5.3 Run `dart format` on touched GUI files.
- [x] 5.4 Run `flutter test`.
- [x] 5.5 Run `flutter analyze`.
- [x] 5.6 Run `openspec validate split-large-gui-widgets --strict`.
