# GUI Redesign Baseline

Recorded before replacing production layouts.

## Representative Surfaces

| Surface | Current structure | Baseline issue retained for redesign comparison |
| --- | --- | --- |
| Vault home | Pinned app bar, Git chip, filled search, Recent cards, Browse cards, legacy three-item bottom bar | Card density, repeated Copy labels, fixed success icon, no visible Favorites section |
| Entry detail | Tall modal sheet, header, password surface, primary Copy, duplicate Reveal, wrapped action buttons, fields/notes | Duplicate reveal action, unstable action wrapping, Delete lacks distinct destructive hierarchy |
| Settings | Pinned app bar, long grouped card list, every domain opens a modal surface | Routine and advanced settings have equal weight; raw Autofill parser status can dominate a tile |
| Manage | Pinned app bar, eight action cards, separate batch selection panel | Single and batch operations are duplicated and detached from credential context |
| Onboarding | Fixed Gesture/Biometrics/PGP/SSH/Store/Review choice-chip rail | Technical six-step sequence and disabled chips consume compact space |
| Lock | Heading, optional biometric button, drawing-only gesture grid, inline error | No semantic dot activation/submit path and no manual lock entry from authenticated shell |
| Empty/loading/error | Generic card/list-tile empty state, linear/spinner loading, raw interpolated errors | Weak recovery hierarchy and unstable backend wording |

## Measured Source Debt

- 159 static production `Text` literals detected by the initial audit expression.
- 40 direct raw-error interpolation patterns across production Dart.
- 2 direct `Clipboard.setData` secret-copy paths.
- 0 literal empty production action callbacks.
- 31 modal bottom-sheet entry points and 9 dialog entry points in the pre-redesign source.
- 4 explicit `Semantics` widgets in the pre-redesign source.

The source-audit test initially treats the first three values as non-increase baselines. Final cleanup lowers approved production-facing literals, raw error presentation, and direct secret clipboard writes to zero or an explicitly classified non-user-facing allowlist.

## Responsive Evidence and Chosen Bounds

Existing tests and Android screenshots represent a 390 × 844 logical-pixel compact phone. Existing detail tests also use a 900-pixel-wide route and cap the old modal at 640 pixels. The redesign adopts Material-oriented width classes:

- Compact: `< 600` logical pixels — single-column content and bottom NavigationBar.
- Medium: `600–839` logical pixels — NavigationRail and bounded single-column/adaptive dialog content.
- Expanded: `>= 840` logical pixels — NavigationRail with bounded content or safe list-detail composition.

Initial shared maximums to validate during implementation:

- Readable form/detail body: 640 logical pixels.
- General single-column settings/vault body: 720 logical pixels.
- Expanded list-detail composition: 1100 logical pixels.

These are implementation constants, not device assumptions. Golden/structural tests at 390, 700, and 1100 logical pixels plus 200% text scaling determine whether later tuning is required.

## Privacy Baseline

The pre-redesign authenticated Android window does not apply `FLAG_SECURE`, iOS does not install an application-switcher privacy cover, and Vault-row copy does not share Entry Detail's delayed clipboard clearing. The redesign must change all three without modifying stored vault/key/Autofill data.
