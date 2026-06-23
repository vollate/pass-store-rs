use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;

use pars_core::config::cli::{
    load_config as load_core_config, save_config as save_core_config, ParsConfig,
};
pub use pars_core::gui::ListEntriesRequest;
use pars_core::gui::{
    self, CoreError, DeleteEntryRequest, DeleteEntryResult, EditEntryRequest, EntryMutationResult,
    EntrySecret, GenerateEntryRequest, GenerateEntryResult, GitCommandOutput, GitOperationRequest,
    InsertEntryRequest, InsertEntryResult, MoveEntryRequest, ReadEntryRequest, StoreId, StoreInfo,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub type BridgeResult<T> = Result<T, BridgeError>;

pub const SUPPORTED_METHODS: &[&str] = &[
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

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct BridgeError {
    pub category: String,
    pub message: String,
    pub conflict_kind: Option<String>,
    pub path: Option<String>,
}

impl BridgeError {
    fn validation(message: impl Into<String>) -> Self {
        Self {
            category: "ValidationError".to_string(),
            message: message.into(),
            conflict_kind: None,
            path: None,
        }
    }

    fn unsupported(message: impl Into<String>) -> Self {
        Self {
            category: "UnsupportedPlatform".to_string(),
            message: message.into(),
            conflict_kind: None,
            path: None,
        }
    }
}

impl From<CoreError> for BridgeError {
    fn from(value: CoreError) -> Self {
        match value {
            CoreError::ConfigError(message) => Self {
                category: "ConfigError".to_string(),
                message,
                conflict_kind: None,
                path: None,
            },
            CoreError::StoreError(message) => Self {
                category: "StoreError".to_string(),
                message,
                conflict_kind: None,
                path: None,
            },
            CoreError::PgpError(message) => {
                Self { category: "PgpError".to_string(), message, conflict_kind: None, path: None }
            }
            CoreError::GitError(message) => {
                Self { category: "GitError".to_string(), message, conflict_kind: None, path: None }
            }
            CoreError::ClipboardError(message) => Self {
                category: "ClipboardError".to_string(),
                message,
                conflict_kind: None,
                path: None,
            },
            CoreError::ValidationError(message) => Self {
                category: "ValidationError".to_string(),
                message,
                conflict_kind: None,
                path: None,
            },
            CoreError::Conflict(conflict) => Self {
                category: "Conflict".to_string(),
                message: conflict.to_string(),
                conflict_kind: Some(format!("{:?}", conflict.kind)),
                path: Some(conflict.path),
            },
            CoreError::UnsupportedPlatform(message) => Self {
                category: "UnsupportedPlatform".to_string(),
                message,
                conflict_kind: None,
                path: None,
            },
        }
    }
}

impl From<serde_json::Error> for BridgeError {
    fn from(value: serde_json::Error) -> Self {
        BridgeError::validation(value.to_string())
    }
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct BridgeEnvelope {
    pub method: String,
    #[serde(default)]
    pub payload: Value,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct LoadConfigRequest {
    pub path: PathBuf,
}

#[derive(Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SaveConfigRequest {
    pub path: PathBuf,
    pub config: ParsConfig,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct ListStoresRequest {
    pub config_path: Option<PathBuf>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GitRequest {
    pub root: PathBuf,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GitCommitRequest {
    pub root: PathBuf,
    pub message: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct CopyEntryPasswordResult {
    pub path: String,
    pub password: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
struct BridgeWireResponse {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<BridgeError>,
}

pub async fn load_config(request: LoadConfigRequest) -> BridgeResult<ParsConfig> {
    load_config_sync(request)
}

pub async fn save_config(request: SaveConfigRequest) -> BridgeResult<()> {
    save_config_sync(request)
}

pub async fn list_stores(request: ListStoresRequest) -> BridgeResult<Vec<StoreInfo>> {
    list_stores_sync(request)
}

pub async fn list_entries(
    request: ListEntriesRequest,
) -> BridgeResult<Vec<pars_core::gui::EntrySummary>> {
    gui::list_entries(request).map_err(BridgeError::from)
}

pub async fn read_entry(request: ReadEntryRequest) -> BridgeResult<EntrySecret> {
    gui::read_entry(request).map_err(BridgeError::from)
}

pub async fn copy_entry_password(
    request: ReadEntryRequest,
) -> BridgeResult<CopyEntryPasswordResult> {
    copy_entry_password_sync(request)
}

pub async fn insert_entry(request: InsertEntryRequest) -> BridgeResult<InsertEntryResult> {
    gui::insert_entry(request).map_err(BridgeError::from)
}

pub async fn generate_entry(request: GenerateEntryRequest) -> BridgeResult<GenerateEntryResult> {
    gui::generate_entry(request).map_err(BridgeError::from)
}

pub async fn edit_entry(request: EditEntryRequest) -> BridgeResult<EntryMutationResult> {
    gui::edit_entry(request).map_err(BridgeError::from)
}

pub async fn move_entry(request: MoveEntryRequest) -> BridgeResult<EntryMutationResult> {
    gui::move_entry(request).map_err(BridgeError::from)
}

pub async fn delete_entry(request: DeleteEntryRequest) -> BridgeResult<DeleteEntryResult> {
    gui::delete_entry(request).map_err(BridgeError::from)
}

pub async fn git_status(request: GitRequest) -> BridgeResult<GitCommandOutput> {
    run_git_command(request.root, vec!["status", "--short", "--branch"])
}

pub async fn git_pull(request: GitRequest) -> BridgeResult<GitCommandOutput> {
    run_git_command(request.root, vec!["pull"])
}

pub async fn git_push(request: GitRequest) -> BridgeResult<GitCommandOutput> {
    run_git_command(request.root, vec!["push"])
}

pub async fn git_commit(request: GitCommitRequest) -> BridgeResult<GitCommandOutput> {
    run_git_command(request.root, vec!["commit", "-m", request.message.as_str()])
}

pub async fn run_git_args(request: GitOperationRequest) -> BridgeResult<GitCommandOutput> {
    gui::run_git_args(request).map_err(BridgeError::from)
}

pub fn dispatch(envelope: BridgeEnvelope) -> BridgeResult<Value> {
    match envelope.method.as_str() {
        "load_config" => to_value(load_config_sync(from_value(envelope.payload)?)?),
        "save_config" => to_value(save_config_sync(from_value(envelope.payload)?)?),
        "list_stores" => to_value(list_stores_sync(from_value(envelope.payload)?)?),
        "list_entries" => to_value(gui::list_entries(from_value(envelope.payload)?)?),
        "read_entry" => to_value(gui::read_entry(from_value(envelope.payload)?)?),
        "copy_entry_password" => to_value(copy_entry_password_sync(from_value(envelope.payload)?)?),
        "insert_entry" => to_value(gui::insert_entry(from_value(envelope.payload)?)?),
        "generate_entry" => to_value(gui::generate_entry(from_value(envelope.payload)?)?),
        "edit_entry" => to_value(gui::edit_entry(from_value(envelope.payload)?)?),
        "move_entry" => to_value(gui::move_entry(from_value(envelope.payload)?)?),
        "delete_entry" => to_value(gui::delete_entry(from_value(envelope.payload)?)?),
        "git_status" => {
            let request: GitRequest = from_value(envelope.payload)?;
            to_value(run_git_command(request.root, vec!["status", "--short", "--branch"])?)
        }
        "git_pull" => {
            let request: GitRequest = from_value(envelope.payload)?;
            to_value(run_git_command(request.root, vec!["pull"])?)
        }
        "git_push" => {
            let request: GitRequest = from_value(envelope.payload)?;
            to_value(run_git_command(request.root, vec!["push"])?)
        }
        "git_commit" => {
            let request: GitCommitRequest = from_value(envelope.payload)?;
            to_value(run_git_command(request.root, vec!["commit", "-m", request.message.as_str()])?)
        }
        "run_git_args" => to_value(gui::run_git_args(from_value(envelope.payload)?)?),
        method => Err(BridgeError::unsupported(format!("unsupported bridge method: {method}"))),
    }
}

pub fn bridge_call_json(request_json: &str) -> String {
    let response = match serde_json::from_str::<BridgeEnvelope>(request_json) {
        Ok(envelope) => match dispatch(envelope) {
            Ok(result) => BridgeWireResponse { ok: true, result: Some(result), error: None },
            Err(error) => BridgeWireResponse { ok: false, result: None, error: Some(error) },
        },
        Err(error) => {
            BridgeWireResponse { ok: false, result: None, error: Some(BridgeError::from(error)) }
        }
    };

    serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(
            r#"{{"ok":false,"error":{{"category":"ValidationError","message":"failed to serialize bridge response: {error}","conflict_kind":null,"path":null}}}}"#
        )
    })
}

#[no_mangle]
pub extern "C" fn pars_bridge_call(request_json: *const c_char) -> *mut c_char {
    let request = if request_json.is_null() {
        return string_to_c(bridge_call_json(""));
    } else {
        unsafe { CStr::from_ptr(request_json) }.to_string_lossy().into_owned()
    };

    string_to_c(bridge_call_json(&request))
}

#[no_mangle]
pub extern "C" fn pars_bridge_free_string(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}

fn load_config_sync(request: LoadConfigRequest) -> BridgeResult<ParsConfig> {
    load_core_config(request.path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .map_err(BridgeError::from)
}

fn save_config_sync(request: SaveConfigRequest) -> BridgeResult<()> {
    save_core_config(&request.config, request.path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .map_err(BridgeError::from)
}

fn list_stores_sync(request: ListStoresRequest) -> BridgeResult<Vec<StoreInfo>> {
    let config = match request.config_path {
        Some(path) => load_core_config(path)
            .map_err(|error| CoreError::ConfigError(error.to_string()))
            .map_err(BridgeError::from)?,
        None => ParsConfig::default(),
    };

    Ok(config
        .path_config
        .repos
        .iter()
        .enumerate()
        .map(|(index, root)| {
            let root = PathBuf::from(root);
            let name = root.file_name().and_then(|name| name.to_str()).unwrap_or("password-store");
            StoreInfo {
                id: StoreId(format!("store-{index}")),
                name: name.to_string(),
                root: root.clone(),
                is_default: root == PathBuf::from(&config.path_config.default_repo),
            }
        })
        .collect())
}

fn copy_entry_password_sync(request: ReadEntryRequest) -> BridgeResult<CopyEntryPasswordResult> {
    let path = request.entry.path.clone();
    let secret = gui::read_entry(request).map_err(BridgeError::from)?;
    Ok(CopyEntryPasswordResult { path, password: secret.password })
}

fn run_git_command(root: PathBuf, args: Vec<&str>) -> BridgeResult<GitCommandOutput> {
    let args = args.into_iter().map(str::to_string).collect::<Vec<_>>();
    let request = GitOperationRequest::new(root, args).map_err(BridgeError::from)?;
    gui::run_git_args(request).map_err(BridgeError::from)
}

fn from_value<T>(value: Value) -> BridgeResult<T>
where
    T: for<'de> Deserialize<'de>,
{
    serde_json::from_value(value).map_err(BridgeError::from)
}

fn to_value<T>(value: T) -> BridgeResult<Value>
where
    T: Serialize,
{
    serde_json::to_value(value).map_err(BridgeError::from)
}

fn string_to_c(value: String) -> *mut c_char {
    CString::new(value).unwrap_or_default().into_raw()
}
