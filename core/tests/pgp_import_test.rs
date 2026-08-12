use std::path::Path;

use pars_core::config::cli::PgpBackendKind;
use pars_core::pgp::backend::{PgpBackend, PgpBackendConfig};
use pars_core::pgp::import::{
    import_pgp_key_file, import_pgp_key_text, inspect_pgp_key_bytes, inspect_pgp_key_file,
    PgpImportError, PgpKeyMaterialKind,
};
use pars_core::pgp::rpgp_backend::RpgpBackend;
use pars_core::util::test_util::PgpKeyMaterialFixture;
use secrecy::SecretString;
use tempfile::TempDir;

const PASSPHRASE: &str = "fixture passphrase";

struct PureRustBackend {
    _keyring: TempDir,
    backend: RpgpBackend,
}

impl PureRustBackend {
    fn new() -> Self {
        let keyring = tempfile::tempdir().expect("keyring");
        let backend = RpgpBackend::from_config(&PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            keyring_home: Some(keyring.path().display().to_string()),
            ..Default::default()
        })
        .expect("backend");
        Self { _keyring: keyring, backend }
    }

    fn as_dyn(&self) -> &dyn PgpBackend {
        &self.backend
    }

    fn fingerprints(&self) -> Vec<String> {
        self.backend
            .list_keys()
            .expect("list keys")
            .into_iter()
            .map(|key| key.fingerprint)
            .collect()
    }
}

#[test]
fn inspection_reports_the_same_identity_for_every_supported_encoding() {
    let fixture = PgpKeyMaterialFixture::generate(Some(PASSPHRASE));
    let temp = tempfile::tempdir().expect("tempdir");

    for (label, material, kind, armored) in [
        ("armored public", &fixture.armored_public, PgpKeyMaterialKind::Public, true),
        ("binary public", &fixture.binary_public, PgpKeyMaterialKind::Public, false),
        ("armored private", &fixture.armored_private, PgpKeyMaterialKind::Private, true),
        ("binary private", &fixture.binary_private, PgpKeyMaterialKind::Private, false),
    ] {
        // Same material, once through bytes and once through a file: the source must not change
        // what is detected.
        let from_bytes = inspect_pgp_key_bytes(material.clone()).expect(label);
        let path = temp.path().join("key-material");
        fixture.write_to(&path, material);
        let from_file = inspect_pgp_key_file(&path).expect(label);

        for inspected in [&from_bytes, &from_file] {
            let inspection = inspected.inspection();
            assert_eq!(inspection.kind, kind, "{label}");
            assert_eq!(inspection.armored, armored, "{label}");
            assert_eq!(inspection.fingerprint, fixture.fingerprint, "{label}");
            assert_eq!(inspection.identity, fixture.identity, "{label}");
        }
    }
}

#[test]
fn pure_rust_import_returns_canonical_fingerprint_for_every_encoding() {
    let fixture = PgpKeyMaterialFixture::generate(None);
    let temp = tempfile::tempdir().expect("tempdir");

    for (label, material) in [
        ("armored public", &fixture.armored_public),
        ("binary public", &fixture.binary_public),
        ("armored private", &fixture.armored_private),
        // Binary private material is the case the old `read_to_string` path could not handle.
        ("binary private", &fixture.binary_private),
    ] {
        let backend = PureRustBackend::new();
        let path = temp.path().join("key-material");
        fixture.write_to(&path, material);

        let outcome =
            import_pgp_key_file(backend.as_dyn(), &path, None, None).unwrap_or_else(|error| {
                panic!("{label} should import: {error}");
            });
        assert_eq!(outcome.fingerprint, fixture.fingerprint, "{label}");
        // Metadata comes back from the backend, not from the submitted material.
        assert_eq!(outcome.identity, fixture.identity, "{label}");
        assert_ne!(outcome.identity, outcome.fingerprint, "{label}");
        assert_eq!(backend.fingerprints(), vec![fixture.fingerprint.clone()], "{label}");
    }
}

#[test]
fn pure_rust_duplicate_import_returns_the_same_fingerprint() {
    let fixture = PgpKeyMaterialFixture::generate(None);
    let backend = PureRustBackend::new();

    let first = import_pgp_key_text(backend.as_dyn(), fixture.armored_public_text(), None, None)
        .expect("first import");
    let second = import_pgp_key_text(backend.as_dyn(), fixture.armored_public_text(), None, None)
        .expect("re-import of an existing key");

    assert_eq!(first.fingerprint, fixture.fingerprint);
    assert_eq!(second.fingerprint, first.fingerprint);
    assert_eq!(backend.fingerprints(), vec![fixture.fingerprint]);
}

