## Why

Pars now exposes the required vault, key, Git, Autofill, and mutation workflows, but the GUI presents them through duplicated action paths, card-heavy screens, transient or contradictory status feedback, and mostly hard-coded English. A unified redesign is needed now so the product remains understandable, secure, accessible, and maintainable as the supported feature set grows.

## What Changes

- **Stage 1 — Establish the UI foundation:** introduce shared semantic color, typography, spacing, shape, status, notification, modal, and responsive-layout primitives; migrate every production-facing Flutter string to complete English and Chinese resources; add a persisted System/English/Chinese language choice; and add accessibility and visual-regression coverage for representative phone, large-text, dark-mode, and wide-screen states.
- **Stage 2 — Simplify navigation and preserve state:** **BREAKING (UI)** replace the equal-weight Vault/Manage/Settings tab model with Vault and Settings as the two durable destinations. Preserve each destination's search, directory, selection, scroll, and nested-navigation state. Move create and mutation workflows into contextual Vault actions rather than retaining Manage as a separate top-level destination.
- **Stage 3 — Redesign Vault and entry detail:** present bounded Favorites, Recent, and Browse content with denser, distinguishable rows; stop treating every entry as recent when no history exists; expose favorite state visibly; provide a clear manual lock action; use one reveal/hide control; group primary, secondary, and destructive entry actions; and keep all existing decrypt, mutation, confirmation, secret-clearing, and optional Git-commit semantics.
- **Stage 4 — Consolidate creation and management:** expose create/generated-password actions from Vault, enter an explicit multi-select mode for batch operations, and place edit, move, rename, regenerate, and delete beside the selected entry or selection. Remove duplicate action-first cards while preserving all current single-entry and batch capabilities.
- **Stage 5 — Reorganize Settings and onboarding:** group routine appearance, security, vault/sync, and Autofill settings ahead of key-management and advanced diagnostics; show concise localized status summaries instead of raw parser paths or backend errors; progressively disclose optional biometric and SSH setup instead of forcing a six-chip expert workflow; and keep all key, store, Git, picker, and transactional safety behavior available.
- **Stage 6 — Harden security and feedback UX:** provide consistent timed clipboard clearing and platform-sensitive clipboard metadata for every secret-copy path; protect revealed secrets, fields, and QR codes from application-switcher snapshots and screen capture where the platform supports it; provide an accessible non-drawing way to enter the existing gesture pattern; and use durable, actionable warnings for partial success or post-mutation Git failures.
- Polish Android and iOS Autofill presentation and setup status within platform rendering constraints, while preserving system-safe Android `RemoteViews`, visible non-filling no-match behavior, path-first matching, and exactly-one-entry decryption.
- Do not change password-store ciphertext, OpenPGP key protection, passphrases, public material, Autofill matching schema, Android package matching policy, or the no-secret-cache architecture.

## Capabilities

### New Capabilities
- `flutter-ui-foundation`: Shared Flutter design tokens and components, adaptive layouts, persisted locale selection, complete English/Chinese localization, accessible interaction semantics, sanitized feedback, and visual/accessibility regression standards.

### Modified Capabilities
- `flutter-gui-composition`: Change screen composition from behavior-equivalent extraction to explicit state ownership, shared UI primitives, adaptive navigation, and independently testable route surfaces.
- `flutter-vault-and-manage`: Replace the dedicated Manage destination with contextual Vault creation and selection workflows; make Favorites, Recent, Browse, entry detail, copy, status, and mutation hierarchy coherent and state-preserving.
- `flutter-security-and-onboarding`: Add manual lock and sensitive-screen protection, accessible gesture entry, progressive onboarding, and a reorganized Settings hierarchy without weakening existing security or transactional behavior.
- `mobile-system-autofill`: Present concise localized Autofill state and recoverable errors in Settings and refine matched/no-match platform presentation without changing path-first matching or decryption boundaries.

## Impact

- Primary Flutter areas: `gui/lib/app/`, `gui/lib/screens/shell/`, `gui/lib/screens/vault/`, `gui/lib/screens/manage/`, `gui/lib/screens/settings/`, `gui/lib/screens/onboarding/`, `gui/lib/screens/security/`, `gui/lib/widgets/`, `gui/lib/l10n/`, and related repository-facing UI adapters.
- Native presentation/privacy areas: Android activity/window and Autofill resources under `gui/android/`, plus iOS runner and credential-provider presentation under `gui/ios/`.
- Tests: widget, semantics, localization, navigation-state, golden or screenshot, responsive-layout, clipboard/privacy adapter, Android Autofill presentation, and iOS presentation tests.
- No bridge or core cryptographic API change is intended. Existing vault mutations, key preparation, Autofill index lifecycle, selected-entry-only decryption, and Git operations remain authoritative.
