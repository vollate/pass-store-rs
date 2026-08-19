use std::future::Future;
use std::path::Path;
use std::pin::pin;
use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

use pars_bridge::api::{
    self, AddPgpKeyToGpgIdRequest, AutofillCredentialRequest, AutofillEntryMetadataDto,
    AutofillQueryRequest, ClearAutofillIndexRequest, ConfigurePgpBackendRequest,
    CreateLocalStoreRequest, DeleteLocalStoreRequest, DeletePgpKeyRequest, DeleteSshKeyRequest,
    EntryRequest, ExportPgpKeyRequest, ExportSshKeyRequest, GeneratePgpKeyRequest,
    GenerateSshKeyRequest, ImportKeyTextRequest, ImportPgpKeyFileRequest, ImportPgpKeyTextRequest,
    InsertEntryRequest, InspectAppStateRequest, InspectPgpKeyFileRequest, InspectPgpKeyTextRequest,
    ListEntriesRequest, ListKeysRequest, OpenGithubSshSettingsRequest, PgpImportFailureKind,
    PgpKeyDeletionFailureKind, PgpKeyKindDto, PreparePgpPrivateKeyRequest,
    RebuildAutofillIndexRequest, SUPPORTED_METHODS,
};
use pars_core::util::test_util::PgpKeyMaterialFixture;

const PASSPHRASE: &str = "bridge fixture passphrase";

#[test]
fn rust_bridge_api_exposes_list_entries_future() {
    let temp = tempfile::tempdir().unwrap();
    let request = ListEntriesRequest {
        root: temp.path().display().to_string(),
        target: None,
        recursive: true,
    };

    drop(api::list_entries(request));
}

#[test]
fn bridge_method_table_matches_generated_api_surface() {
    let expected = [
        "load_config",
        "save_config",
        "configure_pgp_backend",
        "list_stores",
        "list_entries",
        "read_entry",
        "copy_entry_password",
        "insert_entry",
        "generate_entry",
        "edit_entry",
        "move_entry",
        "delete_entry",
        "git_status",
        "git_pull",
        "git_push",
        "git_commit",
        "run_git_args",
        "inspect_app_state",
        "select_store",
        "create_local_store",
        "import_local_store",
        "clone_store",
        "remove_store",
        "delete_local_store",
        "list_keys",
        "detect_imported_key",
        "generate_pgp_key",
        "inspect_pgp_key_text",
        "inspect_pgp_key_file",
        "import_pgp_key_text",
        "import_pgp_key_file",
        "import_pgp_public_key",
        "import_pgp_private_key_file",
        "import_pgp_private_key_text",
        "export_pgp_public_key",
        "export_pgp_private_key",
        "prepare_pgp_private_key",
        "delete_pgp_key",
        "add_pgp_key_to_gpg_id",
        "generate_ssh_key",
        "import_ssh_private_key_file",
        "import_ssh_private_key_text",
        "export_ssh_public_key",
        "export_ssh_private_key",
        "delete_ssh_key",
        "open_github_ssh_settings",
        "rebuild_autofill_index",
        "upsert_autofill_index_entry",
        "move_autofill_index_entry",
        "remove_autofill_index_entry",
        "patch_autofill_index_ranking",
        "reconcile_autofill_index",
        "enrich_autofill_index_websites",
        "clear_autofill_index_websites",
        "query_autofill_candidates",
        "resolve_autofill_credential",
        "clear_autofill_index",
    ];

    assert_eq!(SUPPORTED_METHODS, expected);
}

#[test]
fn configure_pgp_backend_writes_pure_rust_config() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let keyring_home = temp.path().join("pgp");

    let response = block_on(api::configure_pgp_backend(ConfigurePgpBackendRequest {
        config_path: config_path.display().to_string(),
        backend: "pure_rust".to_string(),
        keyring_home: Some(keyring_home.display().to_string()),
        pgp_executable: None,
    }));
    assert!(response.error.is_none(), "{:?}", response.error);

    let config_toml = std::fs::read_to_string(config_path).unwrap();
    assert!(config_toml.contains("backend = \"pure_rust\""));
    assert!(config_toml.contains("keyring_home"));
}

