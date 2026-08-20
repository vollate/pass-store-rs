## 1. Baseline and Regression Harness

- [x] 1.1 Add a deterministic GUI test harness for compact phone, keyboard-visible phone, 200% text scale, medium, and expanded window sizes in light and dark themes.
- [x] 1.2 Add reusable helpers for rendering English and Chinese localized widget tests and for asserting absence of Flutter overflow exceptions.
- [x] 1.3 Capture structural or golden baselines for current Vault, entry detail, Settings, onboarding, lock, empty, loading, and error states before replacing their layouts.
- [x] 1.4 Add source-audit tests or scripts that inventory production user-facing literals, direct raw-error interpolation, direct secret clipboard writes, and actionable no-op callbacks.
- [x] 1.5 Record the chosen compact/medium/expanded breakpoints and bounded content widths from representative phone and tablet/simulator evidence.

## 2. Semantic Theme and Shared UI Foundation

- [x] 2.1 Extend `ParsTheme` with semantic light/dark success, warning, error, info, busy, unavailable, selected, and destructive roles while preserving existing readable primary colors.
- [x] 2.2 Add shared spacing, radius, content-width, icon-size, minimum-touch-target, and motion-duration tokens without adding a third-party design-system dependency.
- [x] 2.3 Configure Material 3 component themes for navigation, cards/rows, inputs, buttons, chips/status badges, dialogs, bottom sheets, focus, disabled, and destructive states.
- [x] 2.4 Replace the hard-coded section-label and sheet-handle colors with semantic theme roles and add contrast tests including the dark section-label case.
- [x] 2.5 Implement focused shared page header, section header, empty state, compact row, status badge, action hierarchy, and responsive content-boundary components.
- [x] 2.6 Implement shared adaptive route/modal framing with consistent safe area, title, close/back, maximum width, scrolling, keyboard insets, and compact-versus-wide behavior.
- [x] 2.7 Add theme/component tests covering light/dark legibility, status icon/color correctness, destructive distinction, minimum touch targets, and 200% text wrapping.

## 3. Locale Preferences and Complete Localization

- [x] 3.1 Define a versioned `UiPreferencesStore` abstraction and fake implementation for `system`, `en`, and `zh` locale preferences.
- [x] 3.2 Implement atomic app-support-file persistence with missing, invalid, and unreadable data falling back to System locale without blocking app startup.
- [x] 3.3 Make `ParsGuiApp` own the active locale preference, apply it to `MaterialApp`, and support live locale changes without restarting or resetting navigation.
- [x] 3.4 Add the localized Appearance and language-selection messages and verify persisted System/English/Chinese switching in widget and repository tests.
- [x] 3.5 Migrate shell, Vault, entry rows, entry detail, contextual mutation, copy, status, empty, loading, and error strings and semantics to ARB resources.
- [x] 3.6 Migrate Settings, key/store/Git/Autofill workflows, dialogs, notifications, validation, and diagnostics summaries to ARB resources.
- [x] 3.7 Migrate onboarding, lock, gesture, biometric, picker, import, conflict, and review strings and semantics to ARB resources.
- [x] 3.8 Add equivalent English and Chinese Android and iOS Pars/Autofill presentation resources while leaving user data and machine diagnostics untranslated.
- [x] 3.9 Add strict localization validation for English/Chinese key parity, placeholder parity, and unapproved production-facing string literals.

## 4. Adaptive Two-Destination Shell and State Ownership

- [x] 4.1 Introduce explicit non-secret Vault and Settings destination state objects for query, directory, selection, category/nested route, and scroll restoration.
- [x] 4.2 Replace the Vault/Manage/Settings `BottomNavigationBar` shell with Material 3 Vault/Settings `NavigationBar` on compact windows and `NavigationRail` on medium/expanded windows.
- [x] 4.3 Implement platform back behavior so nested routes pop first, compact Settings returns to Vault before app exit, and lock/onboarding remain outside the authenticated shell.
- [x] 4.4 Preserve safe destination state across switches without recreating or unnecessarily refreshing Vault and without retaining decrypted entry content.
- [x] 4.5 Clear/dismiss decrypted detail state on destination change, lock, protected background transition, or detail close while preserving only public list/detail selection.
- [x] 4.6 Update shell and navigation tests for compact/wide layout, back behavior, state restoration, no redundant refresh, and secret-disposal boundaries.

## 5. Vault Home, Rows, Favorites, Recent, and Status

