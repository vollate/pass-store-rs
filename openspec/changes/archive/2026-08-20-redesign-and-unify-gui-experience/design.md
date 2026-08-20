## Context

Pars has accumulated a complete set of mobile password-store workflows without a corresponding product-level UI system. The current authenticated shell constructs only the selected Vault, Manage, or Settings page; switching destinations therefore disposes search, browse, selection, and scroll state. Vault is object-oriented while Manage duplicates the same mutations through an action-oriented menu. Settings exposes routine and expert controls at equal prominence, and complex configuration is routed through many unrelated modal sheets.

The present visual layer is mostly Material defaults plus local constants. Production Dart contains approximately 159 literal `Text` strings while the English and Chinese ARB files each contain only 37 messages. Error strings are frequently interpolated directly, explicit semantics are sparse, and there is little breakpoint or large-text coverage. Screenshots also demonstrate contradictory status semantics (`Sync failed` with a success icon), raw Autofill parser diagnostics occupying a Settings card, low-density entry lists, duplicated reveal controls, and weak destructive-action hierarchy.

This redesign crosses Flutter shell state, Vault and mutation orchestration, Settings and onboarding, localization persistence, accessibility, clipboard/privacy adapters, and native Autofill presentation. It must preserve the following established constraints:

- Password-store ciphertext, entry formats, OpenPGP protection, key fingerprints, public material, passphrases, and Rust bridge cryptographic APIs do not change.
- No private-key envelope, unlocked-key cache, derived-key cache, plaintext private-key copy, or new durable secret is introduced.
- Autofill remains path-first, does not match Android package identifiers, does not decrypt during indexing or matching, and decrypts only the authenticated selected entry.
- Entry-detail mutations continue to clear decrypted content before presenting mutation UI and continue to use existing repository, confirmation, optional Git commit, and partial-failure semantics.
- Invalid Autofill indexes continue to fail closed until explicitly rebuilt.
- Native Android Autofill presentations remain restricted to system-allowlisted `RemoteViews` classes.

## Goals / Non-Goals

**Goals:**

- Give Pars one coherent visual, interaction, status, feedback, and modal system in light and dark themes.
- Make the authenticated shell object-oriented: Vault for credentials and contextual mutations, Settings for configuration.
- Preserve useful non-secret navigation state across destination changes without retaining decrypted detail content.
- Make Favorites, Recent, Browse, create, direct copy, single-entry actions, and batch selection visible and understandable.
- Reduce card density and action duplication while preserving every existing vault operation.
- Reorganize Settings and onboarding around routine user goals with advanced capabilities progressively disclosed.
- Provide complete, switchable, persisted English and Chinese localization for Flutter and localized native presentation strings.
- Provide concise user-facing errors with diagnosable details, semantic status indicators, and severity-appropriate feedback.
- Improve screen-reader, large-text, contrast, keyboard/focus, compact-phone, landscape, and wide-screen behavior.
- Apply consistent clipboard clearing, sensitive clipboard metadata, manual lock, and platform screen-capture/background privacy.
- Establish deterministic visual and semantics regression tests so later UI work cannot silently undo the redesign.

**Non-Goals:**

- Redesigning core password-store, Git, key, encryption, or Autofill matching algorithms.
- Adding online accounts, synchronization services, telemetry, remote icon/favicon fetching, or network-dependent branding.
- Adding a new PIN/password authentication secret; accessible gesture entry reuses the existing gesture verifier.
- Migrating the Autofill index schema or restoring legacy package-based matching.
- Replacing Flutter Material with a separate native UI implementation or adding a third-party state-management/design-system package.
- Guaranteeing identical pixel output on Android and iOS where platform authentication or system Autofill owns the surface.

## Decisions

### 1. Implement one change in independently verifiable stages

The implementation follows six stages: foundation, shell, Vault/detail, contextual management, Settings/onboarding, and security/native polish. Each stage must compile and keep the repository test suite green before the next begins. Temporary adapters may bridge old and new widget constructors during a stage, but the completed change will not retain duplicate top-level navigation or parallel legacy UI.

**Alternative considered:** replace every screen in one cutover. This shortens the coexistence period but makes behavioral regressions, localization omissions, and review failures difficult to isolate.