#[test]
fn key_management_bridge_lists_generates_exports_and_detects_keys() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let ssh_dir = temp.path().join("ssh");
    let store_root = temp.path().join("store");
    std::fs::create_dir_all(&store_root).unwrap();

    let generated = block_on(api::generate_ssh_key(GenerateSshKeyRequest {
        ssh_dir: ssh_dir.display().to_string(),
        name: "github-mobile".to_string(),
    }));
    assert!(generated.error.is_none(), "{:?}", generated.error);
    assert_eq!(generated.key.unwrap().name, "github-mobile");

    let keys = block_on(api::list_keys(ListKeysRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: Some("/bin/false".to_string()),
        ssh_dir: Some(ssh_dir.display().to_string()),
    }));
    assert!(keys.error.is_none(), "{:?}", keys.error);
    assert!(keys.keys.iter().any(|key| key.key_type == "ssh" && key.name == "github-mobile"));

    let public = block_on(api::export_ssh_public_key(ExportSshKeyRequest {
        ssh_dir: ssh_dir.display().to_string(),
        name: "github-mobile".to_string(),
        confirmation: None,
    }));
    assert!(public.error.is_none(), "{:?}", public.error);
    assert!(public.export.unwrap().armored_text.starts_with("ssh-ed25519 "));

    let private_denied = block_on(api::export_ssh_private_key(ExportSshKeyRequest {
        ssh_dir: ssh_dir.display().to_string(),
        name: "github-mobile".to_string(),
        confirmation: None,
    }));
    assert!(private_denied.error.unwrap().message.contains("confirmation"));

    let deleted = block_on(api::delete_ssh_key(DeleteSshKeyRequest {
        ssh_dir: ssh_dir.display().to_string(),
        name: "github-mobile".to_string(),
    }));
    assert!(deleted.error.is_none(), "{:?}", deleted.error);

    let keys_after_delete = block_on(api::list_keys(ListKeysRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: Some("/bin/false".to_string()),
        ssh_dir: Some(ssh_dir.display().to_string()),
    }));
    assert!(keys_after_delete.error.is_none(), "{:?}", keys_after_delete.error);
    assert!(!keys_after_delete
        .keys
        .iter()
        .any(|key| key.key_type == "ssh" && key.name == "github-mobile"));

    let detected = block_on(api::detect_imported_key(ImportKeyTextRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: Some("/bin/false".to_string()),
        ssh_dir: Some(ssh_dir.display().to_string()),
        name: None,
        armored_text:
            "-----BEGIN PGP PUBLIC KEY BLOCK-----\nabc\n-----END PGP PUBLIC KEY BLOCK-----"
                .to_string(),
    }));
    assert_eq!(detected.kind.as_deref(), Some("pgp_public"));

    let add = block_on(api::add_pgp_key_to_gpg_id(AddPgpKeyToGpgIdRequest {
        root: store_root.display().to_string(),
        fingerprint: "A991D3B4A70291EF".to_string(),
    }));
    assert!(add.error.is_none(), "{:?}", add.error);
    assert_eq!(std::fs::read_to_string(store_root.join(".gpg-id")).unwrap(), "A991D3B4A70291EF\n");

    let github = block_on(api::open_github_ssh_settings(OpenGithubSshSettingsRequest {}));
    assert_eq!(github.url.as_deref(), Some("https://github.com/settings/keys"));
}

