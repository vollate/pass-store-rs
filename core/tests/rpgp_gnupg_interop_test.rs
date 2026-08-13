use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use pars_core::config::cli::PgpBackendKind;
use pars_core::pgp::backend::{
    KeyGenerationRequest, PgpBackend, PgpBackendConfig, SystemGpgBackend,
};
use pars_core::pgp::import::{
    import_inspected_pgp_key, import_pgp_key_text, inspect_pgp_key_bytes, PgpImportError,
    PgpImportOutcome,
};
use pars_core::pgp::rpgp_backend::RpgpBackend;
use pars_core::util::test_util::{gpg_key_gen_batch, PgpKeyMaterialFixture};
use pgp::crypto::hash::HashAlgorithm;
use pgp::crypto::sym::SymmetricKeyAlgorithm;
use pgp::types::{S2kParams, SecretParams, StringToKey};
use secrecy::{ExposeSecret, SecretString};

#[test]
fn pure_rust_reprotects_the_low_cost_legacy_sha1_ci_fixture() {
    const PASSPHRASE: &str = "pars legacy fixture password";
    let material = include_bytes!("fixtures/legacy-sha1-coded-1-private.asc").to_vec();
    let inspected = inspect_pgp_key_bytes(material).expect("inspect legacy CI fixture");
    let fingerprint = inspected.fingerprint().to_string();
    let source_key = inspected.secret_key().expect("private fixture");
    assert!(
        all_protected_packets_match(source_key, |params| {
            matches!(
                params,
                S2kParams::Cfb {
                    s2k: StringToKey::IteratedAndSalted {
                        hash_alg: HashAlgorithm::Sha1,
                        count: 1,
                        ..
                    },
                    ..
                }
            )
        }),
        "unexpected fixture profiles: {:?}",
        protected_packet_profiles(source_key)
    );

    let target = InteropContext::new();
    let outcome = import_inspected_pgp_key(
        &target.rpgp,
        &inspected,
        Some(&SecretString::from(PASSPHRASE)),
        None,
    )
    .expect("re-protect CI fixture");
    assert_eq!(outcome.fingerprint, fingerprint);

    let exported = target.rpgp.export_private_key(&fingerprint, None).expect("export prepared key");
    let prepared =
        inspect_pgp_key_bytes(exported.armored_text.into_bytes()).expect("inspect prepared key");
    assert!(all_protected_packets_match(
        prepared.secret_key().expect("prepared private key"),
        |params| {
            matches!(
                params,
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
        }
    ));
    prepared
        .validate_passphrase(Some(&SecretString::from(PASSPHRASE)))
        .expect("same passphrase unlocks prepared fixture");
    assert_eq!(prepared.fingerprint(), fingerprint);

    let encrypted_path = target.temp.path().join("prepared-ci-entry.gpg");
    target
        .rpgp
        .encrypt_content(
            &SecretString::new("prepared CI secret".into()),
            &encrypted_path,
            &[fingerprint],
        )
        .expect("encrypt with migrated fixture");
    let decrypted = target
        .rpgp
        .decrypt_file(&encrypted_path, Some(&SecretString::from(PASSPHRASE)))
        .expect("decrypt migrated fixture with the same passphrase");
    assert_eq!(decrypted.expose_secret(), "prepared CI secret");
    assert!(
        target
            .rpgp
            .decrypt_file(&encrypted_path, Some(&SecretString::from("wrong passphrase")))
            .is_err(),
        "the migrated key must still require its original passphrase"
    );
}

#[test]
fn optional_gnupg_decrypts_rpgp_encrypted_entry() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let fingerprint = context.generate_rpgp_key();
    context.import_private_key_to_gnupg(&fingerprint);

    let encrypted_path = context.temp.path().join("rpgp-to-gpg.gpg");
    context
        .rpgp
        .encrypt_content(&SecretString::new("rpgp secret".into()), &encrypted_path, &[fingerprint])
        .unwrap();

    let output = gpg_command(&context.gnupg_home)
        .args(["--batch", "--yes", "--pinentry-mode", "loopback", "--decrypt"])
        .arg(&encrypted_path)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "gpg decrypt failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "rpgp secret");
}