- [x] 5.1 Change real and fake repository recent selectors so empty recent metadata returns an empty recent list rather than every credential while retaining the bounded recency cap.
- [x] 5.2 Implement bounded Favorites and Recent sections plus Browse and a separate Search results state using the shared section/empty-state components.
- [x] 5.3 Replace card-per-entry `EntryTile` presentation with compact accessible credential and directory rows that show display name, service/parent context, favorite state, and one direct-copy affordance.
- [x] 5.4 Ensure row identity uses local path-derived data or deterministic local glyphs only and performs no network favicon or icon lookup.
- [x] 5.5 Add visible favorite toggling and immediate Favorites/row-state updates without triggering full Autofill rebuild or entry decryption.
- [x] 5.6 Replace the fixed Git success icon with status-derived localized icon, color, tooltip, semantics, details, and recovery actions for clean, pull-needed, uncommitted, busy, and failed states.
- [x] 5.7 Add a clearly named manual Lock now action to the authenticated Vault/shell header.
- [x] 5.8 Add Vault tests for favorites, empty recent, bounded sections, search replacement, browse navigation, row density/semantics, truthful failed status, refresh, and restored public state.

## 6. Entry Detail and Sensitive Copy

- [x] 6.1 Replace the always-tall entry-detail bottom sheet with the shared adaptive detail route/pane while preserving passphrase, loading, error, empty, and loaded-state geometry.
- [x] 6.2 Redesign the detail header, password surface, fields, raw notes, URL, favorite, primary Copy, secondary/overflow actions, and destructive Delete hierarchy.
- [x] 6.3 Remove the duplicate Reveal action and implement one reveal/hide control whose icon, label, tooltip, obscured state, and semantics toggle together.
- [x] 6.4 Preserve PGP session gating and one-time key preparation feedback, and announce localized busy/error state without exposing passphrases or backend internals.
- [x] 6.5 Implement `SensitiveClipboardService` with consistent configured clearing, superseded-timer handling, secret-free localized feedback, and a testable platform adapter.
- [x] 6.6 Add Android sensitive clipboard metadata and iOS supported expiration/local-only metadata without routing clipboard values through Rust or durable storage.
- [x] 6.7 Route Vault-row password copy, detail password copy, and parsed-field copy through the shared sensitive service; keep diagnostics copy on a non-secret path.
- [x] 6.8 Verify detail closes and clears decrypted content before edit, move, rename, regenerate, or delete workflow presentation.
- [x] 6.9 Add entry-detail tests for adaptive geometry, singular reveal semantics, dark/light themes, large text, PGP states, favorite, URL/field actions, clipboard clearing, unsupported actions, and secret disposal.

## 7. Contextual Creation and Management

- [x] 7.1 Add a prominent Vault Create action that opens existing generated-password and manual-existing-password workflows through the adaptive surface helper.
- [x] 7.2 Add an explicit Select entry point and long-press support with localized selected count, checkbox/selected semantics, cancel behavior, and supported batch actions.
- [x] 7.3 Move edit, move, rename, regenerate, QR, and delete entry points into row/detail context or overflow without changing repository operations.
- [x] 7.4 Move batch move, batch rename, batch regenerate, and batch delete into selection mode while preserving per-entry success/failure collection.
- [x] 7.5 Preserve overwrite handling, parsed fields/raw notes, human-readable typed confirmation, optional commit controls, and existing default commit messages in every relocated workflow.
- [x] 7.6 Replace transient-only operation summaries with severity-aware complete-success, partial-success, failure, and cancellation results.
- [x] 7.7 Present post-mutation Git commit failure as a durable warning that states the vault mutation succeeded and was not rolled back, with details/recovery actions.
- [x] 7.8 Remove the dedicated Manage navigation destination and duplicate action-card/batch-panel entry points only after every former operation is reachable and covered.
- [x] 7.9 Update focused and batch mutation tests to assert the new contextual entry points, cancellation, unsupported capability handling, repository calls, and durable outcome semantics.

## 8. Settings Information Architecture and Sanitized Diagnostics

- [x] 8.1 Rebuild Settings home with Appearance, Security and privacy, Vault and sync, Autofill, Key management, and Advanced/support groups in that order using concise semantic status rows.
- [x] 8.2 Add the persisted System/English/Chinese selector to Appearance and keep the equivalent Settings route visible after live locale switching.
- [x] 8.3 Keep every existing gesture/biometric, PGP timeout/cache, key, store, Git, Autofill, diagnostics, and onboarding-reset action reachable through concrete adaptive routes.
- [x] 8.4 Introduce a localized `UiProblem`/presentation mapper for known bridge, key, store, Git, security, and Autofill failures with severity, summary, recovery, and bounded diagnostics.
- [x] 8.5 Remove raw `error.toString()`, private app-storage paths, parser field lists, command output, and stack-like details from Settings row subtitles and ordinary notifications.
- [x] 8.6 Add explicit Details/Runtime diagnostics disclosure for bounded non-secret paths, commands, versions, and typed errors with redaction and copy support.
- [x] 8.7 Convert complex key/store/Git/diagnostics workflows to adaptive full-height routes or constrained wide dialogs while retaining compact sheets only for short choices/confirmations.
- [x] 8.8 Add Settings tests for category order, language, concise statuses, details disclosure, keyboard-safe confirmations, large text, wide layout, and reachability of every existing operation.

## 9. Essential-First Onboarding, Accessible Lock, and Privacy