### 2. Use two durable authenticated destinations

The authenticated shell will expose Vault and Settings. Compact windows use Material 3 `NavigationBar`; medium and expanded windows use `NavigationRail`. The dedicated Manage destination is removed. Create is a prominent Vault action, single-entry mutations are contextual to the selected entry, and batch mutations appear only during explicit selection mode.

The shell owns destination selection and non-secret page-state controllers. Vault preserves query, directory, bounded section expansion, selection, and scroll position. Settings preserves category and scroll position. Entry detail is not kept alive behind another destination: leaving Vault, locking, background privacy transitions, or closing detail disposes decrypted content.

**Alternative considered:** retain three tabs and restyle Manage. This preserves current tests but leaves duplicated object-first and action-first mental models and gives infrequent maintenance operations the same prominence as the vault itself.

### 3. Prefer routes/panes for complex work and sheets for short decisions

A shared adaptive surface helper will classify interactions:

- Short choices, confirmations, and compact entry forms use a modal bottom sheet on compact phones and an appropriately constrained dialog on wider windows.
- Entry detail and complex key/store/Git workflows use a full-height route on compact windows and a constrained pane or dialog on wider windows.
- All modal content receives safe-area, keyboard-inset, maximum-width, scroll, title, close/back, and drag-handle behavior from shared primitives.

This replaces per-file sheet framing while retaining the existing workflow functions and repository calls.

**Alternative considered:** continue expressing every secondary workflow as a bottom sheet. The current approach has over thirty sheet entry points and produces weak navigation depth, inconsistent handles, and overlong phone sheets.

### 4. Build a small first-party design system on Flutter ThemeData

`ParsTheme` will define semantic colors and component themes rather than screen-local colors. A narrow `ThemeExtension` may carry status colors not represented by `ColorScheme` (success, warning, info). Shared tokens cover spacing, radius, content widths, icon sizes, and motion duration. Shared components cover:

- page headers and adaptive navigation;
- section headers and empty states;
- compact credential rows and selection rows;
- status badges with matched icon, label, color, and semantics;
- primary, secondary, overflow, and destructive actions;
- adaptive route/sheet framing;
- inline error, details disclosure, and notification banners.

System typography remains the default; no downloadable font or remote asset is added. Service identity uses local path-derived labels and deterministic local glyphs/monograms only.

**Alternative considered:** add a UI framework or bespoke component dependency. Existing Material 3 primitives are sufficient and avoid supply-chain, binary-size, and cross-platform maintenance costs.

### 5. Apply explicit responsive breakpoints and bounded content

The foundation uses Material-oriented width classes: compact below 600 logical pixels, medium from 600 to 839, and expanded at 840 or more. Compact layouts remain single-column. Medium/expanded layouts use a rail and bounded content; Vault may use list-detail composition only when it can guarantee secret disposal on deselection or destination change. Text must remain usable at 200% scaling without clipped actions, hidden confirmation controls, or horizontal scrolling for ordinary prose.

Exact maximum widths remain shared constants and may be tuned by golden tests. The implementation will not infer layout from physical platform alone.

### 6. Persist locale in a separate non-secret UI preference store

A small `UiPreferencesStore` abstraction will persist `system`, `en`, or `zh` in the app-support area using atomic file replacement. Absence, invalid data, or read failure falls back to `system`; locale loading must not block security initialization indefinitely. Fakes support widget tests. `ParsGuiApp` owns the current preference and updates `MaterialApp.locale` immediately.

All production-facing Flutter strings, semantics labels, validation text, notifications, and diagnostic summaries move to ARB resources. Native Android and iOS extension strings remain platform resources but receive equivalent English and Chinese coverage. Raw commands, paths, fingerprints, and backend details are data and are not translated.

**Alternative considered:** store locale in secure storage. Locale is not secret, and coupling appearance startup to Keychain/Keystore availability adds unnecessary failure modes. Extending the Rust config would also create an otherwise unnecessary bridge/config schema change.

### 7. Separate user messages from diagnostic details

Known repository and platform failures will map to localized `UiProblem` values containing severity, concise summary, recovery action, and optional sanitized diagnostics. Main cards and inline errors show the summary only. A Details disclosure or Runtime diagnostics route may show/copy bounded technical data such as a path, command output, or typed error, but never a passphrase, decrypted password, private-key material, or full secret content.

