use pars_bridge::api::{self, ListEntriesRequest, SUPPORTED_METHODS};

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