- [x] 9.1 Replace the disabled six-chip onboarding rail with a capability-driven essential flow for gesture and usable store/key setup plus a clear required/optional progress model.
- [x] 9.2 Keep biometric and SSH setup skippable or deferrable and expose deferred actions in review/post-setup guidance and Settings.
- [x] 9.3 Preserve PGP inspection/import/preparation, selected-key behavior, native path pickers, managed-store conflict handling, and transactional create/clone/import operations in the new flow.
- [x] 9.4 Add semantic button actions and selected state for each gesture dot plus localized Clear and Submit controls that reuse the existing ordered-dot verifier without a new credential.
- [x] 9.5 Ensure gesture setup/unlock mismatch, busy, clear, and success states are announced without logging, persisting, or speaking the pattern.
- [x] 9.6 Wire Lock now through the existing full lock path and verify it clears the PGP session and decrypted presentation without clearing durable settings or metadata.
- [x] 9.7 Add an Android release secure-window adapter for authenticated content with only explicit test/debug control and no release bypass.
- [x] 9.8 Add an iOS application-switcher privacy cover and supported capture-state obscuring without interfering with the credential-provider extension.
- [x] 9.9 Add onboarding/lock tests at 200% text scale and keyboard-visible phone size, plus semantics tests for drawing, dot actions, Clear, Submit, biometrics, required repair, optional skip, and Finish gating.
- [x] 9.10 Add native privacy adapter tests and physical-device checks confirming protected snapshots/capture and normal system Autofill authentication.

## 10. Autofill Settings and Native Presentation Polish

- [x] 10.1 Map Autofill status to localized Ready with count, Needs rebuild, Busy, Disabled, and Unavailable summaries without parsing/decrypting entries during render.
- [x] 10.2 Keep setup, path rebuild, clear, URL enrichment enable/run/clear/disable, and diagnostic details as visibly separate explicit actions with current confirmation and selection rules.
- [x] 10.3 Replace invalid-schema parser dumps on the Settings tile with Needs rebuild plus Rebuild, while preserving fail-closed behavior and bounded Details.
- [x] 10.4 Refine Android matched and no-match `RemoteViews` using only allowlisted classes, localized English/Chinese strings, readable service/username/source identity, and distinguishable non-filling no-match semantics.
- [x] 10.5 Refine iOS credential-provider localization and supported accessibility labels without exposing a password before authentication and selection.
- [x] 10.6 Extend Android/iOS tests for large text, matched/no-match text, source/service/username semantics, no empty fill, cancellation, and platform-safe layouts.
- [x] 10.7 Re-run shared matcher/index/resolution tests to prove presentation changes add no package matching, schema compatibility path, implicit rebuild, whole-vault decryption, or more-than-selected-entry decryption.

## 11. Visual, Responsive, and Accessibility Completion

- [x] 11.1 Add deterministic light/dark English/Chinese visual coverage for Vault home/search/browse/selection, entry detail states, Settings groups/details, onboarding, and lock.
- [x] 11.2 Add compact/medium/expanded and portrait/landscape tests ensuring bounded content, correct NavigationBar/NavigationRail choice, adaptive route/modal choice, and no ordinary horizontal overflow.
- [x] 11.3 Add 200% text-scale and keyboard-visible tests for every primary form, destructive confirmation, entry detail, Autofill recovery, onboarding repair, and lock workflow.
- [x] 11.4 Complete a semantics audit for every primary, icon-only, selected, obscured, busy, expanded, error, and destructive control and add regression assertions for findings.
- [x] 11.5 Verify transient copy feedback, actionable recoverable errors, blocking destructive confirmations, and durable partial/post-mutation failures do not replace one another incorrectly.
- [x] 11.6 Perform Android and iOS manual UI review for theme, locale, system authentication, Autofill OEM/system rendering, screen privacy, clipboard privacy, and large-text behavior; record evidence and platform limitations.

## 12. Cleanup and Final Verification

- [x] 12.1 Remove obsolete Manage destination widgets, duplicate modal framing, duplicate reveal controls, direct secret clipboard writes, fixed status icons, and compatibility adapters.
- [x] 12.2 Make the production literal/error/action audit pass with no unapproved user-facing English literal, raw secret-bearing error surface, or actionable empty callback.
- [x] 12.3 Run Dart formatting, Flutter analyzer/LSP diagnostics, the full Flutter test suite, deterministic visual/semantics tests, and `git diff --check`.
- [x] 12.4 Run Android unit/instrumented presentation and privacy checks plus release build validation without clearing installed app data during physical-device deployment.
- [x] 12.5 Run iOS simulator/unit presentation and privacy checks and verify credential-provider behavior remains authenticated and selected-entry-only.
- [x] 12.6 Re-run Rust Autofill tests, workspace Clippy, bridge smoke tests, and generated-binding consistency checks to prove the UI redesign did not change core contracts.
- [x] 12.7 Validate every delta and the complete change with strict OpenSpec validation and create `verification.md` containing commands, results, screenshots/goldens, device evidence, residual risks, and any platform-owned limitations.
