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
#[serde(rename_all = "camelCase")]
struct NativeAutofillQueryRequest {
    index_path: String,
    website: Option<String>,
    android_package: Option<String>,
    query: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCredentialRequest {
    config_path: String,
    index_path: String,
    root: String,
    path: String,
    pgp_executable: Option<String>,
    passphrase: Option<String>,
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
struct NativeAutofillCandidate {
    path: String,
    display_name: String,
    username: Option<String>,
    match_kind: String,
    match_value: String,
    score: i32,
    is_favorite: bool,
    recent_rank: Option<u32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeAutofillCredential {
    path: String,
    username: Option<String>,
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
            android_package: request.android_package,
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
            recent_rank: value.recent_rank,
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

    use super::{query_candidates_json, resolve_credential_json};

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
    use pars_core::autofill::{write_autofill_index, AutofillIndex, AutofillIndexEntry};
    use serde_json::Value;
    use tempfile::tempdir;

    use super::query_candidates_json;

    #[test]
    fn query_candidates_json_matches_android_package() {
        let dir = tempdir().unwrap();
        let index_path = dir.path().join("autofill.json");
        write_autofill_index(
            &index_path,
            &AutofillIndex {
                version: 1,
                store_id: "selected".to_string(),
                store_name: "Selected store".to_string(),
                store_root: dir.path().display().to_string(),
                generated_at_epoch_seconds: 1,
                entries: vec![AutofillIndexEntry {
                    path: "bank/example".to_string(),
                    display_name: "Example Bank".to_string(),
                    username: Some("alice".to_string()),
                    websites: vec!["example.com".to_string()],
                    android_packages: vec!["com.example.bank".to_string()],
                    is_favorite: true,
                    recent_rank: Some(0),
                    updated_at_epoch_seconds: 1,
                }],
            },
        )
        .unwrap();

        let raw = query_candidates_json(&format!(
            r#"{{"indexPath":"{}","androidPackage":"com.example.bank","limit":5}}"#,
            index_path.display().to_string().replace('\\', "\\\\")
        ));
        let value: Value = serde_json::from_str(&raw).unwrap();

        assert!(value["error"].is_null());
        assert_eq!(value["candidates"][0]["path"], "bank/example");
        assert_eq!(value["candidates"][0]["matchKind"], "android_package");
    }

    #[test]
    fn query_candidates_json_reports_invalid_request() {
        let raw = query_candidates_json("{");
        let value: Value = serde_json::from_str(&raw).unwrap();

        assert_eq!(value["candidates"].as_array().unwrap().len(), 0);
        assert_eq!(value["error"]["category"], "validation_error");
    }
}
