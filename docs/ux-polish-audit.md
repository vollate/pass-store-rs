# Pars GUI UX Polish Audit

This audit closes the roadmap polish pass after the GUI moved from mock data to
real bridge-backed behavior.

## States

- Vault shows refresh progress, recoverable load errors with Retry, and empty
  states for recent entries, search results, store root, and folders.
- Entry detail shows loading, passphrase prompt, decrypt error recovery, copy
  feedback, and clears decrypted state on close.
- Manage operation sheets show per-operation progress, inline validation
  errors, conflict feedback, and summaries after success.
- Settings Git sheets show command progress, stdout/stderr/exit status, and
  recoverable inline errors.
- Settings key and store sheets show no-key/no-store empty states.
- Onboarding shows unavailable repository/key states and recoverable action
  errors.

## Accessibility

- Icon-only buttons in entry detail and QR display use tooltips.
- Bottom navigation uses text labels.
- Gesture input exposes semantic labels for selected dot count.
- Destructive actions require typed confirmation.

## Compact Mobile Audit

Widget coverage includes a 390x844 phone-sized viewport that completes
onboarding, opens Settings, and scrolls to runtime diagnostics without layout
exceptions.

## Theme

The app now provides light and dark Material 3 themes and follows the platform
theme mode. Cards and inputs use 8px corner radius.

## Localization Readiness

Strings remain inline for phase 1 because no localization target is active.
The UI now avoids instructional marketing copy on primary tool screens and keeps
labels short enough for later extraction into `AppLocalizations`.

## Manual Device Note

Android physical-device smoke testing was completed on device `7eaf4718` on
2026-06-24. The debug arm64 APK built successfully, installed over the previous
app, launched package `top.vollate.pars_gui`, and stayed running without an
`AndroidRuntime` crash in the app PID log. Phone-sized widget coverage remains
the repeatable CI substitute; physical device testing is still required before
release cuts.
