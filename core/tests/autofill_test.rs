use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use pars_core::autofill::{
    clear_autofill_index, query_autofill_candidates, refresh_autofill_index_with_backend,
    resolve_autofill_credential_with_backend, AutofillCredentialRequest, AutofillEntryMetadata,
    AutofillQueryRequest, RefreshAutofillIndexRequest,
};
use pars_core::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
use pars_core::pgp::backend::{KeyGenerationRequest, PgpBackend, PgpBackendResult, PgpKeyDetails};
use secrecy::SecretString;

#[test]
fn refreshed_autofill_index_omits_passwords_and_matches_service_ids() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let work = root.join("work");
    std::fs::create_dir_all(&work).expect("store");
    let encrypted_path = work.join("github.gpg");
    std::fs::write(&encrypted_path, "encrypted").expect("entry");

    let backend = RecordingBackend::with_entries([(
        encrypted_path.clone(),
        "super-secret\nusername: alice\nurl: https://www.Example.com/login\nandroid-package: com.example.app",
    )]);
    let index_path = temp.path().join("shared").join("autofill.json");

    let index = refresh_autofill_index_with_backend(
        RefreshAutofillIndexRequest {
            index_path: index_path.clone(),
            store_id: "personal".to_string(),
            store_name: "Personal".to_string(),
            store_root: root.clone(),
            pgp_executable: String::new(),
            passphrase: None,
            entries: vec![AutofillEntryMetadata {
                path: "work/github".to_string(),
                display_name: Some("GitHub".to_string()),
                is_favorite: true,
                recent_rank: Some(0),
            }],
        },
        &backend,
    )
    .expect("refresh");

    assert_eq!(index.entries.len(), 1);
    assert_eq!(index.entries[0].username.as_deref(), Some("alice"));
    assert_eq!(index.entries[0].websites, vec!["example.com"]);
    assert_eq!(index.entries[0].android_packages, vec!["com.example.app"]);

    let raw_index = std::fs::read_to_string(&index_path).expect("index");
    assert!(raw_index.contains("alice"));
    assert!(!raw_index.contains("super-secret"));
    assert!(!raw_index.contains("raw_notes"));

    let website = query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.clone(),
        website: Some("https://example.com/account".to_string()),
        android_package: None,
        query: None,
        limit: 10,
    })
    .expect("website query");
    assert_eq!(website[0].path, "work/github");
    assert_eq!(website[0].match_kind, "website");

    let package = query_autofill_candidates(AutofillQueryRequest {
        index_path,
        website: None,
        android_package: Some("com.example.app".to_string()),
        query: None,
        limit: 10,
    })
    .expect("package query");
    assert_eq!(package[0].path, "work/github");
    assert_eq!(package[0].match_kind, "android_package");
    assert!(package[0].score > website[0].score);
}

#[test]
fn android_package_matching_requires_explicit_package_fields() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let bank = root.join("bank");
    std::fs::create_dir_all(&bank).expect("store");
    let encrypted_path = bank.join("chase.gpg");
    std::fs::write(&encrypted_path, "encrypted").expect("entry");

    let backend = RecordingBackend::with_entries([(encrypted_path, "secret\nusername: saver")]);
    let index_path = temp.path().join("autofill.json");
    refresh_autofill_index_with_backend(
        RefreshAutofillIndexRequest {
            index_path: index_path.clone(),
            store_id: "personal".to_string(),
            store_name: "Personal".to_string(),
            store_root: root,
            pgp_executable: String::new(),
            passphrase: None,
            entries: vec![],
        },
        &backend,
    )
    .expect("refresh");

    let exact_package = query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.clone(),
        website: None,
        android_package: Some("com.example.bank".to_string()),
        query: None,
        limit: 10,
    })
    .expect("package query");
    assert!(exact_package.is_empty());

    let fallback = query_autofill_candidates(AutofillQueryRequest {
        index_path,
        website: None,
        android_package: None,
        query: Some("bank".to_string()),
        limit: 10,
    })
    .expect("fallback query");
    assert_eq!(fallback[0].path, "bank/chase");
    assert_eq!(fallback[0].match_kind, "fallback");
}

