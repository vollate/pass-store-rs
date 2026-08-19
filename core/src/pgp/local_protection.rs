use std::time::Duration;
#[cfg(not(test))]
use std::time::Instant;

#[cfg(not(test))]
use pgp::crypto::hash::HashAlgorithm;
#[cfg(not(test))]
use pgp::types::StringToKey;
#[cfg(not(test))]
use rand08::thread_rng;
use serde::{Deserialize, Serialize};

use crate::pgp::backend::{PgpBackendError, PgpBackendResult};

pub(crate) const LOCAL_PROTECTION_POLICY_VERSION: u8 = 2;
pub(crate) const LOCAL_V4_S2K_TARGET: Duration = Duration::from_millis(100);
pub(crate) const LOCAL_V4_S2K_MIN_BYTES: usize = 1 << 20;
pub(crate) const LOCAL_V4_S2K_MAX_BYTES: usize = 1 << 24;
const CALIBRATION_WARMUP_BYTES: usize = 1 << 18;
#[cfg(not(test))]
const CALIBRATION_PASSPHRASE: &[u8] = b"pars-local-policy";
#[cfg(not(test))]
const AES256_KEY_BYTES: usize = 32;
const MAX_VERIFICATION_ROUNDS: usize = 3;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub(crate) struct LocalProtectionPolicy {
    pub(crate) v4_coded_count: u8,
}

impl LocalProtectionPolicy {
    pub(crate) const fn policy_v1() -> Self {
        Self { v4_coded_count: 224 }
    }

    pub(crate) fn metadata(self) -> LocalProtectionPolicyMetadata {
        LocalProtectionPolicyMetadata {
            version: LOCAL_PROTECTION_POLICY_VERSION,
            v4_coded_count: self.v4_coded_count,
        }
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize, Deserialize)]
pub(crate) struct LocalProtectionPolicyMetadata {
    pub(crate) version: u8,
    pub(crate) v4_coded_count: u8,
}

impl LocalProtectionPolicyMetadata {
    pub(crate) fn validated(self) -> Option<LocalProtectionPolicy> {
        let decoded = decode_s2k_count(self.v4_coded_count);
        (self.version == LOCAL_PROTECTION_POLICY_VERSION
            && (LOCAL_V4_S2K_MIN_BYTES..=LOCAL_V4_S2K_MAX_BYTES).contains(&decoded))
        .then_some(LocalProtectionPolicy { v4_coded_count: self.v4_coded_count })
    }
}

pub(crate) fn decode_s2k_count(coded_count: u8) -> usize {
    ((16u32 + u32::from(coded_count & 15)) << (u32::from(coded_count >> 4) + 6)) as usize
}

pub(crate) fn encode_s2k_count_at_most(decoded_count: usize) -> u8 {
    (0u8..=u8::MAX).rev().find(|coded| decode_s2k_count(*coded) <= decoded_count).unwrap_or(0)
}

pub(crate) fn calibrate_v4_policy() -> PgpBackendResult<LocalProtectionPolicy> {
    #[cfg(test)]
    {
        // Unit tests exercise calibration deterministically through `calibrate_v4_policy_with`.
        // Avoid introducing wall-clock timing into unrelated keyring tests.
        Ok(LocalProtectionPolicy {
            v4_coded_count: encode_s2k_count_at_most(LOCAL_V4_S2K_MIN_BYTES),
        })
    }

    #[cfg(not(test))]
    calibrate_v4_policy_with(measure_v4_s2k)
}

pub(crate) fn calibrate_v4_policy_with(
    mut measure: impl FnMut(u8) -> PgpBackendResult<Duration>,
) -> PgpBackendResult<LocalProtectionPolicy> {
    let warmup_count = encode_s2k_count_at_most(CALIBRATION_WARMUP_BYTES);
    let _ = measure(warmup_count)?;

    let minimum_count = encode_s2k_count_at_most(LOCAL_V4_S2K_MIN_BYTES);
    let minimum_elapsed = measure(minimum_count)?;
    if minimum_elapsed.is_zero() {
        return Err(calibration_error());
    }

    let mut coded_count =
        estimate_count(LOCAL_V4_S2K_MIN_BYTES, minimum_elapsed, LOCAL_V4_S2K_TARGET)?;

    for _ in 0..MAX_VERIFICATION_ROUNDS {
        if coded_count == minimum_count {
            break;
        }
        let elapsed = measure(coded_count)?;
        if elapsed.is_zero() {
            return Err(calibration_error());
        }
        if elapsed <= LOCAL_V4_S2K_TARGET {
            break;
        }
        coded_count = estimate_count(decode_s2k_count(coded_count), elapsed, LOCAL_V4_S2K_TARGET)?;
    }

    Ok(LocalProtectionPolicy { v4_coded_count: coded_count })
}

