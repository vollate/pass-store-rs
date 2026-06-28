## Context

The Flutter GUI has accumulated several large hand-written screen files. The
largest current targets are `settings_screen.dart` at roughly 2200 lines,
`manage_screen.dart` at roughly 1500 lines, and `onboarding_screen.dart` at
roughly 1270 lines. These files mix route-level orchestration with repeated
sheet layout, form state, row rendering, confirmation dialogs, and helper
widgets. Generated bridge files are larger, but they are intentionally out of
scope.

This change is a structural refactor. It should improve editability and review
focus without changing visible behavior, bridge/repository APIs, navigation, or
package dependencies.

## Goals / Non-Goals

**Goals:**

- Reduce the largest GUI screen files by extracting focused widgets and sheet
  bodies into screen-local modules.
- Keep top-level screen classes responsible for routing, repositories,
  app-level callbacks, selected tabs/steps, and cross-widget coordination.
- Preserve current UI behavior, labels, semantics, error handling, repository
  calls, and widget-test coverage.
- Use existing Flutter patterns already present in the project: constructor
  parameters, callbacks, local stateful widgets for form state, and small
  stateless widgets for rows/sections.

**Non-Goals:**

- No visual redesign, copy rewrite, route restructure, or navigation change.
- No bridge, repository, model, or generated-code refactor.
- No new state-management framework or package dependency.
- No broad test rewrite beyond adjusting imports/finders if widget extraction
  requires it.

## Decisions

1. Extract by screen domain, not by generic utility first.

   Settings, Manage, and Onboarding each have domain-specific flows with
   different dependencies. New files should live under screen-local `widgets/`
   directories first, such as `gui/lib/screens/settings/widgets/`, so the
   ownership boundary remains obvious. Truly shared widgets can move to
   `gui/lib/widgets/` only when at least two screens already need the same
   behavior.

   Alternative considered: create a broad shared UI library immediately. That
   would make the refactor larger and risks abstracting before the duplicated
   shape is proven.

2. Keep screen files as coordinators.

   The existing top-level screen classes should continue to receive
   repositories and callbacks, decide which sheet/dialog to open, and translate
   completed widget interactions into repository operations. Extracted widgets
   should receive plain data and callbacks rather than importing or owning broad
   app services unless they already represent an isolated form with one clear
   dependency.

   Alternative considered: move most business actions into extracted widgets.
   That would shrink files faster, but it would blur repository ownership and
   make test setup less predictable.

3. Refactor one screen area at a time with behavioral tests as the guardrail.

   Settings should be split first because it is the largest and recently
   changed. Manage and Onboarding should follow with smaller, reviewable slices.
   After each screen area, run focused widget tests before continuing.

   Alternative considered: mechanically split all widgets in one pass. That is
   faster on paper but makes regressions harder to locate.

4. Prefer private extracted widgets unless a public API is needed.

   Most extracted widgets should be implementation details of their screen
   domain. File-level names can still be descriptive, but exported public
   surfaces should stay small to avoid creating a new API burden.

## Risks / Trade-offs

- File count increases -> Keep folders shallow and group files by screen domain,
  not by tiny one-off helpers.
- Callback plumbing gets noisy -> Pass small, explicit callback sets and avoid
  omnibus controller objects unless repetition becomes painful.
- Widget extraction may change keys, semantics, or finder paths -> Preserve
  visible text and semantics labels, and update tests only when assertions remain
  behavior-equivalent.
- Refactor may accidentally change repository call order -> Keep repository
  operations in screen coordinators where possible and run the full Flutter test
  suite before completion.

## Migration Plan

1. Add focused tests or assertions around the screen areas being split when
   coverage is thin.
2. Extract Settings sheets, forms, and row widgets into
   `gui/lib/screens/settings/widgets/` while preserving the existing
   `SettingsScreen` constructor and behavior.
3. Extract Manage operation sheet bodies and reusable panels into
   `gui/lib/screens/manage/widgets/`.
4. Extract Onboarding step bodies, key forms, store setup actions, and form
   sheets into `gui/lib/screens/onboarding/widgets/`.
5. Run focused tests after each screen and finish with `flutter test`,
   `flutter analyze`, and strict OpenSpec validation.

Rollback is a normal Git revert of this refactor because it does not require
data migration or API changes.

## Open Questions

None. The implementation should stop and update this design if extracting a
widget requires changing behavior, APIs, routes, or state ownership.