#[test]
fn credential_lookup_decrypts_only_the_selected_index_entry() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let work = root.join("work");
    std::fs::create_dir_all(&work).expect("store");
    let github_path = work.join("github.gpg");
    let email_path = work.join("mail.gpg");
    std::fs::write(&github_path, "encrypted").expect("github");
    std::fs::write(&email_path, "encrypted").expect("mail");

    let backend = RecordingBackend::with_entries([
        (github_path.clone(), "github-password\nusername: alice\nurl: github.com"),
        (email_path.clone(), "mail-password\nusername: bob\nurl: mail.example.com"),
    ]);
    let index_path = temp.path().join("autofill.json");
    refresh_autofill_index_with_backend(
        RefreshAutofillIndexRequest {
            index_path: index_path.clone(),
            store_id: "personal".to_string(),
            store_name: "Personal".to_string(),
            store_root: root.clone(),
            pgp_executable: String::new(),
            passphrase: None,
            entries: vec![],
        },
        &backend,
    )
    .expect("refresh");
    backend.take_calls();

    let credential = resolve_autofill_credential_with_backend(
        AutofillCredentialRequest {
            index_path,
            store_root: root,
            path: "work/mail".to_string(),
            pgp_executable: String::new(),
            passphrase: None,
        },
        &backend,
    )
    .expect("credential");

    assert_eq!(credential.username.as_deref(), Some("bob"));
    assert_eq!(credential.password, "mail-password");
    assert_eq!(backend.take_calls(), vec![email_path]);
}

#[test]
fn clear_autofill_index_removes_existing_file_and_ignores_missing_file() {
    let temp = tempfile::tempdir().expect("tempdir");
    let index_path = temp.path().join("autofill.json");
    std::fs::write(&index_path, "{}").expect("index");

    clear_autofill_index(&index_path).expect("clear");
    assert!(!index_path.exists());

    clear_autofill_index(&index_path).expect("clear missing");
}

#[derive(Default)]
struct RecordingBackend {
    entries: BTreeMap<PathBuf, String>,
    calls: RefCell<Vec<PathBuf>>,
}

impl RecordingBackend {
    fn with_entries<const N: usize>(entries: [(PathBuf, &str); N]) -> Self {
        Self {
            entries: entries
                .into_iter()
                .map(|(path, content)| (path, content.to_string()))
                .collect(),
            calls: RefCell::new(Vec::new()),
        }
    }

    fn take_calls(&self) -> Vec<PathBuf> {
        self.calls.take()
    }
}

impl PgpBackend for RecordingBackend {
    fn decrypt_file(
        &self,
        encrypted_path: &Path,
        _passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<SecretString> {
        self.calls.borrow_mut().push(encrypted_path.to_path_buf());
        Ok(SecretString::from(self.entries.get(encrypted_path).expect("encrypted path").clone()))
    }

    fn encrypt_content(
        &self,
        _plaintext: &SecretString,
        _output_path: &Path,
        _recipients: &[String],
    ) -> PgpBackendResult<()> {
        unreachable!("not used by autofill tests")
    }

    fn generate_key(&self, _request: KeyGenerationRequest) -> PgpBackendResult<KeyImportResult> {
        unreachable!("not used by autofill tests")
    }

    fn import_public_key(&self, _armored_text: &str) -> PgpBackendResult<KeyImportResult> {
        unreachable!("not used by autofill tests")
    }

    fn import_private_key(
        &self,
        _armored_text: &SecretString,
    ) -> PgpBackendResult<KeyImportResult> {
        unreachable!("not used by autofill tests")
    }

    fn export_public_key(&self, _fingerprint: &str) -> PgpBackendResult<KeyExportResult> {
        unreachable!("not used by autofill tests")
    }

    fn export_private_key(
        &self,
        _fingerprint: &str,
        _passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<KeyExportResult> {
        unreachable!("not used by autofill tests")
    }

    fn delete_key(&self, _fingerprint: &str) -> PgpBackendResult<()> {
        unreachable!("not used by autofill tests")
    }

    fn list_keys(&self) -> PgpBackendResult<Vec<PgpKeySummary>> {
        unreachable!("not used by autofill tests")
    }

    fn inspect_fingerprint(&self, _identity: &str) -> PgpBackendResult<PgpKeyDetails> {
        unreachable!("not used by autofill tests")
    }

    fn validate_gpg_id(
        &self,
        _store_root: &Path,
        _target_path: &Path,
    ) -> PgpBackendResult<Vec<String>> {
        unreachable!("not used by autofill tests")
    }
}
