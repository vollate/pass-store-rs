use std::path::Path;

use pars_core::config::cli::{ParsConfig, PgpBackendKind};
use pars_core::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
use pars_core::pgp::backend::{
    KeyGenerationRequest, PgpBackend, PgpBackendConfig, PgpBackendError, PgpBackendResult,
    PgpKeyDetails, SystemGpgBackend,
};
use pars_core::pgp::import::{inspect_pgp_key_bytes, InspectedPgpKey};
use pars_core::util::test_util::PgpKeyMaterialFixture;
use secrecy::SecretString;

#[test]
fn config_defaults_to_system_gpg_backend_and_round_trips_selection() {
    let default_config = ParsConfig::default();
    assert_eq!(default_config.pgp_config.backend, PgpBackendKind::SystemGpg);

    let config: ParsConfig = toml::from_str(
        r#"
[pgp_config]
backend = "bundled"
bundled_gpg_path = "/app/bin/gpg"
system_gpg_path = "/usr/local/bin/gpg"
keyring_home = "/tmp/pars-gnupg"
"#,
    )
    .unwrap();

    assert_eq!(config.pgp_config.backend, PgpBackendKind::Bundled);
    assert_eq!(config.pgp_config.bundled_gpg_path.as_deref(), Some("/app/bin/gpg"));
    assert_eq!(config.pgp_config.system_gpg_path.as_deref(), Some("/usr/local/bin/gpg"));
    assert_eq!(config.pgp_config.keyring_home.as_deref(), Some("/tmp/pars-gnupg"));

    let serialized = toml::to_string(&config).unwrap();
    assert!(serialized.contains("backend = \"bundled\""));
}

#[test]
fn system_gpg_backend_config_resolves_executable_from_selected_backend() {
    let bundled = PgpBackendConfig {
        backend: PgpBackendKind::Bundled,
        bundled_gpg_path: Some("/Applications/Pars.app/Contents/Resources/bin/gpg".to_string()),
        system_gpg_path: Some("/usr/bin/gpg".to_string()),
        pure_rust_enabled: false,
        keyring_home: None,
    };
    assert_eq!(
        SystemGpgBackend::from_config(&bundled).unwrap().executable(),
        "/Applications/Pars.app/Contents/Resources/bin/gpg"
    );

    let system = PgpBackendConfig {
        backend: PgpBackendKind::SystemGpg,
        bundled_gpg_path: None,
        system_gpg_path: Some("/opt/homebrew/bin/gpg".to_string()),
        pure_rust_enabled: false,
        keyring_home: None,
    };
    assert_eq!(
        SystemGpgBackend::from_config(&system).unwrap().executable(),
        "/opt/homebrew/bin/gpg"
    );

    let pure_rust = PgpBackendConfig {
        backend: PgpBackendKind::PureRust,
        bundled_gpg_path: None,
        system_gpg_path: None,
        pure_rust_enabled: true,
        keyring_home: None,
    };
    assert!(matches!(
        SystemGpgBackend::from_config(&pure_rust),
        Err(PgpBackendError::UnsupportedBackend(_))
    ));
}

#[test]
fn validate_gpg_id_reads_nearest_store_identity_and_rejects_empty_files() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    std::fs::create_dir_all(root.join("work")).unwrap();
    std::fs::write(root.join(".gpg-id"), "alice@example.com\n# comment\n\n").unwrap();
    std::fs::write(root.join("work/.gpg-id"), "team@example.com\n").unwrap();

    let backend = SystemGpgBackend::new("gpg");
    let recipients = backend.validate_gpg_id(root, &root.join("work/github.gpg")).unwrap();
    assert_eq!(recipients, vec!["team@example.com"]);

    std::fs::write(root.join("work/.gpg-id"), "# comment only\n").unwrap();
    let err = backend.validate_gpg_id(root, &root.join("work/github.gpg")).unwrap_err();
    assert!(matches!(err, PgpBackendError::InvalidGpgId(_)));
}

#[test]
fn pgp_backend_trait_covers_milestone_four_operations() {
    let backend = RecordingBackend::default();

    let _ = backend.decrypt_file(Path::new("entry.gpg"), None);
    let _ = backend.encrypt_content(
        &SecretString::new("secret".into()),
        Path::new("entry.gpg"),
        &["alice@example.com".to_string()],
    );
    let _ = backend.generate_key(KeyGenerationRequest {
        name: "Alice Example".to_string(),
        email: "alice@example.com".to_string(),
        passphrase: None,
    });
    let fixture = PgpKeyMaterialFixture::generate(None);
    let inspected =
        inspect_pgp_key_bytes(fixture.armored_public.clone()).expect("inspect fixture key");
    let _ = backend.import_key(&inspected);
    let _ = backend.export_public_key("ABC123");
    let _ = backend.export_private_key("ABC123", None);
    let _ = backend.delete_key("ABC123");
    let _ = backend.list_keys();
    let _ = backend.inspect_fingerprint("alice@example.com");
    let _ = backend.validate_gpg_id(Path::new("/store"), Path::new("/store/entry.gpg"));
}

#[derive(Default)]
struct RecordingBackend;

impl PgpBackend for RecordingBackend {
    fn decrypt_file(
        &self,
        _encrypted_path: &Path,
        _passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<SecretString> {
        Ok(SecretString::new("secret".into()))
    }

    fn encrypt_content(
        &self,
        _plaintext: &SecretString,
        _output_path: &Path,
        _recipients: &[String],
    ) -> PgpBackendResult<()> {
        Ok(())
    }

    fn generate_key(&self, _request: KeyGenerationRequest) -> PgpBackendResult<KeyImportResult> {
        Ok(KeyImportResult { fingerprint: "ABC123".to_string(), imported_private_key: true })
    }

    fn import_key(&self, _key: &InspectedPgpKey) -> PgpBackendResult<KeyImportResult> {
        Ok(KeyImportResult { fingerprint: "ABC123".to_string(), imported_private_key: true })
    }

    fn export_public_key(&self, _fingerprint: &str) -> PgpBackendResult<KeyExportResult> {
        Ok(KeyExportResult { armored_text: "public".to_string() })
    }

    fn export_private_key(
        &self,
        _fingerprint: &str,
        _passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<KeyExportResult> {
        Ok(KeyExportResult { armored_text: "private".to_string() })
    }

    fn delete_key(&self, _fingerprint: &str) -> PgpBackendResult<()> {
        Ok(())
    }

    fn list_keys(&self) -> PgpBackendResult<Vec<PgpKeySummary>> {
        Ok(vec![PgpKeySummary {
            identity: "alice@example.com".to_string(),
            fingerprint: "ABC123".to_string(),
            has_private_key: true,
        }])
    }

    fn inspect_fingerprint(&self, _identity: &str) -> PgpBackendResult<PgpKeyDetails> {
        Ok(PgpKeyDetails {
            identity: "Alice Example <alice@example.com>".to_string(),
            fingerprint: "ABC123".to_string(),
            has_private_key: true,
            public_key_algorithm: Some("rsa2048".to_string()),
        })
    }

    fn validate_gpg_id(
        &self,
        _store_root: &Path,
        _target_path: &Path,
    ) -> PgpBackendResult<Vec<String>> {
        Ok(vec!["alice@example.com".to_string()])
    }
}