Status badges are derived from status enums, never from a fixed icon. Success, warning, error, unavailable, busy, and neutral states receive matched visual and semantic labels. Autofill invalid-schema status therefore reads as a concise “Needs rebuild” state with a Rebuild action; its parser details remain behind Details.

**Alternative considered:** continue displaying `error.toString()` to maximize debugging information. This produces unstable, untranslated, privacy-sensitive UI and makes ordinary recovery harder.

### 8. Match feedback lifetime to consequence

Transient success such as Copy uses a short live-region notification. Recoverable failures include an action and remain long enough to operate. Destructive confirmation remains blocking. Partial success and post-mutation Git commit failure use a durable inline/result surface that explicitly states the vault mutation was not rolled back. A global message coordinator prevents unrelated messages from silently replacing high-severity results.

### 9. Make Vault sections and rows task-oriented

Vault home presents:

- a visible Favorites section derived from existing favorite metadata;
- a bounded Recent section that is empty when there is no history rather than falling back to all entries;
- Browse for the current directory;
- a separate Search results state while a query is active.

Credential rows become denser than current card-per-entry tiles while keeping at least the platform minimum touch target. They show authoritative display name, parent/service context, visible favorite state, and one accessible direct-copy affordance. Directory rows remain visually distinct. Rows use no network favicon lookup.

Create is exposed from the Vault header/FAB. Selection mode is entered through an explicit Select action or long press, shows selected count, and presents only supported batch actions. Exiting mode clears selection without mutating data.

### 10. Give entry detail one primary hierarchy

Entry detail starts masked and displays one reveal/hide control whose icon, label, tooltip, and semantics reflect current state. Password Copy remains primary. Favorite is a stateful header action. Open URL and field copy remain adjacent to their data. Edit, move, rename, regenerate, QR, and delete are grouped as secondary/overflow actions; Delete uses error semantics and retains human-readable confirmation. Unsupported optional actions are disabled or omitted with an explicit explanation, never wired to no-op callbacks.

Focused edit, regenerate, and delete flows continue to clear and close the decrypted detail surface before opening, preserving the current secret-disposal contract.

### 11. Centralize secret-copy and privacy behavior

A `SensitiveClipboardService` replaces direct `Clipboard.setData` calls for passwords and parsed secret fields. It writes through a platform adapter capable of marking content sensitive where supported, schedules the configured clear operation consistently, cancels superseded timers, and provides localized feedback. Non-secret diagnostic copy may use an ordinary clipboard path.

The authenticated shell exposes Lock now, calling the existing app lock/session-clearing path. Android protects the authenticated window with secure-window policy in release builds. iOS covers authenticated content before application-switcher snapshots and obscures sensitive content during supported capture notifications. Platform abstractions make these policies testable; test/debug-only capture overrides must not be enabled in release.

### 12. Preserve the gesture secret while adding accessible entry

Drawing remains the default gesture interaction. Each dot also exposes selected state and an activation action to assistive technology, with localized Clear and Submit actions. The resulting ordered dot list is verified by the existing gesture repository; no alternative persisted credential is created. Incorrect input clears or safely resets the interaction and announces the localized error through a live region.

### 13. Make onboarding essential-first

Onboarding becomes a capability-driven flow rather than a fixed disabled-chip rail. Required local unlock and a usable store/key configuration are completed before Finish. Biometrics and SSH remain available but may be skipped or deferred to a post-setup checklist and Settings. Technical PGP/store details are disclosed only when the selected setup path needs them. Review clearly distinguishes required incomplete work from optional skipped work.

Existing key preparation, protected-import validation, native pickers, store conflict handling, and transactional commit behavior are reused unchanged.

### 14. Keep Autofill presentation inside platform constraints

Flutter Settings shows `Ready`, `Needs rebuild`, `Unavailable`, or `Busy` plus indexed count and an appropriate action; raw index parser text is not used as the tile subtitle. Rebuild, enrichment, clear, and setup remain separate actions with their current decryption boundaries.

