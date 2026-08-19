use std::path::PathBuf;
use std::time::Instant;
use std::{env, fs};

use pars_core::config::cli::PgpBackendKind;
use pars_core::pgp::backend::{PgpBackend, PgpBackendConfig};
use pars_core::pgp::import::{import_inspected_pgp_key, inspect_pgp_key_bytes};
use pars_core::pgp::rpgp_backend::{RpgpBackend, RpgpDecryptProfile};
use pgp::crypto::hash::HashAlgorithm;
use pgp::crypto::sym::SymmetricKeyAlgorithm;
use pgp::types::{S2kParams, SecretParams, StringToKey};
use secrecy::{ExposeSecret, SecretString};

const BENCHMARK_PASSPHRASE: &str = "pars legacy fixture password";

fn main() {
    let mut args = env::args().skip(1);
    let phase = args.next().expect("phase: import, profile, prepare, or decrypt");
    let fixture_path = PathBuf::from(args.next().expect("fixture path"));
    let keyring_home = PathBuf::from(args.next().expect("keyring path"));
    let inspected = inspect_pgp_key_bytes(fs::read(&fixture_path).expect("read fixture"))
        .expect("inspect fixture");
    let fingerprint = inspected.fingerprint().to_string();
    let passphrase = SecretString::from(
        env::var("PARS_PGP_BENCH_PASSPHRASE").unwrap_or_else(|_| BENCHMARK_PASSPHRASE.to_string()),
    );
    let backend_started = Instant::now();
    let backend = RpgpBackend::from_config(&PgpBackendConfig {
        backend: PgpBackendKind::PureRust,
        pure_rust_enabled: true,
        keyring_home: Some(keyring_home.display().to_string()),
        ..Default::default()
    })
    .expect("create backend");
    println!("PARS_PGP_BENCH backend_create_ms={}", backend_started.elapsed().as_millis());

    match phase.as_str() {
        "import" => {
            print_profiles("source", inspected.secret_key().expect("private fixture"));
            let started = Instant::now();
            let outcome = import_inspected_pgp_key(&backend, &inspected, Some(&passphrase), None)
                .expect("import fixture");
            println!("PARS_PGP_BENCH import_ms={}", started.elapsed().as_millis());
            assert_eq!(outcome.fingerprint, fingerprint);

            let exported = backend.export_private_key(&fingerprint, None).expect("export prepared");
            let prepared = inspect_pgp_key_bytes(exported.armored_text.into_bytes())
                .expect("inspect prepared");
            let stored_key = prepared.secret_key().expect("stored private key");
            print_profiles("stored", stored_key);
            let policy_metadata: serde_json::Value = serde_json::from_slice(
                &fs::read(keyring_home.join("local-protection-policy-v2.json"))
                    .expect("read local policy metadata"),
            )
            .expect("parse local policy metadata");
            let policy_version = policy_metadata["version"].as_u64().expect("policy version");
            let policy_count = policy_metadata["v4_coded_count"]
                .as_u64()
                .and_then(|value| u8::try_from(value).ok())
                .expect("policy v4 coded count");
            println!(
                "PARS_PGP_BENCH policy_version={policy_version} policy_v4_coded_count={policy_count}"
            );
            assert_eq!(policy_version, 2);
            assert!(all_packets_are_managed(stored_key, policy_count));
            prepared
                .validate_passphrase(Some(&passphrase))
                .expect("same passphrase unlocks stored key");

            let encrypted_path = keyring_home.join("benchmark-entry.gpg");
            backend
                .encrypt_content(
                    &SecretString::new("android benchmark secret".into()),
                    &encrypted_path,
                    &[fingerprint],
                )
                .expect("encrypt benchmark entry");
        }
        "profile" => {
            let mut private_key_count = 0;
            for key in backend.list_keys().expect("list installed keys") {
                if !key.has_private_key {
                    continue;
                }
                let exported = backend
                    .export_private_key(&key.fingerprint, None)
                    .expect("export installed private key for in-process inspection");
                let inspected = inspect_pgp_key_bytes(exported.armored_text.into_bytes())
                    .expect("inspect installed private key");
                let installed_key = inspected.secret_key().expect("installed private key");
                let label = format!("installed_{private_key_count}");
                print_profiles(&label, installed_key);
                profile_packet_unlock_costs(&label, installed_key);
                private_key_count += 1;
            }
            println!("PARS_PGP_BENCH installed_private_key_count={private_key_count}");
            let policy_path = keyring_home.join("local-protection-policy-v2.json");
            if policy_path.exists() {
                let policy_metadata: serde_json::Value =
                    serde_json::from_slice(&fs::read(policy_path).expect("read policy metadata"))
                        .expect("parse policy metadata");
                println!(
                    "PARS_PGP_BENCH policy_version={} policy_v4_coded_count={}",
                    policy_metadata["version"], policy_metadata["v4_coded_count"]
                );
            } else {
                println!("PARS_PGP_BENCH policy_metadata=absent");
            }
        }
        "prepare" => {
            let started = Instant::now();
            let prepared =
                backend.prepare_private_key(&fingerprint, &passphrase).expect("prepare stored key");
            println!(
                "PARS_PGP_BENCH prepare_ms={} migrated={}",
                started.elapsed().as_millis(),
                prepared.migrated
            );
        }
        "decrypt" => {
            let samples = env::var("PARS_PGP_BENCH_SAMPLES")
                .ok()
                .and_then(|value| value.parse::<usize>().ok())
                .filter(|value| *value > 0)
                .unwrap_or(1);
            let mut totals = Vec::with_capacity(samples);
            for sample in 0..samples {
                let started = Instant::now();
                let (plaintext, profile) = backend
                    .decrypt_file_profiled(
                        &keyring_home.join("benchmark-entry.gpg"),
                        Some(&passphrase),
                    )
                    .expect("decrypt benchmark entry");
                let total = started.elapsed();
                assert_eq!(plaintext.expose_secret(), "android benchmark secret");
                print_decrypt_profile(sample, total, profile);
                totals.push(total.as_micros());
            }
            totals.sort_unstable();
            let p95_index = (totals.len() * 95).div_ceil(100).saturating_sub(1);
            println!(
                "PARS_PGP_BENCH decrypt_samples={} decrypt_p95_us={}",
                samples, totals[p95_index]
            );
        }
        _ => panic!("unknown phase"),
    }
}

