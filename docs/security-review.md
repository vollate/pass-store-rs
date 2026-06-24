# Pars GUI Security Review

This review covers the GUI roadmap security hardening pass for local app
access, password-store file access, Git operations, clipboard use, bridge
serialization, and platform storage.

## Threat Model

| Scenario | Risk | Current control |
| --- | --- | --- |
| Local attacker opens an unattended app session | Password entries or cached passphrases may be exposed | Gesture lock, optional biometrics, lock-on-resume, auto-lock timeout, PGP session expiration |
| Compromised clipboard or clipboard history | Copied passwords may outlive the intended action | Clipboard copy uses timeout clearing in core and GUI entry detail has a clear timer |
| Malicious password-store path | Path traversal could read/write outside the selected store | `EntryRef` and core path checks reject paths outside the root |
| Malicious Git remote or advanced args | Shell injection or arbitrary command execution | Advanced Git args reject shell syntax and always run inside the selected store |
| Bridge serialization accidentally exposes secrets | Secrets may appear in command output, logs, or diagnostics | Bridge DTOs use structured fields; diagnostics avoid entry content, passphrases, and key material |

## Audit Findings

- No production Flutter `print` or `debugPrint` calls log secrets.
- Git command output is displayed only for explicit Git operations; advanced args reject shell metacharacters before execution.
- Rust clipboard implementations accept `SecretString` and zeroize after writing to platform clipboard commands.
- Rust PGP and insert/edit flows use `secrecy` and `zeroize` where buffers are mutable.
- Flutter controllers that collect PGP passphrases or imported private keys are cleared after submit.
- Decrypted entry content is scoped to `EntryDetailSheet` state and cleared on close/dispose; widget tests assert the content is removed.
- Platform secure storage is used for gesture verifier, biometric enablement, onboarding completion, optional PGP passphrase cache, lock settings, and PGP session timeout.

## Regression Coverage

- `core/tests/gui_api_test.rs`
  - `entry_ref_rejects_path_traversal`
  - `validate_git_args_rejects_shell_syntax`
  - `run_git_args_runs_inside_selected_store_path`
  - `run_git_args_preserves_failed_command_output`
- `gui/test/mobile_gui_smoke_test.dart`
  - clears parsed entry detail content when closed
  - clears background PGP session on lock
  - rejects and renders failed advanced Git output without shell execution
- `gui/test/security_repository_test.dart`
  - persists and clears secure-storage settings
  - expires PGP sessions by selected timeout
  - keeps the session locked when biometric authentication fails

## Platform Storage Review

The GUI uses `flutter_secure_storage` for persisted security settings and
optional PGP passphrase caching. PGP session passphrases remain process-local
and are cleared on lock, explicit clear, or expiration. Dart strings cannot be
zeroized reliably, so sensitive text controllers are cleared promptly and
long-lived storage is limited to explicit opt-in secure storage.

## OpenPGP Update Story

Phase 1 uses configured system GPG. Bundled OpenPGP artifacts are not shipped
yet; when a platform package bundles them, the release must pin the version,
document the source and license in `THIRD_PARTY_PACKAGING_NOTICES.md`, expose
the active backend in runtime diagnostics, and include an update procedure in
the platform release notes.

## Residual Risks

- Dart VM string memory cannot guarantee zeroization for passphrases or
decrypted entry content.
- Clipboard managers may retain history outside the app's control.
- User-configured Git remotes can still be malicious; the app prevents shell
injection but cannot make remote content trustworthy.
- Full mobile secure-enclave/keychain behavior still requires device-level
manual testing during release qualification.