#[test]
fn optional_rpgp_decrypts_gnupg_encrypted_entry() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let fingerprint = context.generate_rpgp_key();
    context.import_public_key_to_gnupg(&fingerprint);

    let plaintext_path = context.temp.path().join("plaintext.txt");
    let encrypted_path = context.temp.path().join("gpg-to-rpgp.gpg");
    std::fs::write(&plaintext_path, "gpg secret").unwrap();
    let output = gpg_command(&context.gnupg_home)
        .args([
            "--batch",
            "--yes",
            "--trust-model",
            "always",
            "--recipient",
            &fingerprint,
            "--output",
        ])
        .arg(&encrypted_path)
        .arg("--encrypt")
        .arg(&plaintext_path)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "gpg encrypt failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let decrypted = context.rpgp.decrypt_file(&encrypted_path, None).unwrap();
    assert_eq!(decrypted.expose_secret(), "gpg secret");
}

#[test]
fn optional_gnupg_exported_keys_import_through_the_shared_inspector() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let email = "interop-import@example.com";
    context.generate_gnupg_key(email, None);
    let fingerprint = context.gnupg_fingerprint(email);

    // GnuPG-produced material, in each encoding a user could realistically hand us.
    for (label, armored, private) in [
        ("armored public", true, false),
        ("binary public", false, false),
        ("armored private", true, true),
        ("binary private", false, true),
    ] {
        let material = context.gnupg_export(&fingerprint, private, armored, None);
        let target = InteropContext::new();
        let outcome = import_pgp_key_bytes_into(&target.rpgp, material)
            .unwrap_or_else(|error| panic!("{label} from GnuPG should import: {error}"));

        assert_eq!(outcome.fingerprint, fingerprint, "{label}");
        assert_eq!(outcome.inspection.armored, armored, "{label}");
        assert_eq!(outcome.inspection.has_private_key, private, "{label}");
    }
}

#[test]
fn optional_gnupg_protected_private_key_requires_its_passphrase() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let email = "interop-protected@example.com";
    let passphrase = "gnupg interop passphrase";
    context.generate_gnupg_key(email, Some(passphrase));
    let fingerprint = context.gnupg_fingerprint(email);
    let material = context.gnupg_export(&fingerprint, true, true, Some(passphrase));

    let inspected = inspect_pgp_key_bytes(material.clone()).expect("inspect GnuPG private key");
    assert!(
        inspected.requires_passphrase(),
        "a GnuPG key exported under a passphrase must be reported as protected"
    );

    for (label, supplied, expected) in [
        ("absent", None, PgpImportError::PassphraseRequired),
        ("wrong", Some(SecretString::from("not it")), PgpImportError::IncorrectPassphrase),
    ] {
        let target = InteropContext::new();
        let error = import_inspected_pgp_key(
            &target.rpgp,
            &inspect_pgp_key_bytes(material.clone()).expect("inspect"),
            supplied.as_ref(),
            None,
        )
        .expect_err("import should be rejected");
        assert_eq!(error, expected, "{label} passphrase");
        assert!(
            target.rpgp.list_keys().expect("list keys").is_empty(),
            "{label} passphrase must not mutate the keyring"
        );
    }

    let target = InteropContext::new();
    let outcome = import_inspected_pgp_key(
        &target.rpgp,
        &inspect_pgp_key_bytes(material).expect("inspect"),
        Some(&SecretString::from(passphrase)),
        None,
    )
    .expect("correct passphrase should import");
    assert_eq!(outcome.fingerprint, fingerprint);
}