#[test]
fn pure_rust_pgp_bridge_generates_lists_and_exports_keys() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let keyring_home = temp.path().join("pgp");
    std::fs::write(
        &config_path,
        format!(
            "[pgp_config]\nbackend = \"pure_rust\"\nkeyring_home = \"{}\"\n",
            toml_path(&keyring_home)
        ),
    )
    .unwrap();

    let generated = block_on(api::generate_pgp_key(GeneratePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        name: "Alice Example".to_string(),
        email: "alice@example.com".to_string(),
        passphrase: Some(PASSPHRASE.to_string()),
    }));
    assert!(generated.error.is_none(), "{:?}", generated.error);
    let generated_key = generated.key.expect("generated key");
    assert_eq!(generated_key.key_type, "pgp");
    assert!(generated_key.has_private_key);

    let keys = block_on(api::list_keys(ListKeysRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        ssh_dir: Some(temp.path().join("ssh").display().to_string()),
    }));
    assert!(keys.error.is_none(), "{:?}", keys.error);
    assert!(keys.keys.iter().any(|key| key.fingerprint == generated_key.fingerprint));
    let listed_key = keys
        .keys
        .iter()
        .find(|key| key.fingerprint == generated_key.fingerprint)
        .expect("generated key should be listed");
    assert_ne!(listed_key.name, generated_key.fingerprint);

    let exported = block_on(api::export_pgp_public_key(ExportPgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
        confirmation: None,
    }));
    assert!(exported.error.is_none(), "{:?}", exported.error);
    assert!(exported.export.unwrap().armored_text.contains("BEGIN PGP PUBLIC KEY BLOCK"));

    let fingerprint_phrase_denied = block_on(api::export_pgp_private_key(ExportPgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
        confirmation: Some(format!("EXPORT PRIVATE KEY {}", generated_key.fingerprint)),
    }));
    let fingerprint_phrase_error =
        fingerprint_phrase_denied.error.expect("fingerprint export phrase should be rejected");
    assert!(
        fingerprint_phrase_error
            .message
            .contains(&format!("EXPORT PRIVATE KEY {}", listed_key.name)),
        "{fingerprint_phrase_error:?}"
    );

    let private_exported = block_on(api::export_pgp_private_key(ExportPgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
        confirmation: Some(format!("EXPORT PRIVATE KEY {}", listed_key.name)),
    }));
    assert!(private_exported.error.is_none(), "{:?}", private_exported.error);
    assert!(private_exported.export.unwrap().armored_text.contains("BEGIN PGP PRIVATE KEY BLOCK"));

    let wrong_preparation = block_on(api::prepare_pgp_private_key(PreparePgpPrivateKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
        passphrase: "wrong passphrase".to_string(),
    }));
    assert_eq!(
        wrong_preparation.error.and_then(|error| error.pgp_import_kind),
        Some(PgpImportFailureKind::IncorrectPassphrase)
    );

    let prepared = block_on(api::prepare_pgp_private_key(PreparePgpPrivateKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
        passphrase: PASSPHRASE.to_string(),
    }));
    assert!(prepared.error.is_none(), "{:?}", prepared.error);
    assert_eq!(prepared.fingerprint.as_deref(), Some(generated_key.fingerprint.as_str()));
    assert!(!prepared.migrated, "a compliant generated key must not be rewritten");

    let deleted = block_on(api::delete_pgp_key(DeletePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
    }));
    assert!(deleted.error.is_none(), "{:?}", deleted.error);
    let deletion = deleted.result.expect("verified deletion result");
    assert!(deletion.had_private_key);
    assert!(deletion.private_key_absent);
    assert!(deletion.public_key_absent);

    let keys_after_delete = block_on(api::list_keys(ListKeysRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        ssh_dir: Some(temp.path().join("ssh").display().to_string()),
    }));
    assert!(keys_after_delete.error.is_none(), "{:?}", keys_after_delete.error);
    assert!(!keys_after_delete.keys.iter().any(|key| key.fingerprint == generated_key.fingerprint));
}

#[test]
fn pure_rust_pgp_bridge_preserves_verified_private_absence_on_public_cleanup_failure() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let keyring_home = temp.path().join("pgp");
    std::fs::write(
        &config_path,
        format!(
            "[pgp_config]\nbackend = \"pure_rust\"\nkeyring_home = \"{}\"\n",
            toml_path(&keyring_home)
        ),
    )
    .unwrap();
    let generated = block_on(api::generate_pgp_key(GeneratePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        name: "Partial Delete".to_string(),
        email: "partial-delete@example.com".to_string(),
        passphrase: Some(PASSPHRASE.to_string()),
    }));
    let fingerprint = generated.key.expect("generated key").fingerprint;
    let public_path = keyring_home.join("public").join(format!("{fingerprint}.asc"));
    std::fs::remove_file(&public_path).expect("replace public record with failure fixture");
    std::fs::create_dir(&public_path).expect("public cleanup failure fixture");

    let response = block_on(api::delete_pgp_key(DeletePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: fingerprint.clone(),
    }));

    assert_eq!(response.failure_kind, Some(PgpKeyDeletionFailureKind::PublicCleanupFailed));
    assert!(response.error.is_some());
    let deletion = response.result.expect("partial result");
    assert!(deletion.had_private_key);
    assert!(deletion.private_key_absent);
    assert!(!deletion.public_key_absent);
    assert!(!keyring_home.join("private").join(format!("{fingerprint}.asc")).exists());
    assert!(public_path.exists());
}

