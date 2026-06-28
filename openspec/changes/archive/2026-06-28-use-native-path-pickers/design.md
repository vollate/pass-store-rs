## Context

Settings and Onboarding currently contain several `TextField` controls for
filesystem paths: local store roots, clone target roots, and key-file import
paths. Onboarding already derives roots from app-managed paths in some cases,
but Settings still asks for raw paths and key-file import always asks for a raw
file path.

The desired interaction is picker-only in the primary UI. Affected forms should
not show editable path fields. They should show a restrained, no-icon picker row
that displays the current default/base path, opens the platform-native selector,
and then displays the selected path.

## Goals / Non-Goals

**Goals:**

- Use platform-native file and folder selectors for user-facing filesystem path
  choices in Settings and Onboarding.
- Keep store-folder selection and key-file selection in their existing separate
  interfaces. Store setup forms must not be merged with key import forms.
- Display the default/base path before selection and the selected path after
  selection.
- Use compact no-icon picker rows with label, path subtitle, and a trailing
  Choose/Change action.
- Keep existing repository and bridge method signatures unchanged.
- Make picker behavior testable through injection.

**Non-Goals:**

- No broad rewrite of store lifecycle, bridge, or core filesystem APIs.
- No new combined path-management popup that mixes store folders with key
  files.
- No decorative icon treatment or card-heavy redesign.
- No manual path text entry in the primary UI.

## Decisions

### Use an injected path-picker abstraction

Add a small Flutter abstraction, for example `PathPickerService`, with methods
for folder selection and file selection. The production implementation should
wrap the chosen native picker package, while tests inject a fake picker that can
return a path, return null for cancellation, or throw an unsupported-platform
error.

Alternative considered: call the picker package directly from Settings and
Onboarding. That would be faster initially, but it would spread platform and
test behavior across forms.

### Use native selectors as the primary path input

Replace visible path `TextField` controls with picker rows. Before selection,
the row shows `Default: <path>` using the best available base/default path.
After selection, it shows `Selected: <path>` and changes the action from Choose
to Change. Submit actions that require a user-selected path remain disabled
until the picker returns a path.

Alternative considered: retain manual text entry as a secondary inline fallback.
The approved direction is stricter: picker-only in the primary UI. Unsupported
platforms should produce a clear notification instead of silently accepting
typed paths.

### Treat store roots and key files as separate picker contexts

Store setup forms use folder pickers. Key-file import forms use file pickers.
These controls may share a reusable row widget, but they stay in their existing
separate Settings and Onboarding screens/sheets.

For import-local-store, the folder picker selects the existing store root. For
create-local-store and clone-store, the picker selects the parent/base folder
when a native selector cannot select a not-yet-existing target path; the final
root is derived from the chosen base plus the store name or remote URL slug.

Alternative considered: a single generic path picker popup for all path types.
That would reduce duplication, but it would blur unrelated user tasks and risk
repeating the prior "merged popup" problem.

### Reuse existing default path knowledge

Defaults should come from existing application state where possible:

- Store roots prefer the app-managed store base when available.
- Create-store defaults derive from the store name.
- Clone-store defaults derive from the remote URL slug.
- Import-store defaults use the managed store base, selected store parent, or
  platform home/documents fallback.
- SSH key-file import defaults to the configured SSH directory when available.
- PGP key-file import defaults to the best platform file location available.

The default text is informational and also controls the picker initial
directory where the native package supports it.

## Risks / Trade-offs

- Native picker package behavior varies by platform -> wrap it in a service and
  centralize unsupported/cancel/error handling.
- Create/clone target roots may not exist yet -> select a base folder and derive
  the final root consistently from existing slug helpers.
- Strict picker-only UI can block automation or unusual platforms -> show a
  clear unsupported-platform notification and keep the submit disabled rather
  than accepting ambiguous manual text.
- Long paths can overflow compact rows -> use single-line ellipsis in the row
  and keep the full path accessible in tests/semantics or tooltip where the
  platform supports it.
