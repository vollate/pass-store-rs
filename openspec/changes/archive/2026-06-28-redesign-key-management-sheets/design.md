## Context

Settings currently opens separate PGP and SSH key sheets, but each sheet mixes
global creation/import actions with key-specific operations at the bottom. The
same export and `.gpg-id` buttons act on the first key in the visible list,
which makes targeting unclear and creates a crowded action cluster.

The redesign keeps PGP and SSH as separate sheets. It only changes action
placement and targeting; repository APIs and key operation flows remain the
same.

## Goals / Non-Goals

**Goals:**

- Keep the PGP keys sheet and SSH keys sheet as separate popups.
- Limit sheet-level actions to adding new keys: `Create` and `Import`.
- Move all key-specific operations into the row overflow menu for the key they
  affect.
- Preserve current dialogs and confirmations for create, import, export, add to
  `.gpg-id`, and delete.
- Remove first-key default targeting for export and `.gpg-id` actions.

**Non-Goals:**

- Merging PGP and SSH into one popup, tabs, or combined sheet.
- Changing bridge/core key-management APIs.
- Redesigning onboarding key setup.
- Adding new key metadata, search, sorting, or filtering.

## Decisions

- Use the existing `_showKeys(context, KeyRecordType)` entry point but keep it
  rendering separate sheets for PGP and SSH.
  - Rationale: this preserves the current navigation model while allowing
    shared implementation for list rendering.
  - Alternative considered: one combined key management sheet with PGP/SSH
    tabs. This was rejected because PGP and SSH should keep their own popups.

- Keep only `Create` and `Import` as sheet-level actions.
  - Rationale: these actions do not target an existing key and are natural
    sheet-level commands.
  - Alternative considered: keep `Import file` as a third top-level action.
    This keeps more clutter; implementation can instead fold file import into
    the import flow or expose it from a small import choice dialog.

- Move per-key operations into each key row's overflow menu.
  - PGP menu: `Export public`, `Export private`, `Add to .gpg-id`, `Delete`.
  - SSH menu: `Export public`, `Export private`, `Delete`.
  - Rationale: the menu is already used for delete, and placing all
    key-specific commands there makes the target obvious.
  - Alternative considered: expose inline icon buttons per row. That would be
    faster but visually denser and harder to scan on mobile.

- Remove `GitHub settings` from the redesigned SSH key sheet.
  - Rationale: it is not a local key-management action, and the approved sheet
    structure keeps only Create and Import at the sheet level.
  - Alternative considered: keep it as a quiet secondary sheet-level link. This
    was rejected to keep the SSH sheet aligned with the same Create/Import-only
    rule as PGP.

## Risks / Trade-offs

- Users may need one extra tap to export a key. Mitigation: the row menu makes
  the target key explicit and groups related actions consistently.
- Existing tests may rely on global export buttons. Mitigation: replace them
  with tests for per-key overflow menu actions and selected-key targeting.
- Folding text/file import into one `Import` entry may need a small choice
  dialog. Mitigation: reuse existing import form methods and keep the change
  scoped to presentation and routing.
