# Pars Mobile Flutter GUI Design

Date: 2026-06-18
Status: approved for design documentation
Scope: mobile Flutter GUI only. Tablet and desktop layouts are out of scope for this spec.

## Context

Pars is a cross-platform `pass`-compatible password-store tool. The existing repository already has a Rust core and CLI with support for listing/showing entries, inserting, generating, editing, removing, searching, Git operations, PGP encryption, and clipboard clearing. The Flutter GUI currently exists as a starter app, so the mobile design can define the user-facing product shape without needing to preserve an existing GUI.

The mobile app should feel like a mature password manager, not a command-line interface transplanted onto a phone. Text input should be limited to unavoidable cases such as searching by pass name/path, entering Git arguments in an advanced screen, pasting keys, and editing entry content. Normal operations should be expressed as buttons, sheets, toggles, pickers, confirmations, and pull gestures.

## Design Goals

- Make daily password lookup and copy fast with minimal typing.
- Keep compatibility with existing `pass` stores and personal file formats.
- Expose PGP, SSH, and Git power-user controls without polluting the daily Vault screen.
- Support first-run setup on a phone, including creating or importing keys.
- Treat secrets conservatively: decrypt briefly, mask by default, confirm dangerous actions, and avoid leaking private key material.

## Main Navigation

The mobile app uses three bottom tabs:

1. `Vault`
   Daily use. Search, browse, view recent entries, copy passwords, and open entry details.

2. `Manage`
   Password entry management. Generate, create, edit, move, rename, delete, and batch-regenerate entries.

3. `Settings`
   App and store configuration. Password stores, Git, PGP keys, SSH keys, gesture unlock, biometrics, KMS/Keychain, clipboard, and advanced Git arguments.

There is no separate `Folders` tab. Directory browsing belongs in `Vault`, alongside search and recent entries. There is no `Create` tab because creation is only one part of password maintenance; `Manage` covers create, modify, delete, and batch workflows.

## First-Run Onboarding

The app should guide a fresh mobile user from an empty install to a usable password store.

### Step 1: Unlock Setup

- Set a 9-dot gesture lock as the mobile app's primary local unlock method.
- Confirm the gesture by drawing it a second time.
- Offer biometric authentication as a faster unlock path.
- If biometric authentication fails or is disabled, fall back to the gesture lock.
- Offer optional KMS/Keychain storage for the PGP private-key passphrase, enabling biometric unlock to open a PGP session without asking for the passphrase again.
- Let the user choose auto-lock behavior and PGP session-auth expiration.

The gesture lock protects the local Pars app experience. It does not replace the PGP key or passphrase. KMS/Keychain storage of PGP passphrases is opt-in.

### Step 2: Password Store

Offer three primary paths:

- Use an existing local password store.
- Clone a password store from Git.
- Create a new password store.

If an existing Pars config is found, offer to import it. Store import/config import belongs in onboarding and `Settings > Password Stores`, not in the daily Vault UI.

### Step 3: Encryption Key

Support:

- Use an existing PGP key on the device.
- Create a new PGP key on the device.
- Import a PGP private key from file/storage provider.
- Import a PGP private key from pasted armored text.

After key creation/import, the app should show the key identity and fingerprint, and offer to add the public key to `.gpg-id`.

### Step 4: Git Access

Support GitHub/Git SSH setup separately from PGP:

- Create an ed25519 SSH key pair on the device.
- Import an SSH private key from file/storage provider.
- Import an SSH private key from pasted text.
- Copy the SSH public key.
- Open GitHub SSH key settings in a browser.

PGP keys encrypt password entries. SSH keys authenticate Git remotes. The UI should keep those concepts separate.

### Step 5: Review

Before entering the app, show:

- Selected password store path.
- Git remote and sync mode if configured.
- PGP key fingerprint.
- SSH key status if configured.
- Gesture lock and biometric status.
- KMS/Keychain PGP passphrase storage status.

## Vault

`Vault` is the daily-use screen.