#[test]
fn pure_rust_pgp_bridge_encrypts_and_decrypts_entries() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let keyring_home = temp.path().join("pgp");
    let store_root = temp.path().join("store");
    std::fs::create_dir_all(&store_root).unwrap();
    std::fs::write(
        &config_path,
        format!(
            "[pgp_config]\nbackend = \"pure_rust\"\nkeyring_home = \"{}\"\n",
            toml_path(&keyring_home)
        ),
    )
    .unwrap();

    let generated = block_on(api::generate_pgp_key(GeneratePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        name: "Entry Example".to_string(),
        email: "entry@example.com".to_string(),
        passphrase: None,
    }))
    .key
    .expect("generated key");
    std::fs::write(store_root.join(".gpg-id"), format!("{}\n", generated.fingerprint)).unwrap();

    let inserted = block_on(api::insert_entry(InsertEntryRequest {
        config_path: config_path.display().to_string(),
        root: store_root.display().to_string(),
        path: "example.com/entry".to_string(),
        content: "entry-secret\nusername: hidden-name\nurl: https://ignored.example/login"
            .to_string(),
        overwrite: false,
        pgp_executable: String::new(),
    }));
    assert!(inserted.error.is_none(), "{:?}", inserted.error);

    let read = block_on(api::read_entry(EntryRequest {
        config_path: config_path.display().to_string(),
        root: store_root.display().to_string(),
        path: "example.com/entry".to_string(),
        pgp_executable: None,
        passphrase: None,
    }));
    assert!(read.error.is_none(), "{:?}", read.error);
    let secret = read.secret.expect("secret");
    assert_eq!(secret.password, "entry-secret");
    assert_eq!(secret.fields[0].value, "hidden-name");

    let index_path = temp.path().join("autofill.json");
    let rebuilt = block_on(api::rebuild_autofill_index(RebuildAutofillIndexRequest {
        index_path: index_path.display().to_string(),
        store_id: "personal".to_string(),
        store_name: "Personal".to_string(),
        root: store_root.display().to_string(),
        entries: vec![AutofillEntryMetadataDto {
            path: "example.com/entry".to_string(),
            is_favorite: true,
            recent_rank: Some(0),
        }],
    }));
    assert!(rebuilt.error.is_none(), "{:?}", rebuilt.error);
    let raw_index = std::fs::read_to_string(&index_path).expect("path index");
    assert!(!raw_index.contains("entry-secret"));
    assert!(!raw_index.contains("hidden-name"));
    assert!(!raw_index.contains("ignored.example"));

    let website = block_on(api::query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.display().to_string(),
        website: Some("example.com".to_string()),
        app_name: None,
        query: None,
        limit: 10,
    }));
    assert!(website.error.is_none(), "{:?}", website.error);
    assert_eq!(website.candidates[0].path, "example.com/entry");
    assert_eq!(website.candidates[0].match_kind, "path_website");

    let app = block_on(api::query_autofill_candidates(AutofillQueryRequest {
        index_path: index_path.display().to_string(),
        website: None,
        app_name: Some("EXAMPLE.COM".to_string()),
        query: None,
        limit: 10,
    }));
    assert!(app.error.is_none(), "{:?}", app.error);
    assert_eq!(app.candidates[0].match_kind, "app_name");
    assert!(website.candidates[0].score > app.candidates[0].score);

    let credential = block_on(api::resolve_autofill_credential(AutofillCredentialRequest {
        config_path: config_path.display().to_string(),
        index_path: index_path.display().to_string(),
        root: store_root.display().to_string(),
        path: "example.com/entry".to_string(),
        pgp_executable: None,
        passphrase: None,
    }));
    assert!(credential.error.is_none(), "{:?}", credential.error);
    let credential = credential.credential.expect("credential");
    assert_eq!(credential.username, "entry");
    assert_eq!(credential.password, "entry-secret");

    let cleared = block_on(api::clear_autofill_index(ClearAutofillIndexRequest {
        index_path: index_path.display().to_string(),
    }));
    assert!(cleared.error.is_none(), "{:?}", cleared.error);
    assert!(!index_path.exists());
}

