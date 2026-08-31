use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;

use pars_core::autofill::{
    self, AutofillCredentialRequest as CoreAutofillCredentialRequest,
    AutofillQueryRequest as CoreAutofillQueryRequest,
};
use pars_core::gui::CoreError;
use serde::{Deserialize, Serialize};

use crate::api::{self, BridgeFailure};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct NativeAutofillQueryRequest {
    index_path: String,
    website: Option<String>,
    app_name: Option<String>,
    query: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct NativeAutofillCredentialRequest {
    config_path: String,
    index_path: String,
    root: String,
    path: String,
    pgp_executable: Option<String>,
    passphrase: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct NativeAutofillCompletionRequest {
    index_path: String,
    path: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCandidatesResponse {
    candidates: Vec<NativeAutofillCandidate>,
    error: Option<NativeAutofillError>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCredentialResponse {
    credential: Option<NativeAutofillCredential>,
    error: Option<NativeAutofillError>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCompletionResponse {
    recorded: bool,
    error: Option<NativeAutofillError>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCandidate {
    path: String,
    display_name: String,
    username: String,
    match_kind: String,
    match_value: String,
    score: i32,
    is_favorite: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCredential {
    path: String,
    username: String,
    password: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillError {
    category: String,
    message: String,
}

pub fn query_candidates_json(request_json: &str) -> String {
    let response = match serde_json::from_str::<NativeAutofillQueryRequest>(request_json) {
        Ok(request) => match autofill::query_autofill_candidates(CoreAutofillQueryRequest {
            index_path: PathBuf::from(request.index_path),
            website: request.website,
            app_name: request.app_name,
            query: request.query,
            limit: request.limit.unwrap_or(10),
        }) {
            Ok(candidates) => NativeAutofillCandidatesResponse {
                candidates: candidates.into_iter().map(NativeAutofillCandidate::from).collect(),
                error: None,
            },
            Err(error) => NativeAutofillCandidatesResponse {
                candidates: Vec::new(),
                error: Some(NativeAutofillError::from(BridgeFailure::from(error))),
            },
        },
        Err(error) => NativeAutofillCandidatesResponse {
            candidates: Vec::new(),
            error: Some(NativeAutofillError::validation(error)),
        },
    };
    serialize_response(&response)
}

pub fn resolve_credential_json(request_json: &str) -> String {
    let response = match serde_json::from_str::<NativeAutofillCredentialRequest>(request_json) {
        Ok(request) => {
            let backend =
                match api::pgp_backend(&request.config_path, request.pgp_executable.as_deref()) {
                    Ok(backend) => backend,
                    Err(error) => {
                        return serialize_response(&NativeAutofillCredentialResponse {
                            credential: None,
                            error: Some(NativeAutofillError::from(error)),
                        });
                    }
                };
            match autofill::resolve_autofill_credential_with_backend(
                CoreAutofillCredentialRequest {
                    index_path: PathBuf::from(request.index_path),
                    store_root: PathBuf::from(request.root),
                    path: request.path,
                    pgp_executable: request.pgp_executable.unwrap_or_default(),
                    passphrase: request.passphrase,
                },
                backend.as_ref(),
            ) {
                Ok(credential) => NativeAutofillCredentialResponse {
                    credential: Some(NativeAutofillCredential::from(credential)),
                    error: None,
                },
                Err(error) => NativeAutofillCredentialResponse {
                    credential: None,
                    error: Some(NativeAutofillError::from(BridgeFailure::from(error))),
                },
            }
        }
        Err(error) => NativeAutofillCredentialResponse {
            credential: None,
            error: Some(NativeAutofillError::validation(error)),
        },
    };
    serialize_response(&response)
}

pub fn record_completion_json(request_json: &str) -> String {
    let response = match serde_json::from_str::<NativeAutofillCompletionRequest>(request_json) {
        Ok(request) => {
            match autofill::record_autofill_completion(autofill::RecordAutofillCompletionRequest {
                index_path: PathBuf::from(request.index_path),
                path: request.path,
            }) {
                Ok(_) => NativeAutofillCompletionResponse { recorded: true, error: None },
                Err(error) => NativeAutofillCompletionResponse {
                    recorded: false,
                    error: Some(NativeAutofillError::from(BridgeFailure::from(error))),
                },
            }
        }
        Err(error) => NativeAutofillCompletionResponse {
            recorded: false,
            error: Some(NativeAutofillError::validation(error)),
        },
    };
    serialize_response(&response)
}

#[no_mangle]
pub extern "C" fn pars_autofill_query_candidates_json(request_json: *const c_char) -> *mut c_char {
    ffi_json(request_json, query_candidates_json)
}

#[no_mangle]
pub extern "C" fn pars_autofill_resolve_credential_json(
    request_json: *const c_char,
) -> *mut c_char {
    ffi_json(request_json, resolve_credential_json)
}

#[no_mangle]
pub extern "C" fn pars_autofill_record_completion_json(request_json: *const c_char) -> *mut c_char {
    ffi_json(request_json, record_completion_json)
}

#[no_mangle]
/// Releases a string returned by one of this module's native JSON functions.
///
/// # Safety
///
/// `value` must be null or a pointer returned by `CString::into_raw` from this library, and it
/// must not have been freed previously.
pub unsafe extern "C" fn pars_autofill_free_string(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: upheld by the caller contract above.
        drop(unsafe { CString::from_raw(value) });
    }
}

fn serialize_response<T>(response: &T) -> String
where
    T: Serialize,
{
    serde_json::to_string(response).unwrap_or_else(|error| {
        format!(r#"{{"error":{{"category":"serialization_error","message":"{}"}}}}"#, error)
    })
}

fn ffi_json(request_json: *const c_char, handler: fn(&str) -> String) -> *mut c_char {
    let response = if request_json.is_null() {
        r#"{"error":{"category":"validation_error","message":"request_json is null"}}"#.to_string()
    } else {
        match unsafe { CStr::from_ptr(request_json) }.to_str() {
            Ok(request) => handler(request),
            Err(error) => {
                format!(r#"{{"error":{{"category":"validation_error","message":"{}"}}}}"#, error)
            }
        }
    };
    CString::new(response)
        .unwrap_or_else(|error| {
            CString::new(format!(
                r#"{{"error":{{"category":"serialization_error","message":"{}"}}}}"#,
                error
            ))
            .expect("fallback JSON does not contain NUL bytes")
        })
        .into_raw()
}

impl NativeAutofillError {
    fn validation(error: serde_json::Error) -> Self {
        Self { category: "validation_error".to_string(), message: error.to_string() }
    }
}

impl From<BridgeFailure> for NativeAutofillError {
    fn from(value: BridgeFailure) -> Self {
        Self { category: format!("{:?}", value.category), message: value.message }
    }
}

impl From<autofill::AutofillCandidate> for NativeAutofillCandidate {
    fn from(value: autofill::AutofillCandidate) -> Self {
        Self {
            path: value.path,
            display_name: value.display_name,
            username: value.username,
            match_kind: value.match_kind,
            match_value: value.match_value,
            score: value.score,
            is_favorite: value.is_favorite,
        }
    }
}

impl From<autofill::AutofillCredential> for NativeAutofillCredential {
    fn from(value: autofill::AutofillCredential) -> Self {
        Self { path: value.path, username: value.username, password: value.password }
    }
}

impl From<CoreError> for NativeAutofillError {
    fn from(value: CoreError) -> Self {
        NativeAutofillError::from(BridgeFailure::from(value))
    }
}

#[cfg(target_os = "android")]
mod android_jni {
    use jni::objects::{JClass, JString};
    use jni::sys::jstring;
    use jni::JNIEnv;

    use super::{query_candidates_json, record_completion_json, resolve_credential_json};

    #[no_mangle]
    pub extern "system" fn Java_top_vollate_pars_1gui_autofill_ParsAutofillNative_queryCandidatesJson(
        mut env: JNIEnv,
        _class: JClass,
        request: JString,
    ) -> jstring {
        call_json(&mut env, request, query_candidates_json)
    }

    #[no_mangle]
    pub extern "system" fn Java_top_vollate_pars_1gui_autofill_ParsAutofillNative_resolveCredentialJson(
        mut env: JNIEnv,
        _class: JClass,
        request: JString,
    ) -> jstring {
        call_json(&mut env, request, resolve_credential_json)
    }

    #[no_mangle]
    pub extern "system" fn Java_top_vollate_pars_1gui_autofill_ParsAutofillNative_recordCompletionJson(
        mut env: JNIEnv,
        _class: JClass,
        request: JString,
    ) -> jstring {
        call_json(&mut env, request, record_completion_json)
    }

    fn call_json(env: &mut JNIEnv, request: JString, handler: fn(&str) -> String) -> jstring {
        let request = match env.get_string(&request) {
            Ok(value) => String::from(value),
            Err(error) => {
                format!(r#"{{"error":{{"category":"jni_error","message":"{}"}}}}"#, error)
            }
        };
        let response = handler(&request);
        env.new_string(response).map(JString::into_raw).unwrap_or(std::ptr::null_mut())
    }
}

#[cfg(test)]
mod tests {
    use pars_core::autofill::{
        read_autofill_index, write_autofill_index, AutofillIndex, AutofillIndexEntry,
        AUTOFILL_INDEX_VERSION,
    };
    use serde_json::Value;
    use tempfile::tempdir;

    use super::{query_candidates_json, record_completion_json};

    #[test]
    fn query_candidates_json_matches_path_website_and_app_name() {
        let dir = tempdir().unwrap();
        let index_path = dir.path().join("autofill.json");
        write_autofill_index(
            &index_path,
            &AutofillIndex {
                version: AUTOFILL_INDEX_VERSION,
                store_id: "selected".to_string(),
                store_name: "Selected store".to_string(),
                store_root: dir.path().display().to_string(),
                generated_at_epoch_seconds: 1,
                entries: vec![AutofillIndexEntry {
                    path: "example.com/alice".to_string(),
                    display_name: "example.com".to_string(),
                    service_name: Some("example.com".to_string()),
                    username: "alice".to_string(),
                    path_website: Some("example.com".to_string()),
                    enriched_websites: Vec::new(),
                    is_favorite: true,
                    autofill_rank: None,
                    updated_at_epoch_seconds: 1,
                }],
            },
        )
        .unwrap();

        let website_raw = query_candidates_json(&format!(
            r#"{{"indexPath":"{}","website":"https://www.example.com/login","limit":5}}"#,
            index_path.display().to_string().replace('\\', "\\\\")
        ));
        let website: Value = serde_json::from_str(&website_raw).unwrap();
        assert!(website["error"].is_null());
        assert_eq!(website["candidates"][0]["path"], "example.com/alice");
        assert_eq!(website["candidates"][0]["matchKind"], "path_website");
        assert_eq!(website["candidates"][0]["username"], "alice");

        let app_raw = query_candidates_json(&format!(
            r#"{{"indexPath":"{}","appName":"EXAMPLE.COM","limit":5}}"#,
            index_path.display().to_string().replace('\\', "\\\\")
        ));
        let app: Value = serde_json::from_str(&app_raw).unwrap();
        assert_eq!(app["candidates"][0]["matchKind"], "app_name");

        let completion_raw = record_completion_json(&format!(
            r#"{{"indexPath":"{}","path":"example.com/alice"}}"#,
            index_path.display().to_string().replace('\\', "\\\\")
        ));
        let completion: Value = serde_json::from_str(&completion_raw).unwrap();
        assert_eq!(completion["recorded"], true);
        assert!(completion["error"].is_null());
        assert_eq!(read_autofill_index(&index_path).unwrap().entries[0].autofill_rank, Some(0));
    }

    #[test]
    fn query_candidates_json_rejects_package_and_malformed_index_shapes() {
        let dir = tempdir().unwrap();
        let index_path = dir.path().join("autofill.json");
        std::fs::write(&index_path, "{}").unwrap();

        let package_raw = query_candidates_json(&format!(
            r#"{{"indexPath":"{}","androidPackage":"com.example.app","limit":5}}"#,
            index_path.display().to_string().replace('\\', "\\\\")
        ));
        let package: Value = serde_json::from_str(&package_raw).unwrap();
        assert_eq!(package["error"]["category"], "validation_error");

        let malformed_raw = query_candidates_json(&format!(
            r#"{{"indexPath":"{}","query":"alice","limit":5}}"#,
            index_path.display().to_string().replace('\\', "\\\\")
        ));
        let malformed: Value = serde_json::from_str(&malformed_raw).unwrap();
        assert!(malformed["candidates"].as_array().unwrap().is_empty());
        assert!(!malformed["error"].is_null());
    }

    #[test]
    fn query_candidates_json_reports_invalid_request() {
        let raw = query_candidates_json("{");
        let value: Value = serde_json::from_str(&raw).unwrap();

        assert_eq!(value["candidates"].as_array().unwrap().len(), 0);
        assert_eq!(value["error"]["category"], "validation_error");
    }
}