#[test]
fn optional_gnupg_maximum_sha1_s2k_is_reprotected_and_remains_interoperable() {
    if !run_interop_tests() {
        return;
    }
    const PASSPHRASE: &str = "maximum legacy S2K passphrase";
    const MAXIMUM_CODED_COUNT: u8 = 255;
    const MAXIMUM_DECODED_COUNT: usize = 65_011_712;

    assert_eq!(decode_s2k_count(MAXIMUM_CODED_COUNT), MAXIMUM_DECODED_COUNT);

    let source = InteropContext::new();
    let email = "interop-maximum-sha1@example.com";
    source.generate_gnupg_key(email, Some(PASSPHRASE));
    let fingerprint = source.gnupg_fingerprint(email);
    let legacy_material = source.gnupg_export_sha1(&fingerprint, PASSPHRASE, MAXIMUM_DECODED_COUNT);
    let inspected = inspect_pgp_key_bytes(legacy_material).expect("inspect legacy GnuPG key");
    assert!(
        all_protected_packets_match(inspected.secret_key().expect("secret key"), |params| {
            matches!(
                params,
                S2kParams::Cfb {
                    s2k: StringToKey::IteratedAndSalted {
                        hash_alg: HashAlgorithm::Sha1,
                        count: MAXIMUM_CODED_COUNT,
                        ..
                    },
                    ..
                }
            )
        }),
        "GnuPG must actually export SHA-1 with coded count 255 for this test; got {:?}",
        protected_packet_profiles(inspected.secret_key().expect("secret key"))
    );

    let target = InteropContext::new();
    let outcome = import_inspected_pgp_key(
        &target.rpgp,
        &inspected,
        Some(&SecretString::from(PASSPHRASE)),
        None,
    )
    .expect("import and re-protect maximum SHA-1 S2K key");
    assert_eq!(outcome.fingerprint, fingerprint);

    let prepared_export =
        target.rpgp.export_private_key(&fingerprint, None).expect("export prepared private key");
    let prepared = inspect_pgp_key_bytes(prepared_export.armored_text.as_bytes().to_vec())
        .expect("inspect prepared private key");
    assert!(all_protected_packets_match(
        prepared.secret_key().expect("prepared secret key"),
        |params| {
            matches!(
                params,
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
        }
    ));
    prepared
        .validate_passphrase(Some(&SecretString::from(PASSPHRASE)))
        .expect("the same passphrase unlocks the prepared key");

    let gnupg_target = InteropContext::new();
    gnupg_target.import_armored_private_to_gnupg(&prepared_export.armored_text);
    assert_eq!(gnupg_target.gnupg_fingerprint(email), fingerprint);

    let encrypted_path = target.temp.path().join("prepared-to-gpg.gpg");
    target
        .rpgp
        .encrypt_content(
            &SecretString::new("prepared interop secret".into()),
            &encrypted_path,
            &[fingerprint],
        )
        .expect("encrypt with prepared public key");
    let output = gpg_command(&gnupg_target.gnupg_home)
        .args([
            "--batch",
            "--yes",
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            PASSPHRASE,
            "--decrypt",
        ])
        .arg(&encrypted_path)
        .output()
        .expect("run GnuPG decrypt");
    assert!(
        output.status.success(),
        "GnuPG decrypt failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(output.stdout, b"prepared interop secret");
}

#[test]
fn optional_system_gpg_import_returns_canonical_fingerprint_and_survives_duplicates() {
    if !run_interop_tests() {
        return;
    }
    // Guards the bug this change fixes: system GPG used to return an empty fingerprint from import,
    // so nothing downstream could bind a session or a cache to the key.
    let context = InteropContext::new();
    let fixture = PgpKeyMaterialFixture::generate(None);
    let gpg = context.system_gpg_backend();

    let first = import_pgp_key_bytes_into(&gpg, fixture.armored_public.clone())
        .expect("import into system GPG");
    assert_eq!(first.fingerprint, fixture.fingerprint);
    assert!(!first.fingerprint.is_empty());
    assert!(first.identity.contains("fixture@example.com"), "{}", first.identity);

    let duplicate = import_pgp_key_bytes_into(&gpg, fixture.armored_public.clone())
        .expect("re-import of an existing key");
    assert_eq!(duplicate.fingerprint, first.fingerprint);

    let binary_private = import_pgp_key_bytes_into(&gpg, fixture.binary_private.clone())
        .expect("binary private material should import");
    assert_eq!(binary_private.fingerprint, fixture.fingerprint);
    assert!(binary_private.imported_private_key);
}

#[test]
fn optional_system_gpg_import_rejects_a_wrong_passphrase_without_importing() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let passphrase = "system gpg passphrase";
    let fixture = PgpKeyMaterialFixture::generate(Some(passphrase));
    let gpg = context.system_gpg_backend();

    let error = import_pgp_key_text(
        &gpg,
        fixture.armored_private_text(),
        Some(&SecretString::from("not it")),
        None,
    )
    .expect_err("wrong passphrase should be rejected");
    assert_eq!(error, PgpImportError::IncorrectPassphrase);
    assert!(
        gpg.inspect_fingerprint(&fixture.fingerprint).is_err(),
        "a rejected passphrase must leave no key in the GnuPG keyring"
    );

    let outcome = import_pgp_key_text(
        &gpg,
        fixture.armored_private_text(),
        Some(&SecretString::from(passphrase)),
        None,
    )
    .expect("correct passphrase should import");
    assert_eq!(outcome.fingerprint, fixture.fingerprint);
}

fn import_pgp_key_bytes_into(
    backend: &dyn PgpBackend,
    material: Vec<u8>,
) -> Result<PgpImportOutcome, PgpImportError> {
    let inspected = inspect_pgp_key_bytes(material)?;
    import_inspected_pgp_key(backend, &inspected, None, None)
}

struct InteropContext {
    temp: tempfile::TempDir,
    gnupg_home: std::path::PathBuf,
    rpgp: RpgpBackend,
}

impl InteropContext {
    fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let gnupg_home = temp.path().join("gnupg");
        let rpgp_home = temp.path().join("rpgp");
        std::fs::create_dir_all(&gnupg_home).unwrap();
        lock_down_dir(&gnupg_home);
        let rpgp = RpgpBackend::from_config(&PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            bundled_gpg_path: None,
            system_gpg_path: None,
            pure_rust_enabled: true,
            keyring_home: Some(rpgp_home.display().to_string()),
        })
        .unwrap();
        Self { temp, gnupg_home, rpgp }
    }

    /// A `SystemGpgBackend` pinned to this context's throwaway `GNUPGHOME`.
    fn system_gpg_backend(&self) -> SystemGpgBackend {
        SystemGpgBackend::from_config(&PgpBackendConfig {
            backend: PgpBackendKind::SystemGpg,
            bundled_gpg_path: None,
            system_gpg_path: Some(gpg_executable()),
            pure_rust_enabled: false,
            keyring_home: Some(self.gnupg_home.display().to_string()),
        })
        .expect("system gpg backend")
    }

    fn generate_rpgp_key(&self) -> String {
        self.rpgp
            .generate_key(KeyGenerationRequest {
                name: "Interop Example".to_string(),
                email: "interop@example.com".to_string(),
                passphrase: None,
            })
            .unwrap()
            .fingerprint
    }

    fn generate_gnupg_key(&self, email: &str, passphrase: Option<&str>) {
        let batch = gpg_key_gen_batch("Interop Example", email, passphrase);
        gpg_with_input(&self.gnupg_home, &["--gen-key"], batch.as_bytes());
    }

    fn gnupg_fingerprint(&self, email: &str) -> String {
        let output = gpg_command(&self.gnupg_home)
            .args(["--batch", "--with-colons", "--fingerprint", email])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "gpg --fingerprint failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8_lossy(&output.stdout)
            .lines()
            .find_map(|line| {
                line.strip_prefix("fpr:").map(|rest| rest.trim_matches(':').to_string())
            })
            .expect("fingerprint in gpg listing")
    }

    /// Exports key material from GnuPG in the requested encoding.
    fn gnupg_export(
        &self,
        fingerprint: &str,
        private: bool,
        armored: bool,
        passphrase: Option<&str>,
    ) -> Vec<u8> {
        let mut command = gpg_command(&self.gnupg_home);
        command.args(["--batch", "--yes", "--pinentry-mode", "loopback"]);
        if armored {
            command.arg("--armor");
        }
        if let Some(passphrase) = passphrase {
            command.args(["--passphrase", passphrase]);
        }
        command.arg(if private { "--export-secret-keys" } else { "--export" }).arg(fingerprint);

        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "gpg export failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!output.stdout.is_empty(), "gpg export produced no material");
        output.stdout
    }

    fn gnupg_export_sha1(
        &self,
        fingerprint: &str,
        passphrase: &str,
        decoded_count: usize,
    ) -> Vec<u8> {
        let output = gpg_command(&self.gnupg_home)
            .args([
                "--batch",
                "--yes",
                "--pinentry-mode",
                "loopback",
                "--armor",
                "--passphrase",
                passphrase,
                "--s2k-mode",
                "3",
                "--s2k-digest-algo",
                "SHA1",
                "--s2k-cipher-algo",
                "AES256",
                "--s2k-count",
                &decoded_count.to_string(),
                "--export-secret-keys",
                fingerprint,
            ])
            .output()
            .expect("export legacy GnuPG private key");
        assert!(
            output.status.success(),
            "GnuPG legacy export failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!output.stdout.is_empty(), "GnuPG legacy export was empty");
        output.stdout
    }

    fn import_public_key_to_gnupg(&self, fingerprint: &str) {
        let public_key = self.rpgp.export_public_key(fingerprint).unwrap();
        gpg_with_input(&self.gnupg_home, &["--import"], public_key.armored_text.as_bytes());
    }

    fn import_private_key_to_gnupg(&self, fingerprint: &str) {
        let private_key = self.rpgp.export_private_key(fingerprint, None).unwrap();
        gpg_with_input(&self.gnupg_home, &["--import"], private_key.armored_text.as_bytes());
    }

    fn import_armored_private_to_gnupg(&self, armored_text: &str) {
        gpg_with_input(&self.gnupg_home, &["--import"], armored_text.as_bytes());
    }
}