#[test]
fn inspect_app_state_reports_first_run_recovery_branches() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");

    let no_config = block_on(api::inspect_app_state(InspectAppStateRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
    }));
    let no_config_state = no_config.state.expect("state response");
    assert_eq!(no_config_state.onboarding_state, "no_config");
    assert!(no_config_state.issues.contains(&"no_config".to_string()));

    let store_root = temp.path().join("store");
    let created = block_on(api::create_local_store(CreateLocalStoreRequest {
        config_path: config_path.display().to_string(),
        name: "Personal".to_string(),
        root: store_root.display().to_string(),
        pgp_keys: vec!["missing@example.com".to_string()],
        set_default: true,
        initialize_git: true,
    }));
    assert!(created.error.is_none(), "{:?}", created.error);

    std::fs::remove_file(store_root.join(".gpg-id")).unwrap();
    let missing_gpg = block_on(api::inspect_app_state(InspectAppStateRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
    }));
    let missing_gpg_store = &missing_gpg.state.expect("state response").stores[0];
    assert!(missing_gpg_store.issues.contains(&"missing_gpg_id".to_string()));

    std::fs::write(store_root.join(".gpg-id"), "missing@example.com").unwrap();
    let missing_remote_and_key = block_on(api::inspect_app_state(InspectAppStateRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: Some("/bin/false".to_string()),
    }));
    let store = &missing_remote_and_key.state.expect("state response").stores[0];
    assert!(store.issues.contains(&"git_remote_missing".to_string()));
    assert!(store.issues.contains(&"pgp_key_missing".to_string()));

    std::fs::remove_dir_all(&store_root).unwrap();
    let missing_store = block_on(api::inspect_app_state(InspectAppStateRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
    }));
    let missing_store_state = missing_store.state.expect("state response");
    assert_eq!(missing_store_state.onboarding_state, "store_missing");
    assert!(missing_store_state.stores[0].issues.contains(&"store_missing".to_string()));
}

#[test]
fn inspect_app_state_treats_non_git_local_store_as_ready() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let store_root = temp.path().join("local-store");

    let created = block_on(api::create_local_store(CreateLocalStoreRequest {
        config_path: config_path.display().to_string(),
        name: "Local".to_string(),
        root: store_root.display().to_string(),
        pgp_keys: vec!["local@example.com".to_string()],
        set_default: true,
        initialize_git: false,
    }));
    assert!(created.error.is_none(), "{:?}", created.error);

    let inspected = block_on(api::inspect_app_state(InspectAppStateRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
    }));
    let state = inspected.state.expect("state response");
    assert_eq!(state.onboarding_state, "ready");
    assert!(!state.issues.contains(&"git_remote_missing".to_string()));
}