fn print_decrypt_profile(sample: usize, total: std::time::Duration, profile: RpgpDecryptProfile) {
    println!(
        concat!(
            "PARS_PGP_BENCH sample={} total_us={} encrypted_read_us={} ",
            "message_parse_us={} private_key_read_parse_us={} private_packet_s2k_us={} ",
            "pkesk_recovery_us={} payload_decrypt_decompress_us={}"
        ),
        sample,
        total.as_micros(),
        profile.encrypted_read.as_micros(),
        profile.message_parse.as_micros(),
        profile.private_key_read_parse.as_micros(),
        profile.private_packet_s2k.as_micros(),
        profile.pkesk_recovery.as_micros(),
        profile.payload_decrypt_decompress.as_micros(),
    );
}

fn print_profiles(label: &str, key: &pgp::composed::SignedSecretKey) {
    for (index, params) in std::iter::once(key.primary_key.secret_params())
        .chain(key.secret_subkeys.iter().map(|subkey| subkey.key.secret_params()))
        .enumerate()
    {
        let profile = match params {
            SecretParams::Encrypted(encrypted) => match encrypted.string_to_key_params() {
                S2kParams::Cfb { sym_alg, s2k, .. }
                | S2kParams::MalleableCfb { sym_alg, s2k, .. } => match s2k {
                    StringToKey::IteratedAndSalted { hash_alg, count, .. } => {
                        format!("{sym_alg:?}/{hash_alg:?}/coded-{count}")
                    }
                    other => format!("{sym_alg:?}/{other:?}"),
                },
                S2kParams::Aead {
                    sym_alg, s2k: StringToKey::Argon2 { t, p, m_enc, .. }, ..
                } => format!("{sym_alg:?}/Argon2/t-{t}/p-{p}/m-{m_enc}"),
                S2kParams::Aead { sym_alg, .. } => format!("{sym_alg:?}/AEAD"),
                other => format!("{other:?}"),
            },
            SecretParams::Plain(_) => "unprotected".to_string(),
        };
        println!("PARS_PGP_BENCH {label}_packet_{index}={profile}");
    }
}

fn profile_packet_unlock_costs(label: &str, key: &pgp::composed::SignedSecretKey) {
    let password = pgp::types::Password::from("pars-profile-synthetic-password");
    let started = Instant::now();
    let _ = key.primary_key.unlock(&password, |_, _| Ok(()));
    println!(
        "PARS_PGP_BENCH {label}_packet_0_synthetic_unlock_us={}",
        started.elapsed().as_micros()
    );
    for (index, subkey) in key.secret_subkeys.iter().enumerate() {
        let started = Instant::now();
        let _ = subkey.key.unlock(&password, |_, _| Ok(()));
        println!(
            "PARS_PGP_BENCH {label}_packet_{}_synthetic_unlock_us={}",
            index + 1,
            started.elapsed().as_micros()
        );
    }
}

fn all_packets_are_managed(key: &pgp::composed::SignedSecretKey, policy_count: u8) -> bool {
    std::iter::once(key.primary_key.secret_params())
        .chain(key.secret_subkeys.iter().map(|subkey| subkey.key.secret_params()))
        .all(|params| {
            matches!(
                params,
                SecretParams::Encrypted(encrypted)
                    if matches!(
                        encrypted.string_to_key_params(),
                        S2kParams::Cfb {
                            sym_alg: SymmetricKeyAlgorithm::AES256,
                            s2k: StringToKey::IteratedAndSalted {
                                hash_alg: HashAlgorithm::Sha256,
                                count,
                                ..
                            },
                            ..
                        } if *count == policy_count
                    )
            )
        })
}