fn decode_s2k_count(coded_count: u8) -> usize {
    (16usize + usize::from(coded_count & 15)) << (usize::from(coded_count >> 4) + 6)
}

fn all_protected_packets_match(
    key: &pgp::composed::SignedSecretKey,
    predicate: impl Fn(&S2kParams) -> bool,
) -> bool {
    let matches = |params: &SecretParams| match params {
        SecretParams::Encrypted(encrypted) => predicate(encrypted.string_to_key_params()),
        SecretParams::Plain(_) => true,
    };
    matches(key.primary_key.secret_params())
        && key.secret_subkeys.iter().all(|subkey| matches(subkey.key.secret_params()))
}

fn protected_packet_profiles(key: &pgp::composed::SignedSecretKey) -> Vec<String> {
    std::iter::once(key.primary_key.secret_params())
        .chain(key.secret_subkeys.iter().map(|subkey| subkey.key.secret_params()))
        .map(|params| match params {
            SecretParams::Encrypted(encrypted) => match encrypted.string_to_key_params() {
                S2kParams::Cfb { sym_alg, s2k, .. }
                | S2kParams::MalleableCfb { sym_alg, s2k, .. } => match s2k {
                    StringToKey::IteratedAndSalted { hash_alg, count, .. } => {
                        format!("{sym_alg:?}/{hash_alg:?}/{count}")
                    }
                    other => format!("{sym_alg:?}/{other:?}"),
                },
                other => format!("{other:?}"),
            },
            SecretParams::Plain(_) => "unprotected".to_string(),
        })
        .collect()
}

fn run_interop_tests() -> bool {
    if std::env::var("PARS_RUN_GPG_INTEROP").as_deref() == Ok("1") {
        return true;
    }
    eprintln!("skipping GnuPG interoperability test; set PARS_RUN_GPG_INTEROP=1 to run");
    false
}

fn gpg_with_input(gnupg_home: &Path, args: &[&str], input: &[u8]) {
    let mut child = gpg_command(gnupg_home)
        .args(["--batch", "--yes", "--pinentry-mode", "loopback"])
        .args(args)
        .stdin(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "gpg command failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn gpg_command(gnupg_home: &Path) -> Command {
    let mut command = Command::new(gpg_executable());
    command.env("GNUPGHOME", gnupg_home);
    command
}

fn gpg_executable() -> String {
    std::env::var("PARS_GPG").unwrap_or_else(|_| "gpg".to_string())
}

#[cfg(unix)]
fn lock_down_dir(path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = std::fs::metadata(path).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(path, permissions).unwrap();
}

#[cfg(not(unix))]
fn lock_down_dir(_path: &Path) {}
