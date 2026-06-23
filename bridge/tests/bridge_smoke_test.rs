use pars_bridge::api::{self, BridgeEnvelope, ListEntriesRequest};

#[test]
fn rust_bridge_api_exposes_list_entries_future() {
    let temp = tempfile::tempdir().unwrap();
    let request = ListEntriesRequest {
        root: temp.path().to_path_buf(),
        target: None,
        recursive: true,
    };

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
