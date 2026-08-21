use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use pars_core::autofill::{
    clear_autofill_index, clear_autofill_index_websites,
    enrich_autofill_index_websites_with_backend, move_autofill_index_entry,
    patch_autofill_index_ranking, query_autofill_candidates, read_autofill_index,
    rebuild_autofill_index, reconcile_autofill_index, remove_autofill_index_entry,
    resolve_autofill_credential_with_backend, upsert_autofill_index_entry,
    AutofillCredentialRequest, AutofillEntryMetadata, AutofillQueryRequest,
    ClearAutofillIndexWebsitesRequest, EnrichAutofillIndexWebsitesRequest,
    MoveAutofillIndexEntryRequest, PatchAutofillIndexRankingRequest, RebuildAutofillIndexRequest,
    ReconcileAutofillIndexRequest, RemoveAutofillIndexEntryRequest,
    UpsertAutofillIndexEntryRequest,
};
use pars_core::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
use pars_core::pgp::backend::{
    KeyGenerationRequest, PgpBackend, PgpBackendError, PgpBackendResult, PgpKeyDeletionResult,
    PgpKeyDetails,
};
use pars_core::pgp::import::InspectedPgpKey;
use secrecy::SecretString;

#[test]
fn rebuild_derives_path_metadata_without_a_backend() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    write_entry(&root, "github.com/alice");
    write_entry(&root, "Work/GitLab/Älice");
    write_entry(&root, "root-user");
    let index_path = temp.path().join("shared/autofill.json");

    let index = rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path,
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root,
        entries: vec![metadata("github.com/alice", true, Some(0))],
    })
    .expect("rebuild");

    let github = entry(&index, "github.com/alice");
    assert_eq!(github.service_name.as_deref(), Some("github.com"));
    assert_eq!(github.username, "alice");
    assert_eq!(github.display_name, "github.com");
    assert_eq!(github.path_website.as_deref(), Some("github.com"));
    assert!(github.is_favorite);

    let nested = entry(&index, "Work/GitLab/Älice");
    assert_eq!(nested.service_name.as_deref(), Some("GitLab"));
    assert_eq!(nested.username, "Älice");
    assert_eq!(nested.path_website, None);

    let root_entry = entry(&index, "root-user");
    assert_eq!(root_entry.service_name, None);
    assert_eq!(root_entry.username, "root-user");
    assert_eq!(root_entry.display_name, "root-user");
    assert_eq!(root_entry.path_website, None);
}

#[test]
fn replacement_schema_is_strict_and_atomic_writes_remain_readable() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    write_entry(&root, "example.com/alice");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root,
        entries: vec![],
    })
    .expect("rebuild");

    let running = Arc::new(AtomicBool::new(true));
    let reader_running = Arc::clone(&running);
    let reader_path = index_path.clone();
    let reader = std::thread::spawn(move || {
        while reader_running.load(Ordering::Acquire) {
            read_autofill_index(&reader_path).expect("atomic reader never sees partial JSON");
        }
    });
    for rank in 0..50 {
        patch_autofill_index_ranking(PatchAutofillIndexRankingRequest {
            index_path: index_path.clone(),
            entries: vec![metadata("example.com/alice", rank % 2 == 0, Some(rank))],
        })
        .expect("ranking patch");
    }
    running.store(false, Ordering::Release);
    reader.join().expect("reader thread");

    std::fs::write(
        &index_path,
        r#"{
          "version": 1,
          "store_id": "old",
          "store_name": "Old",
          "store_root": "/tmp",
          "generated_at_epoch_seconds": 0,
          "entries": [{
            "path": "old/alice",
            "display_name": "Old",
            "username": "alice",
            "websites": [],
            "android_packages": [],
            "is_favorite": false,
            "recent_rank": null,
            "updated_at_epoch_seconds": 0
          }]
        }"#,
    )
    .expect("old index");
    assert!(read_autofill_index(&index_path).is_err());
}

