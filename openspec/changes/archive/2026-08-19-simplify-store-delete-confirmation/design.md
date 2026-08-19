## Context

Local store deletion is destructive and currently requires typing the full
normalized store root. On Android, app-managed roots live under long internal
paths such as `/data/user/0/top.vollate.pars_gui/files/stores/<name>`, so the
current confirmation token is technically precise but bad product behavior.

The bridge already receives both the target `root` and a free-form
`confirmation` string. The request schema can remain unchanged if the bridge
derives the required confirmation token from the normalized root basename.

## Goals / Non-Goals

**Goals:**

- Let users confirm local store deletion by typing the final store name only.
- Keep the full root visible in the UI so users can verify exactly which
  directory will be deleted.
- Keep all existing destructive safeguards around configured roots, existing
  directories, filesystem roots, config updates, and directory deletion.
- Cover bridge validation and Flutter settings UI behavior with tests.

**Non-Goals:**

- Changing key deletion, password entry deletion, Git repo deletion, or private
  key export confirmation phrases.
- Changing the `DeleteLocalStoreRequest` bridge schema.
- Introducing undo/trash behavior for deleted stores.

## Decisions

- Validate confirmation against the normalized root basename in the bridge.
  This keeps the destructive check close to the actual deletion operation and
  ensures every caller gets the same rule. Alternative considered: translate
  the store name in Flutter before calling the bridge. That would improve the
  current UI but leave non-Flutter callers with the old full-path rule.

- Keep `root` as the deletion authority and use confirmation only as a guard.
  The bridge SHALL still normalize and check the configured root before any
  filesystem removal. Alternative considered: delete by store name. That would
  be ambiguous if two configured roots share a basename.

- Show both the store name and full root in the delete dialog. The name is the
  input token; the root is read-only context. Alternative considered: hide the
  root completely. That would be cleaner visually but weaker for destructive
  verification.

## Risks / Trade-offs

- Duplicate basenames across configured roots could produce the same
  confirmation token. Mitigation: the selected `root` remains the actual target
  and the UI displays the full root before deletion.
- Empty or unusual root basenames could make the confirmation token unclear.
  Mitigation: keep existing root normalization and filesystem-root refusal; add
  validation/test coverage for the derived expected token.
- Users familiar with the old behavior may type the full path. Mitigation:
  update helper/error text to explicitly ask for the store name only.