#[test]
fn delete_local_store_confirms_with_store_name_and_rejects_mismatch() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = temp.path().join("pars_config.toml");
    let store_root = temp.path().join("local-store");

    let created = block_on(api::create_local_store(CreateLocalStoreRequest {
        config_path: config_path.display().to_string(),
        name: "Local".to_string(),
        root: store_root.display().to_string(),
        pgp_keys: vec!["local@example.com".to_string()],
        set_default: true,
        initialize_git: false,
    }));
    assert!(created.error.is_none(), "{:?}", created.error);

    let mismatch = block_on(api::delete_local_store(DeleteLocalStoreRequest {
        config_path: config_path.display().to_string(),
        root: store_root.display().to_string(),
        confirmation: store_root.display().to_string(),
    }));
    let mismatch_error = mismatch.error.expect("mismatched confirmation should fail");
    assert!(mismatch_error.message.contains("store name"), "{mismatch_error:?}");
    assert!(store_root.is_dir(), "mismatched confirmation must not delete the store");

    let deleted = block_on(api::delete_local_store(DeleteLocalStoreRequest {
        config_path: config_path.display().to_string(),
        root: store_root.display().to_string(),
        confirmation: "local-store".to_string(),
    }));
    assert!(deleted.error.is_none(), "{:?}", deleted.error);
    assert!(!store_root.exists(), "store-name confirmation should delete the store");
}

#[test]
fn pgp_inspection_detects_kind_and_protection_independently_of_source() {
    let temp = tempfile::tempdir().unwrap();
    let protected = PgpKeyMaterialFixture::generate(Some(PASSPHRASE));
    let unprotected = PgpKeyMaterialFixture::generate(None);

    // Source (pasted text versus picked file) must not decide public versus private.
    for (label, fixture, material, kind, requires_passphrase) in [
        ("public", &protected, &protected.armored_public, PgpKeyKindDto::Public, false),
        ("protected private", &protected, &protected.armored_private, PgpKeyKindDto::Private, true),
        (
            "unprotected private",
            &unprotected,
            &unprotected.armored_private,
            PgpKeyKindDto::Private,
            false,
        ),
    ] {
        let text = String::from_utf8(material.clone()).unwrap();
        let from_text =
            block_on(api::inspect_pgp_key_text(InspectPgpKeyTextRequest { armored_text: text }));
        let path = temp.path().join("key-material");
        std::fs::write(&path, material).unwrap();
        let from_file = block_on(api::inspect_pgp_key_file(InspectPgpKeyFileRequest {
            path: path.display().to_string(),
        }));

        for response in [from_text, from_file] {
            assert!(response.error.is_none(), "{label}: {:?}", response.error);
            let inspection = response.inspection.expect("inspection");
            assert_eq!(inspection.kind, kind, "{label}");
            assert_eq!(inspection.requires_passphrase, requires_passphrase, "{label}");
            assert_eq!(inspection.fingerprint, fixture.fingerprint, "{label}");
            assert_eq!(inspection.identity, fixture.identity, "{label}");
        }
    }
}

#[test]
fn pgp_file_inspection_reads_binary_material_without_returning_key_bytes() {
    let temp = tempfile::tempdir().unwrap();
    let fixture = PgpKeyMaterialFixture::generate(None);
    let path = temp.path().join("private.gpg");
    std::fs::write(&path, &fixture.binary_private).unwrap();

    let response = block_on(api::inspect_pgp_key_file(InspectPgpKeyFileRequest {
        path: path.display().to_string(),
    }));
    assert!(response.error.is_none(), "{:?}", response.error);

    let inspection = response.inspection.expect("inspection");
    assert_eq!(inspection.kind, PgpKeyKindDto::Private);
    assert!(!inspection.armored, "binary material should be reported as such");
    assert!(inspection.has_private_key);
    // The response type carries metadata only; the key bytes stay in Rust.
    let rendered = format!("{inspection:?}");
    assert!(!rendered.contains("PRIVATE KEY"), "inspection leaked key material: {rendered}");
}

#[test]
fn pgp_import_returns_canonical_fingerprint_and_backend_metadata() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = pure_rust_config(&temp, "import-canonical");
    let fixture = PgpKeyMaterialFixture::generate(None);

    let imported = block_on(api::import_pgp_key_text(ImportPgpKeyTextRequest {
        config_path: config_path.clone(),
        pgp_executable: None,
        armored_text: fixture.armored_public_text(),
        passphrase: None,
    }));
    assert!(imported.error.is_none(), "{:?}", imported.error);
    let key = imported.key.expect("imported key");
    assert_eq!(key.fingerprint, fixture.fingerprint);
    assert_eq!(key.key_type, "pgp");
    // The name is the backend-confirmed identity, not a fingerprint fallback.
    assert_eq!(key.name, fixture.identity);
    assert_ne!(key.name, key.fingerprint);
    assert_eq!(imported.inspection.expect("inspection").kind, PgpKeyKindDto::Public);

    let duplicate = block_on(api::import_pgp_key_text(ImportPgpKeyTextRequest {
        config_path,
        pgp_executable: None,
        armored_text: fixture.armored_public_text(),
        passphrase: None,
    }));
    assert!(duplicate.error.is_none(), "{:?}", duplicate.error);
    assert_eq!(duplicate.key.expect("duplicate key").fingerprint, fixture.fingerprint);
}

