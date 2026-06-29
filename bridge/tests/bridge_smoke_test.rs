use std::future::Future;
use std::pin::pin;
use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

use pars_bridge::api::{
    self, AddPgpKeyToGpgIdRequest, ConfigurePgpBackendRequest, CreateLocalStoreRequest,
    DeleteLocalStoreRequest, DeletePgpKeyRequest, DeleteSshKeyRequest, EntryRequest,
    ExportPgpKeyRequest, ExportSshKeyRequest, GeneratePgpKeyRequest, GenerateSshKeyRequest,
    ImportKeyTextRequest, InsertEntryRequest, InspectAppStateRequest, ListEntriesRequest,
    ListKeysRequest, OpenGithubSshSettingsRequest, SUPPORTED_METHODS,
};

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
        "import_pgp_public_key",
        "import_pgp_private_key_file",
        "import_pgp_private_key_text",
        "export_pgp_public_key",
        "export_pgp_private_key",
        "delete_pgp_key",
        "add_pgp_key_to_gpg_id",
        "generate_ssh_key",
        "import_ssh_private_key_file",
        "import_ssh_private_key_text",
        "export_ssh_public_key",
        "export_ssh_private_key",
        "delete_ssh_key",
        "open_github_ssh_settings",
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
            keyring_home.display()
        ),
    )
    .unwrap();

    let generated = block_on(api::generate_pgp_key(GeneratePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        name: "Alice Example".to_string(),
        email: "alice@example.com".to_string(),
        passphrase: None,
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

    let deleted = block_on(api::delete_pgp_key(DeletePgpKeyRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        fingerprint: generated_key.fingerprint.clone(),
    }));
    assert!(deleted.error.is_none(), "{:?}", deleted.error);

    let keys_after_delete = block_on(api::list_keys(ListKeysRequest {
        config_path: config_path.display().to_string(),
        pgp_executable: None,
        ssh_dir: Some(temp.path().join("ssh").display().to_string()),
    }));
    assert!(keys_after_delete.error.is_none(), "{:?}", keys_after_delete.error);
    assert!(!keys_after_delete.keys.iter().any(|key| key.fingerprint == generated_key.fingerprint));
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
            keyring_home.display()
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
        path: "work/example".to_string(),
        content: "entry-secret\nusername: entry".to_string(),
        overwrite: false,
        pgp_executable: String::new(),
    }));
    assert!(inserted.error.is_none(), "{:?}", inserted.error);

    let read = block_on(api::read_entry(EntryRequest {
        config_path: config_path.display().to_string(),
        root: store_root.display().to_string(),
        path: "work/example".to_string(),
        pgp_executable: None,
    }));
    assert!(read.error.is_none(), "{:?}", read.error);
    let secret = read.secret.expect("secret");
    assert_eq!(secret.password, "entry-secret");
    assert_eq!(secret.fields[0].value, "entry");
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

fn block_on<T>(future: impl Future<Output = T>) -> T {
    let waker = noop_waker();
    let mut context = Context::from_waker(&waker);
    let mut future = pin!(future);
    match Future::poll(future.as_mut(), &mut context) {
        Poll::Ready(value) => value,
        Poll::Pending => panic!("bridge future unexpectedly pending"),
    }
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
