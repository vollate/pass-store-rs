# Agent notes

## Flutter GUI design rules (`gui/`)

Every surface is built from the shared pieces below so spacing, row height and
button layout stay identical across pages, sheets and dialogs. Do not hand-roll
replacements.

### Tokens

- Spacing, radii, sizes and insets come from `ParsSpacing`, `ParsRadii`,
  `ParsSizes` and `ParsInsets` in `gui/lib/app/pars_design_tokens.dart`. No raw
  pixel values in widgets.

### Lists

- Use `AppSectionBox` + `ParsSectionRow` + `ParsSectionRowIcon`
  (`gui/lib/widgets/app_section.dart`). Do not stack detached `Card` +
  `ListTile` items. Row title and subtitle are one line each with ellipsis;
  per-row actions go in `trailing` as icon buttons or a `PopupMenuButton`.
- Pass `padding: EdgeInsets.zero` when the surface already has a gutter
  (sheets, onboarding steps), so the list aligns with the rest of the content.
- A list that can grow inside a fixed layout uses
  `AppSectionBox(scrollable: true)` in a height-bounded parent (for example
  `Expanded`). It keeps a visible scrollbar and stops half-way through a row so
  the cut row shows that it scrolls. Primary actions stay pinned below the list
  and never scroll away with it.

### Buttons

- Groups of buttons use `ParsButtonGrid` or `ParsActionGroup`
  (`gui/lib/widgets/pars_action_group.dart`): two equal-width columns, and an
  odd last button spans the row. The grid switches the whole group to one
  full-width button per row when any label would not fit on one line at half
  width, so labels never wrap inside narrow buttons.
- Never lay out buttons with `Wrap`, and never stack several full-width
  buttons by hand. A single submit button in a form sheet, or a page's
  Continue/Skip, may be full width.
- Order inside a pair: secondary on the left (outlined or tonal), primary on the
  right (filled).
- Prefer short labels when the surrounding header gives context, for example
  "Generate" and "Import" under an "SSH keys" section.

### Dialogs

- Use `ParsDialog` (`gui/lib/widgets/pars_dialog.dart`); do not use
  `AlertDialog`, whose actions collapse to one per line on phones.
- At most two actions: `secondary` and `primary`. Deletions set
  `destructive: true`. A third action does not go in the button row: dismissal
  is the close icon (`showClose: true`), and links such as "open GitHub
  settings" are `headerActions` icons or the secondary action.
- Confirmations are a plain yes/no question. Typed confirmation is reserved
  for deleting or disconnecting a store and exporting a private key.

### Content and copy

- No filler hints that repeat what the page title and subtitle already say.
- Every user-facing string is in `gui/lib/l10n/app_en.arb` and `app_zh.arb`;
  run `flutter gen-l10n` after editing them and remove keys that become unused.
- Clipboard writes go through `SensitiveClipboardService`: `copySecret` for
  secrets, `copyPublic` for shareable text such as SSH public keys. Never call
  `Clipboard.setData` directly.

### Navigation

- System back (gesture or navigation key) must match the on-screen back arrow.
  Onboarding walks back through its steps, including steps that were already
  satisfied before the screen opened.

### Verifying UI changes

- Run `flutter analyze` and `flutter test` from `gui/`. Layouts must not
  overflow at 200% text scale (`expectNoFlutterOverflow`).
- For visual changes, render the surface (a temporary golden or a device
  screenshot) and look at it before reporting the change as done.
- Update a golden only when its change is intended and has been inspected.
- Afterwards delete temporary preview tests and images, and restore the golden
  failure output with `git checkout -- gui/test/failures`.
