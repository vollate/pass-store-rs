## Context

The archived `reprotect-imported-private-keys` change established the correct architecture: a legacy source packet is unlocked once, rewritten as standard protected OpenPGP material, and atomically installed as the single authoritative local record. It intentionally left `sha1-checked` unchanged and selected one fixed v4 local profile: AES-256 CFB, iterated-and-salted SHA-256, coded count 224 (16 MiB).

That implementation produced a 67 ms reference-device decrypt during its original Android release verification, but a current real-device path has been observed near 10 seconds. GnuPG does not repeatedly use a transfer key's original S2K parameters; its agent stores a locally re-protected key and calibrates local S2K work to a short duration. Pars already has the re-protection and atomic-storage pieces, but its fixed work factor neither adapts to a device/build nor proves that every key creation/import path produces the expected local profile.

The performance objective applies after the unavoidable source unlock and migration: a protected key stored under the current local policy must decrypt one password-store entry in less than 800 ms on the reference Android device in a release build.

## Goals / Non-Goals

**Goals:**

- Retain the GnuPG-like pay-once architecture and calibrate v4 local protection for predictable device-local unlock cost.
- Keep local and exported records as standard passphrase-protected OpenPGP material with unchanged fingerprint, public packets, and passphrase.
- Cover imported keys, generated keys, and authorized migration of existing fixed-profile or legacy records.
- Separate and measure file I/O, message/key parsing, S2K, public-key session-key recovery, and payload decryption.
- Preserve atomic replacement, rollback, zeroization, and existing Flutter session expiration.

**Non-Goals:**

- Optimizing or replacing `sha1-checked`; legacy SHA-1 remains a one-time compatibility cost.
- Storing plaintext or an unlocked private key, derived S2K key, or decrypted entry beyond an operation.
- Adding a KeyStore/Keychain private-key envelope or changing durable passphrase-cache policy.
- Changing v6 Argon2/AEAD policy in the same change.
- Changing system-GPG behavior or password-store entry encryption.

## Decisions

### Calibrate the standard v4 local S2K profile

The v4 managed profile remains AES-256 CFB with iterated-and-salted SHA-256 and fresh salt/IV per packet. Its encoded iteration count becomes a policy value calibrated through the exact optimized production SHA-256 S2K path rather than a universal coded count of 224.

The initial policy targets 100 ms for one 32-byte local key derivation, matching GnuPG's order of magnitude and leaving margin for parsing and PKESK/payload decryption under the 800 ms product ceiling. Calibration selects the greatest RFC-encodable count whose verification run stays within the target band, clamped to reviewed v4 policy bounds. The initial decoded-count floor is 1 MiB and the ceiling is 16 MiB. If the floor is slower than the target, the floor remains authoritative and the release benchmark exposes the miss rather than silently weakening protection further.

Calibration uses a fixed non-secret synthetic passphrase and random/non-secret salt, a monotonic timer, one warm-up, a throughput estimate, downward RFC count quantization, and bounded verification runs. Unit tests inject a deterministic timer/calibrator; wall-clock assertions remain device verification rather than CI tests.

Alternatives considered:

- Keeping coded count 224 is simple but has failed to provide a portable latency contract.
- Calibrating against legacy SHA-1 would mix the one-time compatibility path with the normal local policy and could select a dangerously low count because of `sha1-checked`; it is rejected.
- Lowering to one hard-coded count would move the same portability problem rather than solve it.

### Persist one versioned, non-secret calibration result per keyring

The selected v4 encoded count and policy version are persisted atomically as non-secret metadata under `keyring_home`. Calibration runs lazily before the first protected v4 generation/import/preparation that needs policy v2 and is reused thereafter. It does not run during each entry read.

The packet's own standard S2K fields remain sufficient to decrypt/export the key. Metadata exists only to make policy acceptance stable and prevent thermal noise from causing repeated rewrites. Missing, malformed, or stale metadata triggers recalibration before a key is rewritten; it never causes an existing private record to be deleted or overwritten before successful authorization and preparation.

### Treat the old fixed profile as migratable, not always compliant

