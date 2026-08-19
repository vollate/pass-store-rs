## Why

The vault entry detail UI contains a hard-coded light password surface that remains bright in dark mode, and its modal bottom sheet collapses to the loading indicator's intrinsic width while an entry is being decrypted. These inconsistencies make dark mode visually incorrect and cause a distracting layout jump during a common security workflow.

## What Changes

- Make password and other input-like surfaces use theme-derived colors so they remain legible and visually consistent in both light and dark modes.
- Audit Flutter text inputs and related editable/input-like surfaces for hard-coded light fills or colors that bypass the active theme.
- Keep the entry detail bottom sheet at a stable, usable width across passphrase, decrypting, error, and loaded-content states.
- Add widget coverage for dark-theme surface colors and loading-state bottom-sheet width.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `flutter-vault-and-manage`: Require entry detail presentation to follow the active color theme and preserve a stable modal width while secrets are loading or transitioning between states.

## Impact

- Affects Flutter theme usage and the vault entry detail widgets under `gui/lib/app/` and `gui/lib/screens/vault/`.
- May touch other hand-written Flutter widgets only where the input-surface audit finds a hard-coded light color.
- Adds or extends Flutter widget tests; no Rust, bridge API, storage format, dependency, or localization contract changes are expected.