Android matched/no-match layouts continue using only allowlisted view classes, with localized service/source and username/no-match text. The no-match item remains non-filling and non-decrypting. iOS credential-provider text receives equivalent localization and accessible labels. No visual refinement may add package matching, legacy schema fields, or pre-selection decryption.

### 15. Treat visual and accessibility behavior as tested contracts

Tests will cover semantic labels/actions, contrast-token selection, 200% text scaling, compact and expanded layouts, destination state preservation, secret disposal on navigation/lock, locale persistence and live switching, complete ARB key parity, concise error rendering, durable partial-failure feedback, clipboard clearing, and native Autofill presentation restrictions. Deterministic golden/screenshot tests cover representative light/dark English/Chinese Vault, entry detail, Settings, onboarding, lock, empty, loading, and error states.

## Risks / Trade-offs

- **[Large cross-cutting change]** UI regressions may be difficult to localize → Land and validate the six stages independently; retain repository behavior tests while adding surface-level tests before deleting legacy UI.
- **[State preservation retains secrets]** Keeping destination widgets alive could retain decrypted content → Preserve only explicit non-secret view state; dispose detail routes and clear secret content on destination change, lock, background transition, or selection change.
- **[Two destinations reduce immediate discoverability]** Removing Manage may hide advanced workflows → Provide prominent Create and Select affordances, contextual overflow actions, localized tooltips, and onboarding hints; test every former Manage operation from its new entry point.
- **[Localization expansion changes geometry]** Chinese or future translations may wrap differently → Use flexible components, 200% text-scale tests, bounded surfaces, and no fixed-height text containers.
- **[Golden tests become brittle]** Platform font/rendering differences can cause noise → Keep deterministic test fonts/environment where practical and use structural/widget assertions for behavior that does not require pixels.
- **[Secure-window policy blocks support screenshots]** Users and testers may be unable to capture ordinary Settings screens → Default release builds to privacy; keep any debug/test override compile-time or test-only and never expose a secret-persisting bypass.
- **[Native Autofill styling is constrained]** OEM System UI may ignore or restyle presentations → Test only allowlisted hierarchy, required text, and behavior; do not require pixel identity across OEMs.
- **[Additional preference file can corrupt]** Locale state may be unreadable → Use atomic replacement, validate a tiny versioned schema, fail to System locale, and never block vault startup.
- **[Accessible gesture interaction is more verbose]** Dot-by-dot semantics may be slower than drawing → Preserve drawing and biometric paths while making ordered selection, clear, submit, and error announcement reliable.
- **[Dense rows reduce visual separation]** Compact lists can become harder to scan → Retain minimum touch targets, section spacing, service context, selected/favorite state, and contrast-tested dividers/surfaces.

## Migration Plan

1. Add the UI foundation, locale store, semantic feedback model, responsive harness, and tests while existing screens still render through compatibility wrappers.
2. Introduce the two-destination shell and explicit non-secret state controllers. Move create/selection entry points into Vault, then remove the Manage navigation item only after all operations are reachable and tested.
3. Replace Vault rows and entry detail with the new hierarchy. Verify secret clearing, clipboard behavior, favorites, recent bounds, search, browse, loading, and every mutation workflow.
4. Reorganize Settings and onboarding, migrate all remaining production strings to ARB, and replace raw error/status presentation.
5. Add manual lock, capture privacy, accessible gesture actions, and native Autofill/iOS presentation polish through platform adapters.
6. Run full Flutter, Android, iOS, bridge, formatting, static-analysis, visual, semantics, and strict OpenSpec validation; perform physical Android and iOS verification where available.
7. Remove compatibility widgets, legacy Manage destination code, hard-coded production strings, duplicate direct clipboard writes, and obsolete tests.

No vault, key, Git, or Autofill data migration is required. The new UI preference file is created lazily; absence or rollback returns to System locale. Rollback is commit-level: previous binaries ignore the UI preference file and continue reading existing vault and platform data.

## Open Questions

- Tune the shared maximum content widths and exact compact/medium transition using the smallest supported phone and available tablet/simulator evidence before final golden baselines are accepted.
- Determine the strongest iOS screen-capture obscuring behavior available without preventing the system credential-provider extension from completing authentication.
- Decide whether a release-visible “allow screenshots” preference is acceptable; the default and minimum requirement remain protected authenticated content.
