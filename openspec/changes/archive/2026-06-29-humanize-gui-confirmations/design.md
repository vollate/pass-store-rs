## Context

The GUI already has destructive-confirmation dialogs, but the required text is
inconsistent. PGP key deletion requires a full fingerprint, PGP private export
requires `EXPORT PRIVATE KEY <fingerprint>`, single-entry deletion requires the
full entry path, and some confirmation fields use a generic label without
showing the required phrase up front.

These dialogs are used heavily on mobile, where typing or copying long opaque
identifiers is especially painful. The existing internal operation targets are
still correct: PGP actions should continue to target fingerprints internally,
SSH actions should target names, and entry deletion should target paths.

## Goals / Non-Goals

**Goals:**

- Make typed confirmation text short and human-readable.
- Show the exact required phrase before the user submits.
- Keep destructive operations targeted by existing stable identifiers
  internally.
- Preserve stronger confirmation for private-key export by keeping the
  `EXPORT PRIVATE KEY <label>` phrase.
- Cover the same pattern anywhere the GUI currently asks for fingerprint,
  full path, or an unlabeled confirmation phrase.

**Non-Goals:**

- Do not remove confirmation from destructive or sensitive operations.
- Do not merge PGP and SSH key-management surfaces.
- Do not redesign unrelated store-delete behavior already covered by
  `simplify-store-delete-confirmation`.
- Do not change batch-delete's short `DELETE` confirmation unless the
  implementation finds it lacks visible instructions.

## Decisions

1. Use human-readable labels as confirmation tokens.

   PGP and SSH key deletion use the visible key name. Password-entry deletion
   uses `PasswordEntry.displayName`. Private-key export uses
   `EXPORT PRIVATE KEY <visible key name>`. The dialog also shows the full
   fingerprint or path as read-only target context.

   Alternative considered: use a fixed token like `DELETE` everywhere. That is
   easy to type, but it stops proving the user noticed which object is being
   changed.

2. Preserve stable operation targets.

   The selected key or entry still carries the internal identifier into the
   repository call. For PGP, delete/export still passes the selected
   fingerprint; the typed phrase only gates the action. This keeps duplicate
   human labels from changing which key is affected.

   Alternative considered: look up the target by the typed label. That would be
   ambiguous when labels duplicate and would make deletion/export less safe.

3. Derive PGP private-export confirmation from listed key identity.

   The bridge should locate the requested fingerprint in the PGP key listing
   and validate `EXPORT PRIVATE KEY <identity>`. If the fingerprint cannot be
   found, export fails before private material is returned. SSH export already
   uses key name, so it only needs clearer UI instructions.

   Alternative considered: keep the backend fingerprint phrase and translate a
   GUI label phrase into it before calling the bridge. That would leave the
   public API with the same anti-human contract and make tests less honest.

4. Centralize confirmation copy where practical.

   Add small helper functions or widgets near the existing settings/manage
   widgets for expected labels, instruction text, and target-context rows. This
   keeps the refactor scoped while avoiding slightly different confirmation
   wording across PGP, SSH, export, and entry delete dialogs.

## Risks / Trade-offs

- Duplicate key names can share one confirmation token. The selected menu item
  still provides the fingerprint/name target, and the dialog displays the
  fingerprint as context.
- PGP key identities can be long. This is still more recognizable than a full
  fingerprint, and export/delete dialogs can allow copying visible phrase text
  if needed.
- Changing PGP export validation affects bridge callers. Tests must cover the
  new phrase and validation error so callers see the expected text.
