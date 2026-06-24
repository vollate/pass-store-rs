# rPGP Mobile OpenPGP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a pass-compatible pure Rust OpenPGP backend for mobile using rPGP.

**Architecture:** Keep `PgpBackend` as the core abstraction. Add `RpgpBackend` behind `PgpBackendKind::PureRust`, store keys in a private file keyring, and route Android/iOS GUI requests to that backend while leaving desktop and CLI on system GnuPG.

**Tech Stack:** Rust, `pgp` crate from rPGP, existing `pars-core`/`pars-bridge`, Flutter FRB generated bindings, Android device `7eaf4718`.

---

### Task 1: Backend Selection Boundary

**Files:**
- Modify: `bridge/src/api.rs`
- Modify: `bridge/tests/bridge_smoke_test.rs`
- Modify: `core/src/pgp/backend.rs`

- [ ] **Step 1: Write the failing bridge/backend-selection test**

Add a smoke test proving that a pure Rust config no longer reports the old
"future milestone" unsupported error and that bridge code can request the
backend through config rather than through a `gpg` path.

- [ ] **Step 2: Run the focused test**

Run: `cargo test -p pars-bridge bridge_smoke_test -- --nocapture`
Expected: fail because `PgpBackendKind::PureRust` is still unsupported.

- [ ] **Step 3: Change bridge helper return type**

Replace the concrete `SystemGpgBackend` helper with a boxed trait object:

```rust
fn pgp_backend(
    config_path: &str,
    pgp_executable: Option<&str>,
) -> Result<Box<dyn PgpBackend>, BridgeFailure>
```

System and bundled configs should return `Box::new(SystemGpgBackend::from_config(...))`.
Pure Rust should return `Box::new(RpgpBackend::from_config(...))` after Task 2
adds the concrete backend.

- [ ] **Step 4: Run the focused test again**

Run: `cargo test -p pars-bridge bridge_smoke_test -- --nocapture`
Expected: pass after Task 2 provides `RpgpBackend`.

### Task 2: rPGP Keyring

**Files:**
- Modify: `core/Cargo.toml`
- Modify: `core/src/pgp/mod.rs`
- Create: `core/src/pgp/rpgp_backend.rs`
- Test: `core/src/pgp/rpgp_backend.rs`

- [ ] **Step 1: Add failing keyring tests**

Tests:

- importing a public key stores it under `public/<fingerprint>.asc`
- importing a private key stores it under `private/<fingerprint>.asc`
- listing merges public/private records by fingerprint
- export returns the original armored text

- [ ] **Step 2: Run the focused test**

Run: `cargo test -p pars-core pgp::rpgp_backend -- --nocapture`
Expected: fail because the module does not exist.

- [ ] **Step 3: Add dependency and minimal backend**

Add `pgp` plus any required helper crates. Implement `RpgpBackend::from_config`,
directory creation, import/list/export, and fingerprint/identity extraction.

- [ ] **Step 4: Run the focused test**

Run: `cargo test -p pars-core pgp::rpgp_backend -- --nocapture`
Expected: pass.

### Task 3: Entry Encryption And Decryption

**Files:**
- Modify: `core/src/pgp/rpgp_backend.rs`
- Modify: `core/src/gui/mod.rs`
- Test: `core/src/pgp/rpgp_backend.rs`
- Test: `core/src/gui/mod.rs`

- [ ] **Step 1: Add failing pure Rust entry tests**

Tests:

- `.gpg-id` containing a stored key fingerprint encrypts an entry.
- decrypting that entry returns the original plaintext.
- missing recipients return a PGP error that names the missing recipient.

- [ ] **Step 2: Run the focused test**

Run: `cargo test -p pars-core rpgp_encrypts_and_decrypts_entry -- --nocapture`
Expected: fail because encryption/decryption are not implemented.

- [ ] **Step 3: Implement minimal message crypto**

Use rPGP composed message APIs to encrypt plaintext to binary output and decrypt
with available private keys. Keep passphrase-protected private-key UX out of this
milestone unless the crate API makes empty/passphrase handling trivial.

- [ ] **Step 4: Run focused and core tests**

Run: `cargo test -p pars-core pgp::rpgp_backend -- --nocapture`
Run: `cargo test -p pars-core --test pgp_backend_test -- --nocapture`
Expected: pass.

### Task 4: Flutter Mobile Defaults

**Files:**
- Modify: `gui/lib/main.dart`
- Modify: `gui/lib/services/bridge_backed_repository.dart`
- Remove: `gui/lib/services/bundled_gpg.dart`
- Remove: `gui/test/bundled_gpg_test.dart`
- Modify: `gui/test/bridge_backed_repository_test.dart`

- [ ] **Step 1: Add failing repository test**

Test that Android/iOS runtime diagnostics reports `Pure Rust OpenPGP (rPGP)` and
does not pass a bundled `gpg2` executable.

- [ ] **Step 2: Run Flutter focused tests**

Run: `cd gui && flutter test test/bridge_backed_repository_test.dart`
Expected: fail until the repository can request `pure_rust`.

- [ ] **Step 3: Remove bundled-GnuPG resolver usage**

Stop importing `bundled_gpg.dart`, stop resolving `gpg2` in `main.dart`, and add
a small backend-selection value that sends `pure_rust` on Android/iOS and leaves
desktop on system GPG.

- [ ] **Step 4: Run Flutter focused tests**

Run: `cd gui && flutter test test/bridge_backed_repository_test.dart`
Expected: pass.

### Task 5: Cleanup And Verification

**Files:**
- Modify: `docs/platform-packaging.md`
- Modify: `docs/THIRD_PARTY_PACKAGING_NOTICES.md`
- Delete: mobile bundled-GnuPG asset placeholders and native packaging hooks if unused.

- [ ] **Step 1: Remove mobile bundled-GnuPG packaging**

Remove Android `libgpg2.so` lookup, iOS GnuPG copy phase, Flutter GnuPG assets,
and related documentation. Keep only Rust bridge packaging.

- [ ] **Step 2: Regenerate bridge bindings**

Run the existing `flutter_rust_bridge_codegen generate` command from project
configuration.

- [ ] **Step 3: Run verification**

Run:

```bash
cargo fmt
cargo test -p pars-core pgp
cargo test -p pars-bridge
cd gui && dart format lib test
cd gui && flutter test test/bridge_backed_repository_test.dart
cd gui && flutter analyze
cd gui && flutter build apk --debug --target-platform android-arm64
cd gui && flutter install -d 7eaf4718 --debug
adb -s 7eaf4718 shell am start -n top.vollate.pars_gui/.MainActivity
```

Expected: every command exits 0 and the app launches on device `7eaf4718`.

- [ ] **Step 4: Commit**

Run:

```bash
git add .
git commit --no-gpg-sign -m "Implement rPGP mobile OpenPGP backend"
```
