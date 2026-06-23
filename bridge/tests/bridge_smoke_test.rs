use pars_bridge::api::{self, BridgeEnvelope, ListEntriesRequest, SUPPORTED_METHODS};

#[test]
fn rust_bridge_api_exposes_list_entries_future() {
    let temp = tempfile::tempdir().unwrap();
    let request =
        ListEntriesRequest { root: temp.path().to_path_buf(), target: None, recursive: true };

    drop(api::list_entries(request));
}

#[test]
fn bridge_dispatch_reports_unknown_methods_as_typed_failures() {
    let response = api::dispatch(BridgeEnvelope {
        method: "missing_method".to_string(),
        payload: serde_json::json!({}),
    });

    let error = response.unwrap_err();
    assert_eq!(error.category, "UnsupportedPlatform");
    assert!(error.message.contains("missing_method"));
}

#[test]
fn bridge_method_table_covers_milestone_two_api_surface() {
    let expected = [
        "load_config",
        "save_config",
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
    ];

    assert_eq!(SUPPORTED_METHODS, expected);
}

#[test]
fn bridge_error_responses_do_not_echo_secret_payloads() {
    let response = api::bridge_call_json(
        r#"{"method":"missing_method","payload":{"password":"do-not-log-this"}}"#,
    );

    assert!(response.contains("UnsupportedPlatform"));
    assert!(!response.contains("do-not-log-this"));
}
