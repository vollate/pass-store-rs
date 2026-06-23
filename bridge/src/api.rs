use std::path::PathBuf;

use pars_core::config::cli::{
    load_config as load_core_config, save_config as save_core_config, ParsConfig,
};
use pars_core::gui::{self, CoreError, EntryRef, GitOperationRequest, StoreId, StoreInfo};

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

#[derive(Debug, Clone)]
pub enum BridgeFailureCategory {
    ConfigError,
    StoreError,
    PgpError,
    GitError,
    ClipboardError,
    ValidationError,
    Conflict,
    UnsupportedPlatform,
}

#[derive(Debug, Clone)]
pub struct BridgeFailure {
    pub category: BridgeFailureCategory,
    pub message: String,
    pub conflict_kind: Option<String>,
    pub path: Option<String>,
}

#[derive(Debug, Clone)]
pub struct UnitResponse {
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct ConfigResponse {
    pub config_toml: Option<String>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct ListStoresResponse {
    pub stores: Vec<StoreInfoDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct ListEntriesResponse {
    pub entries: Vec<EntrySummaryDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct EntrySecretResponse {
    pub secret: Option<EntrySecretDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct CopyEntryPasswordResponse {
    pub result: Option<CopyEntryPasswordResult>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct InsertEntryResponse {
    pub result: Option<InsertEntryResultDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct GenerateEntryResponse {
    pub result: Option<GenerateEntryResultDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct MutationResponse {
    pub result: Option<MutationResultDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct DeleteEntryResponse {
    pub result: Option<DeleteEntryResultDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct GitCommandResponse {
    pub output: Option<GitCommandOutputDto>,
    pub error: Option<BridgeFailure>,
}

impl From<CoreError> for BridgeFailure {
    fn from(value: CoreError) -> Self {
        match value {
            CoreError::ConfigError(message) => {
                Self::simple(BridgeFailureCategory::ConfigError, message)
            }
            CoreError::StoreError(message) => {
                Self::simple(BridgeFailureCategory::StoreError, message)
            }
            CoreError::PgpError(message) => Self::simple(BridgeFailureCategory::PgpError, message),
            CoreError::GitError(message) => Self::simple(BridgeFailureCategory::GitError, message),
            CoreError::ClipboardError(message) => {
                Self::simple(BridgeFailureCategory::ClipboardError, message)
            }
            CoreError::ValidationError(message) => {
                Self::simple(BridgeFailureCategory::ValidationError, message)
            }
            CoreError::Conflict(conflict) => Self {
                category: BridgeFailureCategory::Conflict,
                message: conflict.to_string(),
                conflict_kind: Some(format!("{:?}", conflict.kind)),
                path: Some(conflict.path),
            },
            CoreError::UnsupportedPlatform(message) => {
                Self::simple(BridgeFailureCategory::UnsupportedPlatform, message)
            }
        }
    }
}

impl BridgeFailure {
    fn simple(category: BridgeFailureCategory, message: String) -> Self {
        Self { category, message, conflict_kind: None, path: None }
    }
}

#[derive(Debug, Clone)]
pub struct LoadConfigRequest {
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct SaveConfigRequest {
    pub path: String,
    pub config_toml: String,
}

#[derive(Debug, Clone)]
pub struct ListStoresRequest {
    pub config_path: Option<String>,
}

#[derive(Debug, Clone)]
pub struct EntryRequest {
    pub root: String,
    pub path: String,
    pub pgp_executable: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ListEntriesRequest {
    pub root: String,
    pub target: Option<String>,
    pub recursive: bool,
}

#[derive(Debug, Clone)]
pub struct InsertEntryRequest {
    pub root: String,
    pub path: String,
    pub content: String,
    pub overwrite: bool,
    pub pgp_executable: String,
}

#[derive(Debug, Clone)]
pub struct GenerateEntryRequest {
    pub root: String,
    pub path: String,
    pub length: u32,
    pub no_symbols: bool,
    pub overwrite: bool,
    pub pgp_executable: String,
}

#[derive(Debug, Clone)]
pub struct EditEntryRequest {
    pub root: String,
    pub path: String,
    pub content: String,
    pub pgp_executable: String,
}

#[derive(Debug, Clone)]
pub struct MoveEntryRequest {
    pub root: String,
    pub from_path: String,
    pub to_path: String,
    pub overwrite: bool,
}

#[derive(Debug, Clone)]
pub struct DeleteEntryRequest {
    pub root: String,
    pub path: String,
    pub recursive: bool,
}

#[derive(Debug, Clone)]
pub struct GitRequest {
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct GitCommitRequest {
    pub root: String,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct GitArgsRequest {
    pub root: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct StoreInfoDto {
    pub id: String,
    pub name: String,
    pub root: String,
    pub is_default: bool,
}

#[derive(Debug, Clone)]
pub struct EntrySummaryDto {
    pub path: String,
    pub name: String,
    pub parent_path: Option<String>,
    pub entry_type: String,
    pub child_count: u32,
}

#[derive(Debug, Clone)]
pub struct ParsedEntryFieldDto {
    pub key: String,
    pub label: String,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct EntrySecretDto {
    pub password: String,
    pub fields: Vec<ParsedEntryFieldDto>,
    pub raw_notes: String,
}

#[derive(Debug, Clone)]
pub struct MutationResultDto {
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct InsertEntryResultDto {
    pub entry_path: String,
    pub overwrote_existing: bool,
}

#[derive(Debug, Clone)]
pub struct GenerateEntryResultDto {
    pub entry_path: String,
    pub password: String,
    pub overwrote_existing: bool,
}

#[derive(Debug, Clone)]
pub struct DeleteEntryResultDto {
    pub deleted_path: String,
    pub deleted_type: String,
}

#[derive(Debug, Clone)]
pub struct GitCommandOutputDto {
    pub command: String,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: Option<i32>,
    pub success: bool,
}

#[derive(Debug, Clone)]
pub struct CopyEntryPasswordResult {
    pub path: String,
    pub password: String,
}

pub async fn load_config(request: LoadConfigRequest) -> ConfigResponse {
    match load_core_config(request.path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .and_then(|config| {
            toml::to_string_pretty(&config)
                .map_err(|error| CoreError::ConfigError(error.to_string()))
        }) {
        Ok(config_toml) => ConfigResponse { config_toml: Some(config_toml), error: None },
        Err(error) => ConfigResponse { config_toml: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn save_config(request: SaveConfigRequest) -> UnitResponse {
    let result = toml::from_str::<ParsConfig>(&request.config_toml)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .and_then(|config| {
            save_core_config(&config, request.path)
                .map_err(|error| CoreError::ConfigError(error.to_string()))
        });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn list_stores(request: ListStoresRequest) -> ListStoresResponse {
    match list_stores_inner(request) {
        Ok(stores) => ListStoresResponse { stores, error: None },
        Err(error) => ListStoresResponse { stores: Vec::new(), error: Some(error) },
    }
}

pub async fn list_entries(request: ListEntriesRequest) -> ListEntriesResponse {
    match gui::list_entries(gui::ListEntriesRequest {
        root: PathBuf::from(request.root),
        target: request.target,
        recursive: request.recursive,
    }) {
        Ok(entries) => ListEntriesResponse {
            entries: entries.into_iter().map(EntrySummaryDto::from).collect(),
            error: None,
        },
        Err(error) => {
            ListEntriesResponse { entries: Vec::new(), error: Some(BridgeFailure::from(error)) }
        }
    }
}

pub async fn read_entry(request: EntryRequest) -> EntrySecretResponse {
    match read_entry_inner(request) {
        Ok(secret) => EntrySecretResponse { secret: Some(secret), error: None },
        Err(error) => EntrySecretResponse { secret: None, error: Some(error) },
    }
}

pub async fn copy_entry_password(request: EntryRequest) -> CopyEntryPasswordResponse {
    let path = request.path.clone();
    match read_entry_inner(request) {
        Ok(secret) => CopyEntryPasswordResponse {
            result: Some(CopyEntryPasswordResult { path, password: secret.password }),
            error: None,
        },
        Err(error) => CopyEntryPasswordResponse { result: None, error: Some(error) },
    }
}

pub async fn insert_entry(request: InsertEntryRequest) -> InsertEntryResponse {
    match gui::insert_entry(gui::InsertEntryRequest {
        entry: match entry_ref(&request.root, &request.path) {
            Ok(entry) => entry,
            Err(error) => return InsertEntryResponse { result: None, error: Some(error) },
        },
        content: request.content,
        overwrite: request.overwrite,
        pgp_executable: request.pgp_executable,
    }) {
        Ok(result) => InsertEntryResponse { result: Some(result.into()), error: None },
        Err(error) => InsertEntryResponse { result: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn generate_entry(request: GenerateEntryRequest) -> GenerateEntryResponse {
    match gui::generate_entry(gui::GenerateEntryRequest {
        entry: match entry_ref(&request.root, &request.path) {
            Ok(entry) => entry,
            Err(error) => return GenerateEntryResponse { result: None, error: Some(error) },
        },
        length: request.length as usize,
        no_symbols: request.no_symbols,
        overwrite: request.overwrite,
        pgp_executable: request.pgp_executable,
    }) {
        Ok(result) => GenerateEntryResponse { result: Some(result.into()), error: None },
        Err(error) => {
            GenerateEntryResponse { result: None, error: Some(BridgeFailure::from(error)) }
        }
    }
}

pub async fn edit_entry(request: EditEntryRequest) -> MutationResponse {
    match gui::edit_entry(gui::EditEntryRequest {
        entry: match entry_ref(&request.root, &request.path) {
            Ok(entry) => entry,
            Err(error) => return MutationResponse { result: None, error: Some(error) },
        },
        content: request.content,
        pgp_executable: request.pgp_executable,
    }) {
        Ok(result) => MutationResponse { result: Some(result.into()), error: None },
        Err(error) => MutationResponse { result: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn move_entry(request: MoveEntryRequest) -> MutationResponse {
    let from = match entry_ref(&request.root, &request.from_path) {
        Ok(entry) => entry,
        Err(error) => return MutationResponse { result: None, error: Some(error) },
    };
    let to = match entry_ref(&request.root, &request.to_path) {
        Ok(entry) => entry,
        Err(error) => return MutationResponse { result: None, error: Some(error) },
    };
    match gui::move_entry(gui::MoveEntryRequest { from, to, overwrite: request.overwrite }) {
        Ok(result) => MutationResponse { result: Some(result.into()), error: None },
        Err(error) => MutationResponse { result: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn delete_entry(request: DeleteEntryRequest) -> DeleteEntryResponse {
    match gui::delete_entry(gui::DeleteEntryRequest {
        entry: match entry_ref(&request.root, &request.path) {
            Ok(entry) => entry,
            Err(error) => return DeleteEntryResponse { result: None, error: Some(error) },
        },
        recursive: request.recursive,
    }) {
        Ok(result) => DeleteEntryResponse { result: Some(result.into()), error: None },
        Err(error) => DeleteEntryResponse { result: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn git_status(request: GitRequest) -> GitCommandResponse {
    run_git_command_response(request.root, vec!["status", "--short", "--branch"])
}

pub async fn git_pull(request: GitRequest) -> GitCommandResponse {
    run_git_command_response(request.root, vec!["pull"])
}

pub async fn git_push(request: GitRequest) -> GitCommandResponse {
    run_git_command_response(request.root, vec!["push"])
}

pub async fn git_commit(request: GitCommitRequest) -> GitCommandResponse {
    run_git_command_response(request.root, vec!["commit", "-m", &request.message])
}

pub async fn run_git_args(request: GitArgsRequest) -> GitCommandResponse {
    match GitOperationRequest::new(PathBuf::from(request.root), request.args)
        .and_then(gui::run_git_args)
    {
        Ok(output) => GitCommandResponse { output: Some(output.into()), error: None },
        Err(error) => GitCommandResponse { output: None, error: Some(BridgeFailure::from(error)) },
    }
}

fn list_stores_inner(request: ListStoresRequest) -> Result<Vec<StoreInfoDto>, BridgeFailure> {
    let config = match request.config_path {
        Some(path) => load_core_config(path)
            .map_err(|error| CoreError::ConfigError(error.to_string()))
            .map_err(BridgeFailure::from)?,
        None => ParsConfig::default(),
    };
    Ok(config
        .path_config
        .repos
        .iter()
        .enumerate()
        .map(|(index, root)| {
            let root_path = PathBuf::from(root);
            let name =
                root_path.file_name().and_then(|name| name.to_str()).unwrap_or("password-store");
            StoreInfo {
                id: StoreId(format!("store-{index}")),
                name: name.to_string(),
                root: root_path.clone(),
                is_default: root_path == PathBuf::from(&config.path_config.default_repo),
            }
        })
        .map(StoreInfoDto::from)
        .collect())
}

fn read_entry_inner(request: EntryRequest) -> Result<EntrySecretDto, BridgeFailure> {
    gui::read_entry(gui::ReadEntryRequest {
        entry: entry_ref(&request.root, &request.path)?,
        pgp_executable: request.pgp_executable.unwrap_or_else(|| "gpg".to_string()),
    })
    .map(EntrySecretDto::from)
    .map_err(BridgeFailure::from)
}

fn entry_ref(root: &str, path: &str) -> Result<EntryRef, BridgeFailure> {
    EntryRef::new(PathBuf::from(root), path).map_err(BridgeFailure::from)
}

fn run_git_command_response(root: String, args: Vec<&str>) -> GitCommandResponse {
    let args = args.into_iter().map(str::to_string).collect::<Vec<_>>();
    match GitOperationRequest::new(PathBuf::from(root), args).and_then(gui::run_git_args) {
        Ok(output) => GitCommandResponse { output: Some(output.into()), error: None },
        Err(error) => GitCommandResponse { output: None, error: Some(BridgeFailure::from(error)) },
    }
}

impl From<StoreInfo> for StoreInfoDto {
    fn from(value: StoreInfo) -> Self {
        Self {
            id: value.id.0,
            name: value.name,
            root: value.root.display().to_string(),
            is_default: value.is_default,
        }
    }
}

impl From<gui::EntrySummary> for EntrySummaryDto {
    fn from(value: gui::EntrySummary) -> Self {
        Self {
            path: value.path,
            name: value.name,
            parent_path: value.parent_path,
            entry_type: format!("{:?}", value.entry_type),
            child_count: u32::try_from(value.child_count).unwrap_or(u32::MAX),
        }
    }
}

impl From<gui::EntrySecret> for EntrySecretDto {
    fn from(value: gui::EntrySecret) -> Self {
        Self {
            password: value.password,
            fields: value.fields.into_iter().map(ParsedEntryFieldDto::from).collect(),
            raw_notes: value.raw_notes,
        }
    }
}

impl From<gui::ParsedEntryField> for ParsedEntryFieldDto {
    fn from(value: gui::ParsedEntryField) -> Self {
        Self { key: value.key, label: value.label, value: value.value }
    }
}

impl From<gui::EntryMutationResult> for MutationResultDto {
    fn from(value: gui::EntryMutationResult) -> Self {
        Self { path: value.path }
    }
}

impl From<gui::InsertEntryResult> for InsertEntryResultDto {
    fn from(value: gui::InsertEntryResult) -> Self {
        Self { entry_path: value.entry_path, overwrote_existing: value.overwrote_existing }
    }
}

impl From<gui::GenerateEntryResult> for GenerateEntryResultDto {
    fn from(value: gui::GenerateEntryResult) -> Self {
        Self {
            entry_path: value.entry_path,
            password: value.password,
            overwrote_existing: value.overwrote_existing,
        }
    }
}

impl From<gui::DeleteEntryResult> for DeleteEntryResultDto {
    fn from(value: gui::DeleteEntryResult) -> Self {
        Self { deleted_path: value.deleted_path, deleted_type: format!("{:?}", value.deleted_type) }
    }
}

impl From<gui::GitCommandOutput> for GitCommandOutputDto {
    fn from(value: gui::GitCommandOutput) -> Self {
        Self {
            command: value.command,
            stdout: value.stdout,
            stderr: value.stderr,
            exit_code: value.exit_code,
            success: value.success,
        }
    }
}