#[test]
fn pgp_file_import_accepts_binary_private_material() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = pure_rust_config(&temp, "import-binary");
    let fixture = PgpKeyMaterialFixture::generate(None);
    let path = temp.path().join("private.gpg");
    std::fs::write(&path, &fixture.binary_private).unwrap();

    let imported = block_on(api::import_pgp_key_file(ImportPgpKeyFileRequest {
        config_path,
        pgp_executable: None,
        path: path.display().to_string(),
        passphrase: None,
    }));
    assert!(imported.error.is_none(), "{:?}", imported.error);
    let key = imported.key.expect("imported key");
    assert_eq!(key.fingerprint, fixture.fingerprint);
    assert!(key.has_private_key);
}

#[test]
fn pgp_import_of_protected_key_reports_typed_sanitized_failures() {
    let temp = tempfile::tempdir().unwrap();
    let fixture = PgpKeyMaterialFixture::generate(Some(PASSPHRASE));

    for (label, passphrase, expected) in [
        ("absent", None, PgpImportFailureKind::PassphraseRequired),
        (
            "wrong",
            Some("not the passphrase".to_string()),
            PgpImportFailureKind::IncorrectPassphrase,
        ),
    ] {
        let config_path = pure_rust_config(&temp, &format!("import-{label}"));
        let response = block_on(api::import_pgp_key_text(ImportPgpKeyTextRequest {
            config_path: config_path.clone(),
            pgp_executable: None,
            armored_text: fixture.armored_private_text(),
            passphrase,
        }));

        let error = response.error.expect("import should be rejected");
        assert_eq!(error.pgp_import_kind, Some(expected), "{label}");
        assert!(response.key.is_none(), "{label}");
        assert!(!error.message.contains(PASSPHRASE), "{label}: leaked passphrase");
        assert!(!error.message.contains("not the passphrase"), "{label}: leaked passphrase");
        assert!(!error.message.contains("PRIVATE KEY"), "{label}: leaked key material");

        // Nothing was imported, so the key must not be listed.
        let keys = block_on(api::list_keys(ListKeysRequest {
            config_path,
            pgp_executable: None,
            ssh_dir: Some(temp.path().join("ssh").display().to_string()),
        }));
        assert!(
            !keys.keys.iter().any(|key| key.fingerprint == fixture.fingerprint),
            "{label}: keyring was mutated"
        );
    }

    let config_path = pure_rust_config(&temp, "import-correct");
    let response = block_on(api::import_pgp_key_text(ImportPgpKeyTextRequest {
        config_path,
        pgp_executable: None,
        armored_text: fixture.armored_private_text(),
        passphrase: Some(PASSPHRASE.to_string()),
    }));
    assert!(response.error.is_none(), "{:?}", response.error);
    assert_eq!(response.key.expect("imported key").fingerprint, fixture.fingerprint);
}

#[test]
fn bridge_returns_legacy_import_only_after_commit_and_then_prepares_as_a_noop() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = pure_rust_config(&temp, "import-legacy-commit");
    let armored_text =
        include_str!("../../core/tests/fixtures/legacy-sha1-coded-1-private.asc").to_string();
    let imported = block_on(api::import_pgp_key_text(ImportPgpKeyTextRequest {
        config_path: config_path.clone(),
        pgp_executable: None,
        armored_text,
        passphrase: Some("pars legacy fixture password".to_string()),
    }));
    assert!(imported.error.is_none(), "{:?}", imported.error);
    let fingerprint = imported.key.expect("committed legacy import").fingerprint;

    let prepared = block_on(api::prepare_pgp_private_key(PreparePgpPrivateKeyRequest {
        config_path,
        pgp_executable: None,
        fingerprint: fingerprint.clone(),
        passphrase: "pars legacy fixture password".to_string(),
    }));

    assert!(prepared.error.is_none(), "{:?}", prepared.error);
    assert_eq!(prepared.fingerprint.as_deref(), Some(fingerprint.as_str()));
    assert!(!prepared.migrated, "import must have committed managed protection first");
}

