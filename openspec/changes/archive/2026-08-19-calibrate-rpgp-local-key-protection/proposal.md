## Why

The pure-Rust backend already replaces legacy private-key protection with a fixed local OpenPGP profile, but real-device entry unlocks have still been observed near 10 seconds despite the product target of less than 800 milliseconds. Like GnuPG, Pars needs to pay the source S2K cost once and then use a locally calibrated, verifiably fast protected key for subsequent unlocks rather than assuming one fixed iteration count performs acceptably on every device and build.

## What Changes

- Keep import-time and first-authorized-use re-protection as the boundary where legacy source S2K is paid once; never preserve the expensive source packet as the active local decryption record.
- Replace the fixed v4 managed iteration count with a bounded, device-calibrated local OpenPGP protection profile that uses SHA-256 and AES-256 while targeting a short, explicit local unlock duration.
- Apply the calibrated profile consistently to imported keys, newly generated protected keys, and existing pure-Rust records whose current managed profile exceeds the accepted local cost envelope.
- Treat calibration, re-protection, verification, and atomic commit as part of one import transaction. Any failure SHALL make the import fail, SHALL NOT fall back to storing the source protection, and SHALL NOT start a PGP session.
- Persist the calibrated S2K parameters in standard protected OpenPGP secret packets so the canonical fingerprint, public material, passphrase, and private-key export interoperability remain unchanged.
- Instrument and benchmark private-key loading, packet parsing, S2K derivation, PKESK recovery, and payload decryption separately, and require subsequent release-mode entry decryption to complete below 800 milliseconds on the reference Android device.
- Preserve atomic replacement, secret zeroization, passphrase-session expiration, and failure rollback guarantees from the existing re-protection flow.
- Leave replacing or specializing rPGP's `sha1-checked` implementation as a future optional optimization; it remains relevant only to the unavoidable one-time unlock of legacy SHA-1 source packets.
- Do not introduce a platform KeyStore/Keychain private-key envelope, durable unlocked-key cache, plaintext private-key copy, or changed password-store entry format in this change.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `pgp-and-key-management`: Change pure-Rust managed v4 private-key protection from one fixed S2K count to a bounded local calibration policy, migrate overly expensive managed records after authorization, and add an explicit subsequent-decryption performance contract.

## Impact

- Affects `core/src/pgp/rpgp_backend.rs`, pure-Rust key generation/import/preparation, accepted-policy detection, and the Android benchmark tooling.
- Requires deterministic calibration-policy tests plus release-device timing and OpenPGP/GnuPG interoperability verification.
- May add non-secret persisted calibration metadata if the encoded packet count alone is insufficient to prevent repeated recalibration; no bridge request shape or Flutter session policy change is expected.
- Does not change system-GPG behavior, CLI behavior, `.gpg-id`, password-store ciphertext, key fingerprints, or passphrase storage policy.
