## 1. OpenSpec

- [x] 1.1 Add proposal, design, task list, and new capability spec for mobile
  system autofill.

## 2. Core and Bridge Foundations

- [x] 2.1 Add Rust tests for passphrase-aware read-entry decryption.
- [x] 2.2 Extend `PgpBackend::decrypt_file` to accept an optional passphrase and
  implement it for system/bundled GPG and pure Rust OpenPGP.
- [x] 2.3 Add optional passphrase fields to core and bridge read-entry
  requests, update copy-password behavior, and regenerate FRB bindings.
- [x] 2.4 Update Flutter repository reads and copy-password calls to pass the
  active PGP session passphrase when security state is available.

## 3. Autofill Data Model

- [x] 3.1 Add Rust autofill DTOs, index serialization, service identifier
  normalization, matching, ranking, and credential lookup tests.
- [x] 3.2 Add bridge methods for refreshing, querying, and clearing autofill
  index data.
- [x] 3.3 Add Dart `AutofillRepository`, fake/bridge implementations, and
  focused unit tests.

## 4. Flutter Settings

- [x] 4.1 Add Settings system-autofill surface with status, setup shortcuts,
  refresh, and clear actions.
- [x] 4.2 Refresh the autofill index after successful store/key/passphrase
  setup and when selected-store entries change.
- [x] 4.3 Clear autofill data when the selected store is removed, local store
  data is deleted, or passphrase cache is disabled.

## 5. Android System Integration

- [x] 5.1 Add manifest service declarations, autofill XML metadata, and
  credential provider XML metadata.
- [ ] 5.2 Add Kotlin native bootstrap and secure storage helpers for the
  autofill service process.
- [ ] 5.3 Implement `AutofillService` matching, authentication, and dataset
  response behavior.
- [ ] 5.4 Implement Android Credential Manager password provider behavior.
- [ ] 5.5 Add Android unit or instrumentation coverage for request parsing and
  response construction where host tooling supports it.

## 6. iOS System Integration

- [ ] 6.1 Add Credential Provider extension target, app group/keychain
  entitlements, and build settings.
- [ ] 6.2 Move or mirror mobile runtime paths into the app group container and
  migrate existing mobile data once.
- [ ] 6.3 Sync credential identities from the main app into
  `ASCredentialIdentityStore`.
- [ ] 6.4 Implement extension-side authentication, credential lookup, and
  `ASPasswordCredential` return behavior.
- [ ] 6.5 Add iOS build verification and extension unit coverage where host
  tooling supports it.

## 7. Verification

- [ ] 7.1 Run Rust tests for core, bridge, and autofill matching.
- [ ] 7.2 Run Flutter tests for security, repository, settings, and mobile GUI
  smoke coverage.
- [ ] 7.3 Run static analysis and OpenSpec validation.
- [ ] 7.4 Manually verify Android and iOS autofill enablement and credential
  fill flows on device or simulator.
