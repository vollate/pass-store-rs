use std::path::PathBuf;
use std::time::Instant;
use std::{env, fs};

use pars_core::config::cli::PgpBackendKind;
use pars_core::pgp::backend::{PgpBackend, PgpBackendConfig};
use pars_core::pgp::import::{import_inspected_pgp_key, inspect_pgp_key_bytes};
use pars_core::pgp::rpgp_backend::RpgpBackend;
use pgp::crypto::hash::HashAlgorithm;
use pgp::crypto::sym::SymmetricKeyAlgorithm;
use pgp::types::{S2kParams, SecretParams, StringToKey};
use secrecy::{ExposeSecret, SecretString};

const BENCHMARK_PASSPHRASE: &str = "pars benchmark password";

fn main() {
    let mut args = env::args().skip(1);
    let phase = args.next().expect("phase: import, prepare, or decrypt");
    let fixture_path = PathBuf::from(args.next().expect("fixture path"));
    let keyring_home = PathBuf::from(args.next().expect("keyring path"));
    let inspected = inspect_pgp_key_bytes(fs::read(&fixture_path).expect("read fixture"))
        .expect("inspect fixture");
    let fingerprint = inspected.fingerprint().to_string();
    let passphrase = SecretString::from(BENCHMARK_PASSPHRASE);
    let backend = RpgpBackend::from_config(&PgpBackendConfig {
        backend: PgpBackendKind::PureRust,
        pure_rust_enabled: true,
        keyring_home: Some(keyring_home.display().to_string()),
        ..Default::default()
    })
    .expect("create backend");

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
            print_profiles("stored", prepared.secret_key().expect("stored private key"));
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
            let started = Instant::now();
            let plaintext = backend
                .decrypt_file(&keyring_home.join("benchmark-entry.gpg"), Some(&passphrase))
                .expect("decrypt benchmark entry");
            assert_eq!(plaintext.expose_secret(), "android benchmark secret");
            println!("PARS_PGP_BENCH decrypt_ms={}", started.elapsed().as_millis());
        }
        _ => panic!("unknown phase"),
    }
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

    if label == "stored" {
        assert!(all_packets_are_managed(key));
    }
}

fn all_packets_are_managed(key: &pgp::composed::SignedSecretKey) -> bool {
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
                                count: 224,
                                ..
                            },
                            ..
                        }
                    )
            )
        })
}