fn estimate_count(
    measured_bytes: usize,
    measured_elapsed: Duration,
    target: Duration,
) -> PgpBackendResult<u8> {
    let elapsed_nanos = measured_elapsed.as_nanos();
    if elapsed_nanos == 0 {
        return Err(calibration_error());
    }
    let estimated = (measured_bytes as u128)
        .saturating_mul(target.as_nanos())
        .checked_div(elapsed_nanos)
        .ok_or_else(calibration_error)?;
    let bounded =
        estimated.clamp(LOCAL_V4_S2K_MIN_BYTES as u128, LOCAL_V4_S2K_MAX_BYTES as u128) as usize;
    Ok(encode_s2k_count_at_most(bounded))
}

#[cfg(not(test))]
fn measure_v4_s2k(coded_count: u8) -> PgpBackendResult<Duration> {
    let s2k = StringToKey::new_iterated(&mut thread_rng(), HashAlgorithm::Sha256, coded_count);
    let started = Instant::now();
    let derived = s2k
        .derive_key(CALIBRATION_PASSPHRASE, AES256_KEY_BYTES)
        .map_err(|_| calibration_error())?;
    let elapsed = started.elapsed();
    drop(derived);
    Ok(elapsed)
}

fn calibration_error() -> PgpBackendError {
    PgpBackendError::CommandFailed("local PGP protection calibration failed".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_and_quantizes_rfc_counts() {
        assert_eq!(decode_s2k_count(160), LOCAL_V4_S2K_MIN_BYTES);
        assert_eq!(decode_s2k_count(224), LOCAL_V4_S2K_MAX_BYTES);
        assert_eq!(encode_s2k_count_at_most(LOCAL_V4_S2K_MIN_BYTES), 160);
        assert_eq!(encode_s2k_count_at_most(LOCAL_V4_S2K_MAX_BYTES), 224);
        let five_mib = 5 * (1 << 20);
        let coded = encode_s2k_count_at_most(five_mib);
        assert!(decode_s2k_count(coded) <= five_mib);
        assert!(coded == u8::MAX || decode_s2k_count(coded + 1) > five_mib);
    }

    #[test]
    fn calibration_estimates_and_quantizes_downward() {
        let policy = calibrate_v4_policy_with(|coded| {
            let bytes = decode_s2k_count(coded) as u64;
            Ok(Duration::from_nanos(bytes.saturating_mul(20)))
        })
        .expect("calibrate");

        let decoded = decode_s2k_count(policy.v4_coded_count);
        assert!(decoded <= 5 * (1 << 20));
        assert!(decoded > 4 * (1 << 20));
    }

    #[test]
    fn calibration_clamps_fast_and_slow_devices() {
        let fast = calibrate_v4_policy_with(|coded| {
            let bytes = decode_s2k_count(coded) as u64;
            Ok(Duration::from_nanos(bytes.saturating_mul(1)))
        })
        .expect("fast calibration");
        assert_eq!(decode_s2k_count(fast.v4_coded_count), LOCAL_V4_S2K_MAX_BYTES);

        let slow = calibrate_v4_policy_with(|coded| {
            let bytes = decode_s2k_count(coded) as u64;
            Ok(Duration::from_nanos(bytes.saturating_mul(300)))
        })
        .expect("slow calibration");
        assert_eq!(decode_s2k_count(slow.v4_coded_count), LOCAL_V4_S2K_MIN_BYTES);
    }

    #[test]
    fn calibration_rejects_invalid_measurements() {
        assert_eq!(
            calibrate_v4_policy_with(|_| Ok(Duration::ZERO)).unwrap_err(),
            calibration_error()
        );
    }

    #[test]
    fn metadata_requires_current_version_and_bounds() {
        let valid = LocalProtectionPolicyMetadata {
            version: LOCAL_PROTECTION_POLICY_VERSION,
            v4_coded_count: 160,
        };
        assert!(valid.validated().is_some());
        assert!(LocalProtectionPolicyMetadata { version: 1, ..valid }.validated().is_none());
        assert!(LocalProtectionPolicyMetadata { v4_coded_count: 159, ..valid }
            .validated()
            .is_none());
    }
}