#[test]
fn incremental_operations_preserve_aliases_and_leave_unrelated_entries_unchanged() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let alice_path = write_entry(&root, "github.com/alice");
    write_entry(&root, "mail.example.com/bob");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root.clone(),
        entries: vec![metadata("github.com/alice", true, Some(1))],
    })
    .expect("rebuild");
    let backend = RecordingBackend::with_entries([(
        alice_path,
        "secret\nurl: https://accounts.example.com/login",
    )]);
    enrich_autofill_index_websites_with_backend(
        EnrichAutofillIndexWebsitesRequest {
            index_path: index_path.clone(),
            store_root: root,
            pgp_executable: String::new(),
            passphrase: None,
            paths: vec!["github.com/alice".to_string()],
        },
        &backend,
    )
    .expect("enrich");
    let before = read_autofill_index(&index_path).expect("index");
    let bob_before = entry(&before, "mail.example.com/bob").clone();

    move_autofill_index_entry(MoveAutofillIndexEntryRequest {
        index_path: index_path.clone(),
        old_path: "github.com/alice".to_string(),
        new_path: "GitHub/alice-work".to_string(),
        recursive: false,
    })
    .expect("move");
    let moved = read_autofill_index(&index_path).expect("index");
    let alice = entry(&moved, "GitHub/alice-work");
    assert_eq!(alice.username, "alice-work");
    assert_eq!(alice.service_name.as_deref(), Some("GitHub"));
    assert_eq!(alice.enriched_websites, vec!["accounts.example.com"]);
    assert!(alice.is_favorite);
    assert_eq!(alice.recent_rank, Some(1));
    assert_eq!(entry(&moved, "mail.example.com/bob"), &bob_before);

    remove_autofill_index_entry(RemoveAutofillIndexEntryRequest {
        index_path: index_path.clone(),
        path: "GitHub".to_string(),
        recursive: true,
    })
    .expect("remove prefix");
    let removed = read_autofill_index(&index_path).expect("index");
    assert!(removed.entries.iter().all(|entry| entry.path != "GitHub/alice-work"));
    assert!(removed.entries.iter().any(|entry| entry.path == "mail.example.com/bob"));

    upsert_autofill_index_entry(UpsertAutofillIndexEntryRequest {
        index_path: index_path.clone(),
        entry: metadata("gitlab.com/carol", false, Some(2)),
    })
    .expect("upsert");
    let upserted = read_autofill_index(&index_path).expect("index");
    assert_eq!(entry(&upserted, "gitlab.com/carol").username, "carol");

    let absent = temp.path().join("absent.json");
    assert!(upsert_autofill_index_entry(UpsertAutofillIndexEntryRequest {
        index_path: absent.clone(),
        entry: metadata("example.com/nobody", false, None),
    })
    .expect("uninitialized no-op")
    .is_none());
    assert!(!absent.exists());
}

#[test]
fn reconciliation_updates_only_path_metadata_and_preserves_enrichment() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let alice = write_entry(&root, "example.com/alice");
    write_entry(&root, "old.example.com/bob");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root.clone(),
        entries: vec![metadata("example.com/alice", false, Some(4))],
    })
    .expect("rebuild");
    let backend = RecordingBackend::with_entries([(
        alice,
        "secret\nwebsite: https://login.example.net/path",
    )]);
    enrich_autofill_index_websites_with_backend(
        EnrichAutofillIndexWebsitesRequest {
            index_path: index_path.clone(),
            store_root: root.clone(),
            pgp_executable: String::new(),
            passphrase: None,
            paths: vec!["example.com/alice".to_string()],
        },
        &backend,
    )
    .expect("enrich");
    backend.take_calls();

    std::fs::remove_file(root.join("old.example.com/bob.gpg")).expect("remove old");
    write_entry(&root, "new.example.com/carol");
    reconcile_autofill_index(ReconcileAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root,
        entries: vec![metadata("example.com/alice", true, None)],
    })
    .expect("reconcile");

    assert!(backend.take_calls().is_empty());
    let index = read_autofill_index(&index_path).expect("index");
    assert_eq!(entry(&index, "example.com/alice").enriched_websites, vec!["login.example.net"]);
    assert!(entry(&index, "example.com/alice").is_favorite);
    assert_eq!(entry(&index, "example.com/alice").recent_rank, None);
    assert!(index.entries.iter().any(|entry| entry.path == "new.example.com/carol"));
    assert!(index.entries.iter().all(|entry| entry.path != "old.example.com/bob"));
}

