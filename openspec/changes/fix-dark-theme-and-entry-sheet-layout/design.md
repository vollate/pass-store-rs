## Context

`ParsTheme.dark()` already provides a dark `InputDecorationTheme`, and the current hand-written `TextField` and `TextFormField` instances inherit that theme without local light fill overrides. The bright rectangle reported in the entry detail screenshot is instead the masked-password `DecoratedBox`, whose fill is hard-coded to the light theme's `#E2E8F0` value.

`EntryDetailSheet` renders separate widget trees for passphrase, loading, error, and loaded states. The loading tree contains only a minimum-size column with a handle and progress indicator. Under Material 3 modal constraints, that child can determine the bottom sheet's intrinsic width, so the modal collapses during decryption and expands again when content arrives.

## Goals / Non-Goals

**Goals:**

- Make the entry detail secret surface visually appropriate and readable in light and dark themes.
- Confirm that all GUI text inputs continue to derive their fill from the active input decoration theme and correct any audit findings.
- Keep the entry detail modal at the maximum width allowed by its route constraints in every asynchronous state.
- Add regression tests that exercise the actual dark theme and the loading-to-content transition.

**Non-Goals:**

- Redesigning the entry detail actions, typography, spacing, or information hierarchy.
- Changing QR-code white backgrounds, which are intentionally retained for scanning contrast.
- Changing PGP decryption, passphrase-session behavior, repository APIs, or secret handling.
- Introducing a new shared modal framework or restyling unrelated bottom sheets.

## Decisions

### Use theme-derived semantic surface colors

The password display will use a surface color obtained from the active theme rather than a brightness check or a duplicated dark-mode constant. The preferred source is the configured input decoration fill, with a color-scheme container color as a fallback, because the display is intentionally styled like an input while remaining read-only. Its text and icon will continue to inherit theme foreground colors.

A repository-wide audit will verify that editable text fields do not specify hard-coded light fills. Only confirmed violations will be changed; the existing centralized light and dark `InputDecorationTheme` definitions remain the source of truth.

Alternatives considered:

- Branching on `Brightness.dark` and selecting constants would fix the screenshot but duplicate theme policy in a feature widget.
- Converting the password display into a disabled `TextField` would gain automatic fill behavior but introduce unnecessary editing semantics and accessibility behavior.

### Make the detail sheet root request the available modal width

`EntryDetailSheet` will apply a full-width constraint at a state-independent boundary so passphrase, loading, error, empty, and loaded branches all receive the same horizontal contract. The modal route's own constraints, including Material 3's desktop maximum, remain authoritative; the widget only requests all width available inside those constraints.

This is preferred over adding a wide invisible child to the loading column because it expresses the actual layout requirement and prevents the same regression in another compact state. Applying a fixed pixel width was rejected because it would not adapt across phones, tablets, desktop windows, and orientation changes.

### Test rendered properties and state transitions

Widget tests will render with `ParsTheme.dark()` and assert that the password surface resolves to a dark/theme-derived fill. A modal test with a controllable delayed repository read will compare the bottom sheet width while loading and after content loads, asserting both remain at the available route width. Existing functional tests remain in place to guard secret loading and actions.

## Risks / Trade-offs

- **[Risk] Theme-derived colors may differ slightly from the existing light fill.** → Prefer the configured input fill so the light appearance remains stable and add assertions against theme values rather than raw constants.
- **[Risk] Full-width requests could produce an oversized desktop sheet.** → Preserve the modal route and Material 3 maximum-width constraints instead of setting an absolute width.
- **[Risk] A broad color audit could cause unrelated visual churn.** → Limit edits to hard-coded light fills on input or input-like surfaces that demonstrably bypass the active theme; record intentional white surfaces such as QR output as exclusions.