### Layout

- Top area:
  - Current repo selector.
  - Compact Git state indicator, such as `Clean`, `Need pull`, `Uncommitted`, or `Sync failed`.
  - Search field for pass name/path.
- Content:
  - Recent entries.
  - Favorites if implemented.
  - Directory browsing inside the current repo.
  - Search results when query text is present.
- Sync:
  - Pull-to-refresh triggers sync.
  - Auto-sync policies live in Settings.
  - The Vault top bar should not contain a visible Sync button by default.

### Entry Row

Each password entry row shows:

- Entry display name.
- Path or folder context.
- Optional small visual identifier.
- A visible `Copy` shortcut button.

Tapping the row opens a bottom-sheet detail view. It does not expand the row in place. This keeps the list stable and avoids losing scroll position.

### Entry Detail Sheet

The bottom sheet shows:

- Entry name and full path.
- Masked password by default.
- Parsed fields when available.
- Raw notes when parsing fails or when lines do not map cleanly to known fields.

Actions are buttons:

- Copy password.
- Reveal/hide password.
- Copy parsed fields such as username or URL.
- Open URL when a URL field is recognized.
- Show QR code.
- Edit entry.
- Regenerate password.
- Delete entry.

Dangerous actions such as delete require confirmation and must show the full entry path.

## Entry Parsing

Pars should preserve `pass` compatibility and personal formats.

Rules:

- The first decrypted line is always the password.
- Subsequent lines are parsed best-effort.
- Recognized key names include `username`, `user`, `login`, `email`, `url`, `website`, `totp`, `otp`, and `note`.
- Recognized fields become first-class rows with copy/open buttons.
- Unrecognized lines are preserved exactly in `rawNotes`.
- If the entire metadata section cannot be parsed reliably, show it as raw notes.

Parsing should never discard or rewrite user content just because it does not match a known format.

## Manage

`Manage` is the maintenance area for password entries. It is not for app settings or key configuration.

Supported workflows:

- Generate and save new passwords.
- Save an existing password manually.
- Edit a single entry.
- Edit raw notes.
- Replace only the first-line password while preserving recognized fields and raw notes.
- Move or rename entries.
- Delete entries.
- Batch-select entries.
- Batch move/rename/delete/regenerate.

Batch workflows should use a preview screen before execution. The preview must show:

- All affected paths.
- The planned operation.
- Whether raw notes are preserved.
- Whether a Git commit will be created.

After execution, show a result summary with successes, failures, and current Git state.

Single-entry edit/regenerate/delete can be launched from the Vault detail sheet, but the editing workflow itself belongs to Manage.

## Settings

Settings owns configuration and advanced controls.

### Security

- Gesture lock management.
- Biometric unlock toggle.
- Auto-lock timing.
- KMS/Keychain storage for PGP passphrase.
- PGP session-auth expiration:
  - Immediately.
  - 5 minutes.
  - 15 minutes.
  - 1 hour.
  - Until app exit.
- Clipboard clearing timeout.
- Require unlock on app resume.

### Key Management

Provide a top-level Settings entry for key management. Inside it, separate PGP and SSH keys.

PGP key management:

- List keys with identity and fingerprint.
- Create a new PGP key.
- Import public key.
- Import private key from file.
- Import private key from pasted armored text.
- Copy/export public key.
- Export private key backup.
- Delete key.
- Add public key to `.gpg-id` where appropriate.

SSH key management:

- List SSH keys with fingerprint and usage.
- Create ed25519 key.
- Import private key from file.
- Import private key from pasted text.
- Copy/export public key.
- Export private key backup.
- Delete key.
- Open GitHub SSH settings.

Private key import/export must be strongly marked as sensitive. Private key export requires app unlock and, when available, biometric confirmation plus an explicit confirmation phrase.

### Password Stores

- View and change default repo.
- Add store.
- Remove store from app.
- Delete local store with strong confirmation.
- Clone store from Git.
- Re-clone or re-pull a store.
- Manage `.gpg-id`.
- Import existing Pars config.