#[test]
fn reconciliation_rejects_replacement_store_and_removes_stale_enrichment() {
    let temp = tempfile::tempdir().expect("tempdir");
    let old_root = temp.path().join("old-store");
    let old_entry = write_entry(&old_root, "example.com/alice");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "canonical-store".to_string(),
        store_name: "Old".to_string(),
        store_root: old_root.clone(),
        entries: vec![metadata("example.com/alice", true, Some(0))],
    })
    .expect("rebuild old store");
    let backend = RecordingBackend::with_entries([(
        old_entry,
        "secret\nwebsite: https://old-alias.example.net/login",
    )]);
    enrich_autofill_index_websites_with_backend(
        EnrichAutofillIndexWebsitesRequest {
            index_path: index_path.clone(),
            store_root: old_root,
            pgp_executable: String::new(),
            passphrase: None,
            paths: vec!["example.com/alice".to_string()],
        },
        &backend,
    )
    .expect("enrich old store");

    let replacement_root = temp.path().join("replacement-store");
    write_entry(&replacement_root, "example.com/alice");
    let error = reconcile_autofill_index(ReconcileAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "canonical-store".to_string(),
        store_name: "Replacement".to_string(),
        store_root: replacement_root,
        entries: vec![metadata("example.com/alice", false, None)],
    })
    .expect_err("replacement must require rebuild");

    assert!(error.to_string().contains("rebuild required"));
    assert!(!index_path.exists(), "stale index must be removed");
}

#[test]
fn matching_prefers_path_website_app_name_and_enriched_alias_over_fallback() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let path = write_entry(&root, "example.com/alice");
    write_entry(&root, "GitHub/bob");
    write_entry(&root, "fallback/carol");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root.clone(),
        entries: vec![metadata("fallback/carol", true, Some(0))],
    })
    .expect("rebuild");
    let backend =
        RecordingBackend::with_entries([(path, "secret\nurl: https://accounts.example.net/login")]);
    enrich_autofill_index_websites_with_backend(
        EnrichAutofillIndexWebsitesRequest {
            index_path: index_path.clone(),
            store_root: root,
            pgp_executable: String::new(),
            passphrase: None,
            paths: vec!["example.com/alice".to_string()],
        },
        &backend,
    )
    .expect("enrich");

    let website = query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.clone(),
        website: Some("https://www.example.com/login".to_string()),
        app_name: None,
        query: None,
        limit: 10,
    })
    .expect("website");
    assert_eq!(website[0].match_kind, "path_website");

    let app = query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.clone(),
        website: None,
        app_name: Some("  github  ".to_string()),
        query: None,
        limit: 10,
    })
    .expect("app");
    assert_eq!(app[0].path, "GitHub/bob");
    assert_eq!(app[0].match_kind, "app_name");

    let enriched = query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.clone(),
        website: Some("accounts.example.net".to_string()),
        app_name: None,
        query: None,
        limit: 10,
    })
    .expect("enriched");
    assert_eq!(enriched[0].match_kind, "enriched_website");

    let fallback = query_autofill_candidates(AutofillQueryRequest {
        index_path,
        website: None,
        app_name: None,
        query: Some("carol".to_string()),
        limit: 10,
    })
    .expect("fallback");
    assert_eq!(fallback[0].match_kind, "fallback");
    assert!(enriched[0].score > fallback[0].score);
}

