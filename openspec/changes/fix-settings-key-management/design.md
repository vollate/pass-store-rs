## Context

The settings screen already lists PGP and SSH keys and supports PGP/SSH key
generation, import, export, and adding a PGP key to the selected store. The
Flutter `KeyRepository` and bridge APIs do not expose key deletion, so the UI
cannot remove key material that is no longer wanted on the device.

The security repository currently persists a single cached PGP passphrase as a
bare secret string. That works only when there is one relevant private PGP key;
with multiple keys, the app cannot explain or enforce which key the saved
passphrase unlocks.

## Goals / Non-Goals

**Goals:**

- Let users delete local PGP and SSH keys from Settings.
- Require explicit confirmation before deleting key material.
- Bind saved PGP passphrases to a selected PGP key fingerprint.
- Clear cached passphrases when their associated PGP key is deleted.
- Keep UI, repository, bridge, and core behavior covered by focused tests.

**Non-Goals:**

- Re-encrypt existing password entries after key deletion.
- Automatically rewrite `.gpg-id` files when deleting a PGP key.
- Support passphrase caching for public-only PGP keys.
- Add new external key-management dependencies.

## Decisions

1. **Add explicit delete methods to the existing key-management boundary.**

   `KeyRepository` should gain `deletePgpKey` and `deleteSshKey` methods, and
   `BridgeBackedRepository` should forward those to new bridge APIs. This keeps
   deletion beside generation/import/export instead of special-casing it inside
   the settings screen.

   Alternative considered: implement deletion only in Flutter for SSH files and
   shell out for PGP from the UI. That would bypass the existing Rust bridge
   boundary and duplicate platform-specific keyring behavior.

2. **Delete PGP keys through the configured backend.**

   Extend the PGP backend trait with a delete operation. The system/bundled GPG
   backend should invoke GPG with an exact fingerprint, while the pure Rust
   backend should remove matching public/private keyring files. Listing keys
   after deletion verifies the result.

   Alternative considered: expose only pure-Rust deletion for mobile. That
   would leave desktop/system-GPG settings inconsistent with the visible UI.

3. **Delete SSH keys by key name from the configured SSH directory.**

   SSH deletion should remove both the private key file and `<name>.pub`, and
   fail when neither exists. The bridge should require the same SSH directory
   used for list/import/export.

   Alternative considered: delete only the private key. Keeping an orphaned
   `.pub` file would make the key list misleading and create confusing stale
   records.

4. **Use confirmation text that includes the key identity.**

   The settings UI should show the PGP fingerprint or SSH key name and require a
   matching confirmation phrase before calling delete. This mirrors existing
   private-key export and local-store delete safety patterns.

   Alternative considered: a simple confirm dialog. The stronger confirmation is
   appropriate because deleting private key material can be hard to recover.

5. **Store cached PGP passphrases with fingerprint metadata.**

   Replace the bare passphrase API with a small key-bound value, such as
   `PgpPassphraseCache(fingerprint, passphrase)`, and persist the fingerprint in
   secure storage next to the passphrase. Settings should require selecting a
   private PGP key before saving. Biometric unlock and active PGP sessions
   should preserve the fingerprint alongside the secret.

   Alternative considered: infer the key from the first private PGP key. That is
   the ambiguity causing this change and would silently choose the wrong key when
   multiple private keys exist.

6. **Treat legacy cached passphrases without fingerprints as ambiguous.**

   On secure-storage load, if a passphrase exists without associated fingerprint
   metadata, clear the cached passphrase and require the user to save it again
   with an explicit key selection. This avoids applying an old secret to the
   wrong key.

   Alternative considered: keep the legacy passphrase and ask the user to link
   it later. That preserves convenience but leaves the app holding an ambiguous
   secret and complicates every read path.

## Risks / Trade-offs

- **Deleting a PGP key referenced by `.gpg-id` can break future encryption for
  that store.** Mitigation: show a warning in the delete confirmation and leave
  `.gpg-id` rewriting out of scope for this change.
- **System GPG deletion behavior can vary by installed GPG version.**
  Mitigation: use exact fingerprints, add core/bridge tests around command
  construction where practical, and map backend errors to visible UI messages.
- **Clearing legacy cached passphrases may surprise existing users.**
  Mitigation: prefer explicit re-save over ambiguous secret use, and keep the
  settings copy clear about which key is cached.
- **Generated bridge code may need refresh after API changes.** Mitigation:
  include bridge regeneration and GUI compile/test steps in the task list.