#[test]
fn pgp_import_reports_unsupported_material_as_a_typed_failure() {
    let temp = tempfile::tempdir().unwrap();
    let config_path = pure_rust_config(&temp, "import-unsupported");

    // The same blob `detect_imported_key` still calls `pgp_public`: the new path parses packets, so
    // it refuses material that merely looks like a key.
    let response = block_on(api::import_pgp_key_text(ImportPgpKeyTextRequest {
        config_path,
        pgp_executable: None,
        armored_text:
            "-----BEGIN PGP PUBLIC KEY BLOCK-----\nabc\n-----END PGP PUBLIC KEY BLOCK-----"
                .to_string(),
        passphrase: None,
    }));

    let error = response.error.expect("unsupported material should fail");
    assert_eq!(error.pgp_import_kind, Some(PgpImportFailureKind::UnsupportedMaterial));
}

#[test]
fn legacy_pgp_import_methods_stay_kind_specific_and_return_canonical_fingerprints() {
    let temp = tempfile::tempdir().unwrap();
    let fixture = PgpKeyMaterialFixture::generate(None);

    let config_path = pure_rust_config(&temp, "legacy-public");
    let imported = block_on(api::import_pgp_public_key(ImportKeyTextRequest {
        config_path: config_path.clone(),
        pgp_executable: None,
        ssh_dir: None,
        name: None,
        armored_text: fixture.armored_public_text(),
    }));
    assert!(imported.error.is_none(), "{:?}", imported.error);
    // Used to be `String::new()` for system GPG and is now canonical everywhere.
    assert_eq!(imported.key.expect("imported key").fingerprint, fixture.fingerprint);

    let mismatched = block_on(api::import_pgp_private_key_text(ImportKeyTextRequest {
        config_path,
        pgp_executable: None,
        ssh_dir: None,
        name: None,
        armored_text: fixture.armored_public_text(),
    }));
    let error = mismatched.error.expect("public material must not satisfy a private import");
    assert_eq!(error.pgp_import_kind, Some(PgpImportFailureKind::KindMismatch));
}

/// Writes a config selecting the pure-Rust backend with its own keyring, so each test starts empty.
fn pure_rust_config(temp: &tempfile::TempDir, name: &str) -> String {
    let config_path = temp.path().join(format!("{name}.toml"));
    let keyring_home = temp.path().join(name);
    std::fs::write(
        &config_path,
        format!(
            "[pgp_config]\nbackend = \"pure_rust\"\nkeyring_home = \"{}\"\n",
            toml_path(&keyring_home)
        ),
    )
    .unwrap();
    config_path.display().to_string()
}

fn block_on<T>(future: impl Future<Output = T>) -> T {
    let waker = noop_waker();
    let mut context = Context::from_waker(&waker);
    let mut future = pin!(future);
    match Future::poll(future.as_mut(), &mut context) {
        Poll::Ready(value) => value,
        Poll::Pending => panic!("bridge future unexpectedly pending"),
    }
}

fn toml_path(path: &Path) -> String {
    path.display().to_string().replace('\\', "/")
}

fn noop_waker() -> Waker {
    unsafe fn clone(_: *const ()) -> RawWaker {
        raw_waker()
    }
    unsafe fn wake(_: *const ()) {}
    unsafe fn wake_by_ref(_: *const ()) {}
    unsafe fn drop(_: *const ()) {}

    fn raw_waker() -> RawWaker {
        RawWaker::new(std::ptr::null(), &RawWakerVTable::new(clone, wake, wake_by_ref, drop))
    }

    unsafe { Waker::from_raw(raw_waker()) }
}