### Git

- Show current repo Git status.
- Pull, push, status, and commit buttons.
- Configure remotes.
- Configure auto pull on app open.
- Configure commit after Manage operations.
- Configure optional push after commit.
- Delete local repo with strong confirmation.
- Re-clone/re-pull workflows.
- Advanced Git arguments runner.

Advanced Git runner:

- Only accepts arguments after `git`, such as `pull --rebase`.
- Does not accept full shell commands.
- Does not support pipes, redirection, command separators, or arbitrary shell execution.
- Always runs scoped to the selected password-store repo.
- Shows the exact repo path and full `git <args>` command before execution.
- Shows exit code, stdout, and stderr after execution.

### Appearance and About

Keep these low priority:

- Theme.
- Version.
- Logs.
- Diagnostics export.

## Data Model

Suggested UI/domain models:

- `PasswordEntry`
  - repo id/path
  - entry path
  - display name
  - directory flag
  - last modified time
  - favorite flag
  - recent-used timestamp
  - Git status if known

- `SecretContent`
  - password first line
  - parsed fields
  - raw notes
  - decrypted lifetime metadata

- `ParsedFields`
  - username/login/user
  - email
  - URL/website
  - TOTP/OTP
  - note
  - unknown raw lines

- `KeyRecord`
  - key type: PGP or SSH
  - identity/comment
  - fingerprint
  - public key availability
  - private key availability
  - source: generated, imported file, imported text, system
  - usage flags

- `AuthState`
  - gesture lock configured
  - biometric enabled
  - KMS/Keychain PGP passphrase storage enabled
  - PGP session expiration
  - locked/unlocked state

Secrets and private keys should not live in ordinary long-lived Flutter widget state. Decrypted data should be short-lived and cleared when the detail sheet closes, the app locks, or the configured session expires.

## Error Handling

- Uninitialized app:
  - Open onboarding instead of showing a raw error.

- PGP decrypt failure:
  - Show failure state in the detail sheet.
  - Offer retry, choose key, or import key.

- Missing PGP key:
  - Route to Settings Key Management or onboarding key step.

- Git sync failure:
  - Show `Sync failed` in Vault Git state.
  - Let the user open logs and retry.

- Advanced Git failure:
  - Show exit code, stdout, and stderr.

- Delete or batch modification:
  - Preview full affected paths.
  - Confirm before execution.
  - Show partial success/failure list after execution.

- Biometric failure:
  - Fall back to gesture unlock.

- KMS/Keychain unavailable:
  - Disable one-step PGP unlock.
  - Keep manual PGP passphrase path available.

## Testing Boundaries

Flutter widget tests:

- Onboarding step progression.
- Gesture unlock setup screens.
- Vault list states.
- Entry bottom sheet.
- Copy/reveal/edit/delete button visibility.
- Manage batch selection and preview.
- Settings key management navigation.
- Git advanced args screen.

Parser unit tests:

- First line password extraction.
- Structured metadata parsing.
- Unknown metadata preserved as raw notes.
- Mixed known and unknown fields.
- Empty notes.

Safety tests:

- Advanced Git accepts args only.
- Advanced Git rejects shell-like input.
- Delete requires confirmation.
- Private key export requires strong confirmation.
- Decrypted content clears when expected.

Integration smoke tests:

- Empty app opens onboarding.
- Mock repo renders Vault.
- PGP decrypt failure shows recovery actions.
- Git sync failure shows logs and retry.
- PGP session timeout locks decrypted actions.

## Visual Direction

The visual style should be restrained, dense, and mobile-native:

- Use clear lists, bottom sheets, segmented controls, toggles, and action buttons.
- Avoid command palettes as the primary interaction model.
- Avoid dashboard-style health scores in the first mobile version.
- Keep Vault calm and fast; put power-user controls in Manage and Settings.

The core design principle is: Vault retrieves secrets, Manage changes entries, Settings configures the app.