#[test]
fn pure_rust_import_of_protected_key_requires_the_correct_passphrase() {
    let fixture = PgpKeyMaterialFixture::generate(Some(PASSPHRASE));
    let backend = PureRustBackend::new();

    let outcome = import_pgp_key_text(
        backend.as_dyn(),
        fixture.armored_private_text(),
        Some(&SecretString::from(PASSPHRASE)),
        None,
    )
    .expect("correct passphrase should import");

    assert_eq!(outcome.fingerprint, fixture.fingerprint);
    assert!(outcome.imported_private_key);
    assert!(outcome.inspection.requires_passphrase);
}

#[test]
fn pure_rust_import_leaves_no_key_when_the_passphrase_is_absent_or_wrong() {
    let fixture = PgpKeyMaterialFixture::generate(Some(PASSPHRASE));

    for (label, passphrase, expected) in [
        ("absent", None, PgpImportError::PassphraseRequired),
        ("empty", Some(SecretString::from("")), PgpImportError::PassphraseRequired),
        ("wrong", Some(SecretString::from("not it")), PgpImportError::IncorrectPassphrase),
    ] {
        let backend = PureRustBackend::new();
        let error = import_pgp_key_text(
            backend.as_dyn(),
            fixture.armored_private_text(),
            passphrase.as_ref(),
            None,
        )
        .expect_err("import should be rejected");

        assert_eq!(error, expected, "{label} passphrase");
        // The point of validating first: a typo must not leave a key behind.
        assert!(backend.fingerprints().is_empty(), "{label} passphrase mutated the keyring");
        let message = error.to_string();
        assert!(!message.contains(PASSPHRASE), "{label}: leaked passphrase");
        assert!(!message.contains("PRIVATE KEY"), "{label}: leaked key material");
    }
}

#[test]
fn pure_rust_import_rejects_material_of_the_wrong_kind() {
    let fixture = PgpKeyMaterialFixture::generate(None);
    let backend = PureRustBackend::new();

    let error = import_pgp_key_text(
        backend.as_dyn(),
        fixture.armored_public_text(),
        None,
        Some(PgpKeyMaterialKind::Private),
    )
    .expect_err("public material must not satisfy a private import");

    assert_eq!(
        error,
        PgpImportError::KindMismatch {
            expected: PgpKeyMaterialKind::Private,
            detected: PgpKeyMaterialKind::Public,
        }
    );
    assert!(backend.fingerprints().is_empty());
}

#[test]
fn import_reports_unsupported_material_before_touching_the_keyring() {
    let backend = PureRustBackend::new();

    let error = import_pgp_key_text(backend.as_dyn(), "not a key".to_string(), None, None)
        .expect_err("unparseable material should fail");
    assert!(matches!(error, PgpImportError::UnsupportedMaterial(_)), "{error:?}");

    let missing =
        import_pgp_key_file(backend.as_dyn(), Path::new("/nonexistent/key.asc"), None, None)
            .expect_err("missing file should fail");
    assert!(matches!(missing, PgpImportError::UnsupportedMaterial(_)), "{missing:?}");

    assert!(backend.fingerprints().is_empty());
}

#[test]
fn generated_pure_rust_keys_protect_their_encryption_subkey() {
    // A passphrase that only locked the primary key would leave entries decryptable without it,
    // because decryption only ever uses the encryption subkey.
    let protected = PgpKeyMaterialFixture::generate(Some(PASSPHRASE));
    let inspected = inspect_pgp_key_bytes(protected.armored_private.clone()).expect("inspect");
    assert_eq!(inspected.encryption_material_is_protected(), Some(true));
    assert!(inspected.requires_passphrase());

    let unprotected = PgpKeyMaterialFixture::generate(None);
    let inspected = inspect_pgp_key_bytes(unprotected.armored_private.clone()).expect("inspect");
    assert_eq!(inspected.encryption_material_is_protected(), Some(false));
    assert!(!inspected.requires_passphrase());

    // Public material has no private packets to protect.
    let public = inspect_pgp_key_bytes(protected.armored_public.clone()).expect("inspect");
    assert_eq!(public.encryption_material_is_protected(), None);
}
