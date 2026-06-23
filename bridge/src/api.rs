use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use pars_core::config::cli::{
    load_config as load_core_config, save_config as save_core_config, ParsConfig,
};
use pars_core::gui::{
    self, CoreError, EntryRef, GitOperationRequest, KeyExportResult, PgpKeySummary, SshKeySummary,
    StoreId, StoreInfo,
};
use pars_core::key_management::{
    add_pgp_key_to_gpg_id as add_pgp_key_to_gpg_id_core, detect_imported_key_material,
    export_ssh_private_key as export_ssh_private_key_core,
    export_ssh_public_key as export_ssh_public_key_core, generate_ssh_ed25519_key,
    import_ssh_private_key_text as import_ssh_private_key_text_core, list_ssh_keys,
    ImportedKeyKind, PrivateKeyConfirmation,
};
use pars_core::pgp::backend::{KeyGenerationRequest, PgpBackend, SystemGpgBackend};
use secrecy::SecretString;

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
    "add_pgp_key_to_gpg_id",
    "generate_ssh_key",
    "import_ssh_private_key_file",
    "import_ssh_private_key_text",
    "export_ssh_public_key",
    "export_ssh_private_key",
    "open_github_ssh_settings",
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
pub struct AppStateResponse {
    pub state: Option<AppStateDto>,
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
pub struct ListKeysResponse {
    pub keys: Vec<KeyRecordDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct KeyMutationResponse {
    pub key: Option<KeyRecordDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct KeyDetectionResponse {
    pub kind: Option<String>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct KeyExportResponse {
    pub export: Option<KeyExportDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct OpenExternalUrlResponse {
    pub url: Option<String>,
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
pub struct InspectAppStateRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SelectStoreRequest {
    pub config_path: String,
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct CreateLocalStoreRequest {
    pub config_path: String,
    pub name: String,
    pub root: String,
    pub pgp_keys: Vec<String>,
    pub set_default: bool,
    pub initialize_git: bool,
}

#[derive(Debug, Clone)]
pub struct ImportLocalStoreRequest {
    pub config_path: String,
    pub root: String,
    pub set_default: bool,
}

#[derive(Debug, Clone)]
pub struct CloneStoreRequest {
    pub config_path: String,
    pub remote_url: String,
    pub root: String,
    pub set_default: bool,
}

#[derive(Debug, Clone)]
pub struct RemoveStoreRequest {
    pub config_path: String,
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct DeleteLocalStoreRequest {
    pub config_path: String,
    pub root: String,
    pub confirmation: String,
}

#[derive(Debug, Clone)]
pub struct ListKeysRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub ssh_dir: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GeneratePgpKeyRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub name: String,
    pub email: String,
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ImportKeyTextRequest {
    pub config_path: String,
    pub ssh_dir: Option<String>,
    pub name: Option<String>,
    pub armored_text: String,
}

#[derive(Debug, Clone)]
pub struct ImportKeyFileRequest {
    pub config_path: String,
    pub ssh_dir: Option<String>,
    pub name: Option<String>,
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct ExportPgpKeyRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub fingerprint: String,
    pub confirmation: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AddPgpKeyToGpgIdRequest {
    pub root: String,
    pub fingerprint: String,
}

#[derive(Debug, Clone)]
pub struct GenerateSshKeyRequest {
    pub ssh_dir: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct ExportSshKeyRequest {
    pub ssh_dir: String,
    pub name: String,
    pub confirmation: Option<String>,
}

#[derive(Debug, Clone)]
pub struct OpenGithubSshSettingsRequest {}

#[derive(Debug, Clone)]
pub struct AppStateDto {
    pub config_path: String,
    pub config_exists: bool,
    pub selected_store_id: Option<String>,
    pub selected_store_root: Option<String>,
    pub onboarding_state: String,
    pub issues: Vec<String>,
    pub stores: Vec<StoreStatusDto>,
}

#[derive(Debug, Clone)]
pub struct StoreStatusDto {
    pub id: String,
    pub name: String,
    pub root: String,
    pub is_default: bool,
    pub exists: bool,
    pub has_gpg_id: bool,
    pub has_git_remote: bool,
    pub pgp_key_missing: bool,
    pub issues: Vec<String>,
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

#[derive(Debug, Clone)]
pub struct KeyRecordDto {
    pub key_type: String,
    pub name: String,
    pub fingerprint: String,
    pub source: String,
    pub has_private_key: bool,
}

#[derive(Debug, Clone)]
pub struct KeyExportDto {
    pub armored_text: String,
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

pub async fn inspect_app_state(request: InspectAppStateRequest) -> AppStateResponse {
    match inspect_app_state_inner(request) {
        Ok(state) => AppStateResponse { state: Some(state), error: None },
        Err(error) => AppStateResponse { state: None, error: Some(error) },
    }
}

pub async fn select_store(request: SelectStoreRequest) -> UnitResponse {
    UnitResponse { error: select_store_inner(request).err() }
}

pub async fn create_local_store(request: CreateLocalStoreRequest) -> UnitResponse {
    UnitResponse { error: create_local_store_inner(request).err() }
}

pub async fn import_local_store(request: ImportLocalStoreRequest) -> UnitResponse {
    UnitResponse { error: import_local_store_inner(request).err() }
}

pub async fn clone_store(request: CloneStoreRequest) -> UnitResponse {
    UnitResponse { error: clone_store_inner(request).err() }
}

pub async fn remove_store(request: RemoveStoreRequest) -> UnitResponse {
    UnitResponse { error: remove_store_inner(request).err() }
}

pub async fn delete_local_store(request: DeleteLocalStoreRequest) -> UnitResponse {
    UnitResponse { error: delete_local_store_inner(request).err() }
}

pub async fn list_keys(request: ListKeysRequest) -> ListKeysResponse {
    match list_keys_inner(request) {
        Ok(keys) => ListKeysResponse { keys, error: None },
        Err(error) => ListKeysResponse { keys: Vec::new(), error: Some(error) },
    }
}

pub async fn detect_imported_key(request: ImportKeyTextRequest) -> KeyDetectionResponse {
    match detect_imported_key_material(&request.armored_text) {
        Ok(kind) => KeyDetectionResponse { kind: Some(imported_key_kind(kind)), error: None },
        Err(error) => KeyDetectionResponse { kind: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn generate_pgp_key(request: GeneratePgpKeyRequest) -> KeyMutationResponse {
    match pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
        backend
            .generate_key(KeyGenerationRequest {
                name: request.name,
                email: request.email,
                passphrase: request.passphrase.map(SecretString::from),
            })
            .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
    }) {
        Ok(result) => KeyMutationResponse {
            key: Some(KeyRecordDto {
                key_type: "pgp".to_string(),
                name: result.fingerprint.clone(),
                fingerprint: result.fingerprint,
                source: "Generated on device".to_string(),
                has_private_key: result.imported_private_key,
            }),
            error: None,
        },
        Err(error) => KeyMutationResponse { key: None, error: Some(error) },
    }
}

pub async fn import_pgp_public_key(request: ImportKeyTextRequest) -> KeyMutationResponse {
    import_pgp_key_text(request, false)
}

pub async fn import_pgp_private_key_text(request: ImportKeyTextRequest) -> KeyMutationResponse {
    import_pgp_key_text(request, true)
}

pub async fn import_pgp_private_key_file(request: ImportKeyFileRequest) -> KeyMutationResponse {
    match fs::read_to_string(&request.path).map_err(|error| {
        BridgeFailure::from(CoreError::StoreError(format!(
            "failed to read key file {}: {error}",
            request.path
        )))
    }) {
        Ok(armored_text) => import_pgp_key_text(
            ImportKeyTextRequest {
                config_path: request.config_path,
                ssh_dir: request.ssh_dir,
                name: request.name,
                armored_text,
            },
            true,
        ),
        Err(error) => KeyMutationResponse { key: None, error: Some(error) },
    }
}

pub async fn export_pgp_public_key(request: ExportPgpKeyRequest) -> KeyExportResponse {
    match pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
        backend
            .export_public_key(&request.fingerprint)
            .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
    }) {
        Ok(export) => KeyExportResponse { export: Some(export.into()), error: None },
        Err(error) => KeyExportResponse { export: None, error: Some(error) },
    }
}

pub async fn export_pgp_private_key(request: ExportPgpKeyRequest) -> KeyExportResponse {
    let expected = format!("EXPORT PRIVATE KEY {}", request.fingerprint);
    if request.confirmation.as_deref() != Some(expected.as_str()) {
        return KeyExportResponse {
            export: None,
            error: Some(BridgeFailure::from(CoreError::ValidationError(format!(
                "private key export requires confirmation phrase: {expected}"
            )))),
        };
    }

    match pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
        backend
            .export_private_key(&request.fingerprint, None)
            .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
    }) {
        Ok(export) => KeyExportResponse { export: Some(export.into()), error: None },
        Err(error) => KeyExportResponse { export: None, error: Some(error) },
    }
}

pub async fn add_pgp_key_to_gpg_id(request: AddPgpKeyToGpgIdRequest) -> UnitResponse {
    UnitResponse {
        error: add_pgp_key_to_gpg_id_core(Path::new(&request.root), &request.fingerprint)
            .err()
            .map(BridgeFailure::from),
    }
}

pub async fn generate_ssh_key(request: GenerateSshKeyRequest) -> KeyMutationResponse {
    match generate_ssh_ed25519_key(Path::new(&request.ssh_dir), &request.name) {
        Ok(key) => KeyMutationResponse { key: Some(key.into()), error: None },
        Err(error) => KeyMutationResponse { key: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn import_ssh_private_key_text(request: ImportKeyTextRequest) -> KeyMutationResponse {
    let Some(name) = request.name else {
        return KeyMutationResponse {
            key: None,
            error: Some(BridgeFailure::from(CoreError::ValidationError(
                "SSH private key import requires a key name".to_string(),
            ))),
        };
    };
    let ssh_dir = request.ssh_dir.map(PathBuf::from).unwrap_or_else(default_ssh_dir);
    match import_ssh_private_key_text_core(&ssh_dir, &name, &request.armored_text) {
        Ok(key) => KeyMutationResponse { key: Some(key.into()), error: None },
        Err(error) => KeyMutationResponse { key: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn import_ssh_private_key_file(request: ImportKeyFileRequest) -> KeyMutationResponse {
    match fs::read_to_string(&request.path).map_err(|error| {
        BridgeFailure::from(CoreError::StoreError(format!(
            "failed to read key file {}: {error}",
            request.path
        )))
    }) {
        Ok(armored_text) => {
            import_ssh_private_key_text(ImportKeyTextRequest {
                config_path: request.config_path,
                ssh_dir: request.ssh_dir,
                name: request.name,
                armored_text,
            })
            .await
        }
        Err(error) => KeyMutationResponse { key: None, error: Some(error) },
    }
}

pub async fn export_ssh_public_key(request: ExportSshKeyRequest) -> KeyExportResponse {
    match export_ssh_public_key_core(Path::new(&request.ssh_dir), &request.name) {
        Ok(export) => KeyExportResponse { export: Some(export.into()), error: None },
        Err(error) => KeyExportResponse { export: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn export_ssh_private_key(request: ExportSshKeyRequest) -> KeyExportResponse {
    let confirmation = PrivateKeyConfirmation::new(
        &request.name,
        request.confirmation.clone().unwrap_or_default(),
    );
    match export_ssh_private_key_core(Path::new(&request.ssh_dir), &request.name, confirmation) {
        Ok(export) => KeyExportResponse { export: Some(export.into()), error: None },
        Err(error) => KeyExportResponse { export: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn open_github_ssh_settings(
    _request: OpenGithubSshSettingsRequest,
) -> OpenExternalUrlResponse {
    OpenExternalUrlResponse {
        url: Some("https://github.com/settings/keys".to_string()),
        error: None,
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

fn list_keys_inner(request: ListKeysRequest) -> Result<Vec<KeyRecordDto>, BridgeFailure> {
    let mut keys = Vec::new();
    if let Ok(backend) = pgp_backend(&request.config_path, request.pgp_executable.as_deref()) {
        if let Ok(pgp_keys) = backend.list_keys() {
            keys.extend(pgp_keys.into_iter().map(KeyRecordDto::from));
        }
    }

    let ssh_dir = request.ssh_dir.map(PathBuf::from).unwrap_or_else(default_ssh_dir);
    keys.extend(
        list_ssh_keys(&ssh_dir).map_err(BridgeFailure::from)?.into_iter().map(KeyRecordDto::from),
    );
    Ok(keys)
}

fn import_pgp_key_text(request: ImportKeyTextRequest, private_key: bool) -> KeyMutationResponse {
    let detected = detect_imported_key_material(&request.armored_text);
    let expected_kind =
        if private_key { ImportedKeyKind::PgpPrivate } else { ImportedKeyKind::PgpPublic };
    match detected {
        Ok(kind) if kind == expected_kind => {}
        Ok(_) => {
            return KeyMutationResponse {
                key: None,
                error: Some(BridgeFailure::from(CoreError::ValidationError(
                    "pasted key type does not match the requested PGP import".to_string(),
                ))),
            };
        }
        Err(error) => {
            return KeyMutationResponse { key: None, error: Some(BridgeFailure::from(error)) }
        }
    }

    match pgp_backend(&request.config_path, None).and_then(|backend| {
        if private_key {
            backend
                .import_private_key(&SecretString::from(request.armored_text))
                .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
        } else {
            backend
                .import_public_key(&request.armored_text)
                .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
        }
    }) {
        Ok(result) => KeyMutationResponse {
            key: Some(KeyRecordDto {
                key_type: "pgp".to_string(),
                name: request.name.unwrap_or_else(|| result.fingerprint.clone()),
                fingerprint: result.fingerprint,
                source: if private_key { "Imported private key" } else { "Imported public key" }
                    .to_string(),
                has_private_key: result.imported_private_key,
            }),
            error: None,
        },
        Err(error) => KeyMutationResponse { key: None, error: Some(error) },
    }
}

fn pgp_backend(
    config_path: &str,
    pgp_executable: Option<&str>,
) -> Result<SystemGpgBackend, BridgeFailure> {
    let mut config = if Path::new(config_path).is_file() {
        load_core_config(config_path)
            .map_err(|error| CoreError::ConfigError(error.to_string()))
            .map_err(BridgeFailure::from)?
    } else {
        ParsConfig::default()
    };
    if let Some(executable) = pgp_executable {
        config.pgp_config.system_gpg_path = Some(executable.to_string());
    }
    SystemGpgBackend::from_config(&config.pgp_config)
        .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
}

fn imported_key_kind(kind: ImportedKeyKind) -> String {
    match kind {
        ImportedKeyKind::PgpPublic => "pgp_public",
        ImportedKeyKind::PgpPrivate => "pgp_private",
        ImportedKeyKind::SshPrivate => "ssh_private",
    }
    .to_string()
}

fn default_ssh_dir() -> PathBuf {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .map(|home| home.join(".ssh"))
        .unwrap_or_else(|| PathBuf::from(".ssh"))
}

fn inspect_app_state_inner(request: InspectAppStateRequest) -> Result<AppStateDto, BridgeFailure> {
    let config_path = PathBuf::from(&request.config_path);
    let config_exists = config_path.is_file();
    if !config_exists {
        return Ok(AppStateDto {
            config_path: request.config_path,
            config_exists: false,
            selected_store_id: None,
            selected_store_root: None,
            onboarding_state: "no_config".to_string(),
            issues: vec!["no_config".to_string()],
            stores: Vec::new(),
        });
    }

    let config = load_core_config(&config_path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .map_err(BridgeFailure::from)?;
    let default_repo = config.path_config.default_repo.clone();
    let stores = config
        .path_config
        .repos
        .iter()
        .enumerate()
        .map(|(index, root)| {
            inspect_store(index, root, root == &default_repo, request.pgp_executable.as_deref())
        })
        .collect::<Vec<_>>();
    let selected = stores.iter().find(|store| store.is_default).or_else(|| stores.first());
    let issues = stores.iter().flat_map(|store| store.issues.iter().cloned()).collect::<Vec<_>>();
    let onboarding_state = onboarding_state(&stores, &issues);

    Ok(AppStateDto {
        config_path: request.config_path,
        config_exists,
        selected_store_id: selected.map(|store| store.id.clone()),
        selected_store_root: selected.map(|store| store.root.clone()),
        onboarding_state,
        issues,
        stores,
    })
}

fn inspect_store(
    index: usize,
    root: &str,
    is_default: bool,
    pgp_executable: Option<&str>,
) -> StoreStatusDto {
    let root_path = PathBuf::from(root);
    let name = store_name(&root_path);
    let exists = root_path.is_dir();
    let gpg_id_path = root_path.join(".gpg-id");
    let has_gpg_id = gpg_id_path.is_file();
    let has_git_remote = exists && git_remote_exists(&root_path);
    let pgp_key_missing = has_gpg_id && pgp_key_missing(&gpg_id_path, pgp_executable);
    let mut issues = Vec::new();

    if !exists {
        issues.push("store_missing".to_string());
    }
    if exists && !has_gpg_id {
        issues.push("missing_gpg_id".to_string());
    }
    if exists && !has_git_remote {
        issues.push("git_remote_missing".to_string());
    }
    if exists && pgp_key_missing {
        issues.push("pgp_key_missing".to_string());
    }

    StoreStatusDto {
        id: format!("store-{index}"),
        name,
        root: root.to_string(),
        is_default,
        exists,
        has_gpg_id,
        has_git_remote,
        pgp_key_missing,
        issues,
    }
}

fn onboarding_state(stores: &[StoreStatusDto], issues: &[String]) -> String {
    if stores.is_empty() {
        return "store_missing".to_string();
    }
    for state in ["store_missing", "missing_gpg_id", "git_remote_missing", "pgp_key_missing"] {
        if issues.iter().any(|issue| issue == state) {
            return state.to_string();
        }
    }
    "ready".to_string()
}

fn select_store_inner(request: SelectStoreRequest) -> Result<(), BridgeFailure> {
    let mut config = load_config_for_mutation(&request.config_path)?;
    let root = normalize_store_root(&request.root)?;
    if !config.path_config.repos.iter().any(|repo| repo == &root) {
        return Err(BridgeFailure::from(CoreError::ValidationError(format!(
            "store is not configured: {root}"
        ))));
    }
    config.path_config.default_repo = root;
    save_config_for_mutation(&config, &request.config_path)
}

fn create_local_store_inner(request: CreateLocalStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let keys = normalized_keys(request.pgp_keys)?;
    fs::create_dir_all(&root).map_err(store_failure)?;
    fs::write(Path::new(&root).join(".gpg-id"), keys.join("\n")).map_err(store_failure)?;
    if request.initialize_git && !Path::new(&root).join(".git").exists() {
        run_git(Path::new(&root), &["init"])?;
    }

    let mut config = load_config_for_mutation(&request.config_path)?;
    add_store_to_config(&mut config, &root, request.set_default);
    save_config_for_mutation(&config, &request.config_path)
}

fn import_local_store_inner(request: ImportLocalStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    if !Path::new(&root).is_dir() {
        return Err(BridgeFailure::from(CoreError::StoreError(format!(
            "password store root does not exist: {root}"
        ))));
    }
    let mut config = load_config_for_mutation(&request.config_path)?;
    add_store_to_config(&mut config, &root, request.set_default);
    save_config_for_mutation(&config, &request.config_path)
}

fn clone_store_inner(request: CloneStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let root_path = PathBuf::from(&root);
    if root_path.exists() {
        return Err(BridgeFailure::from(CoreError::Conflict(gui::EntryConflict {
            kind: gui::EntryConflictKind::EntryAlreadyExists,
            path: root,
        })));
    }
    if let Some(parent) = root_path.parent() {
        fs::create_dir_all(parent).map_err(store_failure)?;
    }
    let output = Command::new("git")
        .args(["clone", &request.remote_url, &root_path.display().to_string()])
        .output()
        .map_err(|error| BridgeFailure::from(CoreError::GitError(error.to_string())))?;
    if !output.status.success() {
        return Err(BridgeFailure::from(CoreError::GitError(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        )));
    }
    let mut config = load_config_for_mutation(&request.config_path)?;
    add_store_to_config(&mut config, &root_path.display().to_string(), request.set_default);
    save_config_for_mutation(&config, &request.config_path)
}

fn remove_store_inner(request: RemoveStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let mut config = load_config_for_mutation(&request.config_path)?;
    config.path_config.repos.retain(|repo| repo != &root);
    if config.path_config.default_repo == root {
        config.path_config.default_repo =
            config.path_config.repos.first().cloned().unwrap_or_default();
    }
    save_config_for_mutation(&config, &request.config_path)
}

fn delete_local_store_inner(request: DeleteLocalStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    if request.confirmation != root {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "delete confirmation must match the full store root".to_string(),
        )));
    }
    let mut config = load_config_for_mutation(&request.config_path)?;
    if !config.path_config.repos.iter().any(|repo| repo == &root) {
        return Err(BridgeFailure::from(CoreError::ValidationError(format!(
            "refusing to delete unconfigured store: {root}"
        ))));
    }
    let root_path = PathBuf::from(&root);
    if !root_path.is_dir() {
        return Err(BridgeFailure::from(CoreError::StoreError(format!(
            "password store root does not exist: {root}"
        ))));
    }
    if root_path.parent().is_none() || root_path == Path::new("/") {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "refusing to delete filesystem root".to_string(),
        )));
    }

    config.path_config.repos.retain(|repo| repo != &root);
    if config.path_config.default_repo == root {
        config.path_config.default_repo =
            config.path_config.repos.first().cloned().unwrap_or_default();
    }
    save_config_for_mutation(&config, &request.config_path)?;
    fs::remove_dir_all(root_path).map_err(store_failure)
}

fn load_config_for_mutation(config_path: &str) -> Result<ParsConfig, BridgeFailure> {
    let path = PathBuf::from(config_path);
    if path.is_file() {
        return load_core_config(path)
            .map_err(|error| CoreError::ConfigError(error.to_string()))
            .map_err(BridgeFailure::from);
    }

    let mut config = ParsConfig::default();
    config.path_config.repos.clear();
    config.path_config.default_repo.clear();
    Ok(config)
}

fn save_config_for_mutation(config: &ParsConfig, config_path: &str) -> Result<(), BridgeFailure> {
    let path = PathBuf::from(config_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(store_failure)?;
    }
    save_core_config(config, path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .map_err(BridgeFailure::from)
}

fn add_store_to_config(config: &mut ParsConfig, root: &str, set_default: bool) {
    if !config.path_config.repos.iter().any(|repo| repo == root) {
        config.path_config.repos.push(root.to_string());
    }
    if set_default || config.path_config.default_repo.is_empty() {
        config.path_config.default_repo = root.to_string();
    }
}

fn normalize_store_root(root: &str) -> Result<String, BridgeFailure> {
    let trimmed = root.trim();
    if trimmed.is_empty() {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "store root cannot be empty".to_string(),
        )));
    }
    if trimmed.contains('\0') {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "store root cannot contain NUL bytes".to_string(),
        )));
    }
    Ok(PathBuf::from(trimmed).display().to_string())
}

fn normalized_keys(keys: Vec<String>) -> Result<Vec<String>, BridgeFailure> {
    let keys = keys
        .into_iter()
        .map(|key| key.trim().to_string())
        .filter(|key| !key.is_empty())
        .collect::<Vec<_>>();
    if keys.is_empty() {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "at least one PGP key is required".to_string(),
        )));
    }
    Ok(keys)
}

fn store_name(root: &Path) -> String {
    root.file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("password-store")
        .to_string()
}

fn git_remote_exists(root: &Path) -> bool {
    let Ok(output) = Command::new("git").arg("remote").current_dir(root).output() else {
        return false;
    };
    output.status.success() && !String::from_utf8_lossy(&output.stdout).trim().is_empty()
}

fn pgp_key_missing(gpg_id_path: &Path, pgp_executable: Option<&str>) -> bool {
    let Ok(content) = fs::read_to_string(gpg_id_path) else {
        return true;
    };
    let keys = content.lines().map(str::trim).filter(|line| !line.is_empty()).collect::<Vec<_>>();
    if keys.is_empty() {
        return true;
    }
    let Some(executable) = pgp_executable else {
        return false;
    };
    keys.iter().any(|key| {
        Command::new(executable)
            .args(["--list-secret-keys", key])
            .output()
            .map(|output| !output.status.success())
            .unwrap_or(true)
    })
}

fn run_git(root: &Path, args: &[&str]) -> Result<(), BridgeFailure> {
    let output = Command::new("git")
        .args(args)
        .current_dir(root)
        .output()
        .map_err(|error| BridgeFailure::from(CoreError::GitError(error.to_string())))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(BridgeFailure::from(CoreError::GitError(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        )))
    }
}

fn store_failure(error: std::io::Error) -> BridgeFailure {
    BridgeFailure::from(CoreError::StoreError(error.to_string()))
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

impl From<PgpKeySummary> for KeyRecordDto {
    fn from(value: PgpKeySummary) -> Self {
        Self {
            key_type: "pgp".to_string(),
            name: value.identity,
            fingerprint: value.fingerprint,
            source: "GnuPG keyring".to_string(),
            has_private_key: value.has_private_key,
        }
    }
}

impl From<SshKeySummary> for KeyRecordDto {
    fn from(value: SshKeySummary) -> Self {
        Self {
            key_type: "ssh".to_string(),
            name: value.name,
            fingerprint: value.fingerprint,
            source: "SSH key directory".to_string(),
            has_private_key: value.has_private_key,
        }
    }
}

impl From<KeyExportResult> for KeyExportDto {
    fn from(value: KeyExportResult) -> Self {
        Self { armored_text: value.armored_text }
    }
}