The accepted-policy predicate compares v4 packets against the persisted policy-v2 count in addition to algorithm and mode. A coded-224 record remains untouched when calibration selects 224; otherwise it is migrated after the same passphrase successfully unlocks every protected packet. Legacy source records still pay their original S2K exactly once before conversion.

Every protected packet in one key receives the same calibrated count but fresh salt and IV. v6 records continue to use the existing Argon2/AEAD predicate. Unprotected input retains existing behavior.

### Generate directly into the managed profile

Protected key generation must not create an rPGP-default protected record and then immediately pay its S2K to rewrite it. Generation creates and signs secret material in memory, applies the calibrated managed protection to all required secret packets, verifies bindings/fingerprint, and atomically stores only the protected result.

Imports and existing-key migration continue to use the one-pass preparation path because they must validate an externally supplied passphrase and source protection.

### Make re-protection commit part of import success

A protected import is one transaction spanning source unlock, calibration lookup, re-protection, binding/fingerprint verification, private/public record commit, and backend confirmation. Failure at any point returns import failure. The backend must not report the key as imported, retain the source-protected packet as a fallback, write only the public record, or allow Flutter to start a PGP session.

This differs from migration of an already installed record. If authorized lazy migration of an existing key fails, the previous private record remains byte-for-byte available for a later retry, but the current preparation/unlock request fails and no new session starts. Preserving the old record is rollback, not successful migration.

### Make performance evidence identify the actual bottleneck

The Android benchmark is extended to report separate durations and packet profiles for backend construction, encrypted-message parsing, target private-key location/loading/parsing, S2K/private-packet unlock, PKESK recovery, and payload decrypt/decompress. Measurements must not print passphrases, private parameters, derived keys, plaintext, or salts.

Release verification uses an application-built bridge/library and an app-managed keyring, confirms that the stored encryption packet matches policy v2, then records cold process preparation and repeated entry decrypt samples. The normative acceptance point is the subsequent decrypt p95 below 800 ms on the reference device; the one-time legacy source unlock is reported separately.

This instrumentation also guards against stale/debug native libraries and against timing passphrase preparation together with entry decryption without identifying each phase.

## Risks / Trade-offs

- **[Risk] Time calibration lowers offline password-guessing work on a slow implementation.** → Calibrate only the optimized SHA-256 local path, enforce a reviewed 1 MiB floor, retain AES-256/SHA-256, and document the GnuPG-like usability/security trade-off.
- **[Risk] Thermal throttling produces unstable calibration.** → Persist one bounded result, use warm-up and verification runs, quantize downward, and never recalibrate on normal reads.
- **[Risk] Moving a keyring to slower hardware preserves an expensive count.** → Treat missing/stale device-policy metadata as requiring recalibration and authorized migration; never rewrite without the passphrase.
- **[Risk] Existing coded-224 keys are rewritten unnecessarily.** → Rewrite only when the persisted calibrated count differs and preparation has already validated all packets.
- **[Risk] Import appears successful even though local optimization failed.** → Make calibrated re-protection and durable backend confirmation mandatory for import success; never fall back to the source profile.
- **[Risk] A performance target encourages caching secret material.** → Keep this change stateless between operations and explicitly prohibit unlocked/derived-key caches.
- **[Risk] Exported keys use the locally calibrated count.** → Keep standard OpenPGP interoperability and the same passphrase, document the local work factor, and leave a distinct stronger transfer-export profile to a future proposal if required.

## Migration Plan

1. Add staged timing/profile diagnostics and reproduce the current 10-second path with the exact release artifact and key packet profile.
2. Add deterministic v4 calibration, bounded policy-v2 metadata, and accepted-policy tests without changing active records.
3. Apply the calibrated profile to protected generation and new imports while retaining current atomic commit behavior.
4. Lazily migrate existing legacy or mismatched fixed-profile records after successful authorization.
5. Run core/bridge tests, GnuPG interoperability, secret-safety checks, and Android release benchmarks; require subsequent decrypt p95 below 800 ms.

Rollback keeps reading all standard OpenPGP records already written. Disabling new calibration does not require reverse migration because packet algorithms and fingerprints remain compatible.

## Open Questions

- Whether private-key export should later apply a separate stronger transfer profile rather than exporting the local calibrated profile requires a separate security/product decision.