#[test]
fn credential_lookup_decrypts_only_selected_entry_and_uses_path_username() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let alice_path = write_entry(&root, "example.com/alice");
    let bob_path = write_entry(&root, "example.com/bob");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root.clone(),
        entries: vec![],
    })
    .expect("rebuild");
    let backend = RecordingBackend::with_entries([
        (alice_path, "alice-password\nusername: mallory"),
        (bob_path.clone(), "bob-password\nusername: robert"),
    ]);
    let before = std::fs::read(&index_path).expect("before");

    let credential = resolve_autofill_credential_with_backend(
        AutofillCredentialRequest {
            index_path: index_path.clone(),
            store_root: root,
            path: "example.com/bob".to_string(),
            pgp_executable: String::new(),
            passphrase: None,
        },
        &backend,
    )
    .expect("credential");

    assert_eq!(credential.username, "bob");
    assert_eq!(credential.password, "bob-password");
    assert_eq!(backend.take_calls(), vec![bob_path]);
    assert_eq!(std::fs::read(index_path).expect("after"), before);
}

#[test]
fn enrichment_is_selected_only_transactional_and_clearable_without_decryption() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = temp.path().join("store");
    let alice = write_entry(&root, "example.com/alice");
    let bob = write_entry(&root, "example.com/bob");
    let index_path = temp.path().join("autofill.json");
    rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.clone(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        store_root: root.clone(),
        entries: vec![],
    })
    .expect("rebuild");

    let selected_backend = RecordingBackend::with_entries([(
        alice.clone(),
        "secret\nurl: https://www.example.net/path\nservice: login.example.org",
    )]);
    enrich_autofill_index_websites_with_backend(
        EnrichAutofillIndexWebsitesRequest {
            index_path: index_path.clone(),
            store_root: root.clone(),
            pgp_executable: String::new(),
            passphrase: None,
            paths: vec!["example.com/alice".to_string()],
        },
        &selected_backend,
    )
    .expect("selected enrichment");
    assert_eq!(selected_backend.take_calls(), vec![alice]);
    assert_eq!(
        entry(&read_autofill_index(&index_path).expect("index"), "example.com/alice")
            .enriched_websites,
        vec!["example.net", "login.example.org"]
    );

    let before_failure = std::fs::read(&index_path).expect("before failure");
    let failing_backend = RecordingBackend::with_entries([(bob, "secret\nurl: bob.example.net")]);
    let failure = enrich_autofill_index_websites_with_backend(
        EnrichAutofillIndexWebsitesRequest {
            index_path: index_path.clone(),
            store_root: root,
            pgp_executable: String::new(),
            passphrase: None,
            paths: vec!["example.com/bob".to_string(), "example.com/alice".to_string()],
        },
        &failing_backend,
    );
    assert!(failure.is_err());
    assert_eq!(std::fs::read(&index_path).expect("after failure"), before_failure);

    clear_autofill_index_websites(ClearAutofillIndexWebsitesRequest {
        index_path: index_path.clone(),
        paths: vec![],
    })
    .expect("clear aliases");
    assert!(read_autofill_index(&index_path)
        .expect("index")
        .entries
        .iter()
        .all(|entry| entry.enriched_websites.is_empty()));
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

fn write_entry(root: &Path, logical_path: &str) -> PathBuf {
    let encrypted_path = root.join(format!("{logical_path}.gpg"));
    std::fs::create_dir_all(encrypted_path.parent().expect("entry parent")).expect("mkdir");
    std::fs::write(&encrypted_path, "encrypted").expect("entry");
    encrypted_path
}

fn metadata(path: &str, is_favorite: bool, recent_rank: Option<u32>) -> AutofillEntryMetadata {
    AutofillEntryMetadata { path: path.to_string(), is_favorite, recent_rank }
}

fn entry<'a>(
    index: &'a pars_core::autofill::AutofillIndex,
    path: &str,
) -> &'a pars_core::autofill::AutofillIndexEntry {
    index.entries.iter().find(|entry| entry.path == path).expect("indexed entry")
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
        self.entries.get(encrypted_path).cloned().map(SecretString::from).ok_or_else(|| {
            PgpBackendError::CommandFailed(format!(
                "missing test ciphertext: {}",
                encrypted_path.display()
            ))
        })
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

    fn import_key(&self, _key: &InspectedPgpKey) -> PgpBackendResult<KeyImportResult> {
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

    fn delete_key(&self, _fingerprint: &str) -> PgpBackendResult<PgpKeyDeletionResult> {
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
