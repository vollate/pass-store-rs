use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use pars_core::autofill::{
    self, AutofillCredential, AutofillCredentialRequest as CoreAutofillCredentialRequest,
    AutofillEntryMetadata, AutofillQueryRequest as CoreAutofillQueryRequest,
};
use pars_core::config::cli::{
    load_config as load_core_config, save_config as save_core_config, ParsConfig, PgpBackendKind,
};
use pars_core::gui::{
    self, CoreError, EntryRef, GitOperationRequest, KeyExportResult, PgpKeySummary, SshKeySummary,
    StoreId, StoreInfo,
};
use pars_core::key_management::{
    add_pgp_key_to_gpg_id as add_pgp_key_to_gpg_id_core, delete_ssh_key as delete_ssh_key_core,
    detect_imported_key_material, export_ssh_private_key as export_ssh_private_key_core,
    export_ssh_public_key as export_ssh_public_key_core, generate_ssh_ed25519_key,
    import_ssh_private_key_text as import_ssh_private_key_text_core, list_ssh_keys,
    ImportedKeyKind, PrivateKeyConfirmation,
};
use pars_core::pgp::backend::{
    KeyGenerationRequest, PgpBackend, PgpBackendError, PgpKeyDeletionResult, SystemGpgBackend,
};
use pars_core::pgp::import::{
    import_pgp_key_file as import_pgp_key_file_core,
    import_pgp_key_text as import_pgp_key_text_core, inspect_pgp_key_bytes,
    inspect_pgp_key_file as inspect_pgp_key_file_core, PgpImportError, PgpImportInspection,
    PgpImportOutcome, PgpKeyMaterialKind,
};
use pars_core::pgp::rpgp_backend::RpgpBackend;
use secrecy::SecretString;

pub const SUPPORTED_METHODS: &[&str] = &[
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
    /// Set only for PGP import failures, so Flutter can branch on the reason rather than the text.
    pub pgp_import_kind: Option<PgpImportFailureKind>,
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
pub struct AutofillCandidatesResponse {
    pub candidates: Vec<AutofillCandidateDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct AutofillCredentialResponse {
    pub credential: Option<AutofillCredentialDto>,
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
                pgp_import_kind: None,
            },
            CoreError::UnsupportedPlatform(message) => {
                Self::simple(BridgeFailureCategory::UnsupportedPlatform, message)
            }
        }
    }
}

impl From<PgpImportError> for BridgeFailure {
    fn from(value: PgpImportError) -> Self {
        let kind = match value {
            PgpImportError::UnsupportedMaterial(_) => PgpImportFailureKind::UnsupportedMaterial,
            PgpImportError::KindMismatch { .. } => PgpImportFailureKind::KindMismatch,
            PgpImportError::PassphraseRequired => PgpImportFailureKind::PassphraseRequired,
            PgpImportError::IncorrectPassphrase => PgpImportFailureKind::IncorrectPassphrase,
            PgpImportError::UnsupportedProtection => PgpImportFailureKind::UnsupportedProtection,
            PgpImportError::ReprotectionFailed => PgpImportFailureKind::ReprotectionFailed,
            PgpImportError::Backend(_) => PgpImportFailureKind::BackendError,
        };
        // `Display` on the core error is already sanitized: no passphrase, no key material.
        let category = match value {
            PgpImportError::Backend(_) | PgpImportError::ReprotectionFailed => {
                BridgeFailureCategory::PgpError
            }
            _ => BridgeFailureCategory::ValidationError,
        };
        Self {
            category,
            message: value.to_string(),
            conflict_kind: None,
            path: None,
            pgp_import_kind: Some(kind),
        }
    }
}

impl From<&PgpImportInspection> for PgpKeyInspectionDto {
    fn from(value: &PgpImportInspection) -> Self {
        Self {
            kind: match value.kind {
                PgpKeyMaterialKind::Public => PgpKeyKindDto::Public,
                PgpKeyMaterialKind::Private => PgpKeyKindDto::Private,
            },
            fingerprint: value.fingerprint.clone(),
            identity: value.identity.clone(),
            has_private_key: value.has_private_key,
            requires_passphrase: value.requires_passphrase,
            armored: value.armored,
        }
    }
}

impl From<PgpKeyDeletionResult> for PgpKeyDeletionResultDto {
    fn from(value: PgpKeyDeletionResult) -> Self {
        Self {
            fingerprint: value.fingerprint,
            had_private_key: value.had_private_key,
            private_key_absent: value.private_key_absent,
            public_key_absent: value.public_key_absent,
        }
    }
}

impl BridgeFailure {
    fn simple(category: BridgeFailureCategory, message: String) -> Self {
        Self { category, message, conflict_kind: None, path: None, pgp_import_kind: None }
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
pub struct ConfigurePgpBackendRequest {
    pub config_path: String,
    pub backend: String,
    pub keyring_home: Option<String>,
    pub pgp_executable: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ListStoresRequest {
    pub config_path: Option<String>,
}

#[derive(Debug, Clone)]
pub struct EntryRequest {
    pub config_path: String,
    pub root: String,
    pub path: String,
    pub pgp_executable: Option<String>,
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ListEntriesRequest {
    pub root: String,
    pub target: Option<String>,
    pub recursive: bool,
}

#[derive(Debug, Clone)]
pub struct InsertEntryRequest {
    pub config_path: String,
    pub root: String,
    pub path: String,
    pub content: String,
    pub overwrite: bool,
    pub pgp_executable: String,
}

#[derive(Debug, Clone)]
pub struct GenerateEntryRequest {
    pub config_path: String,
    pub root: String,
    pub path: String,
    pub length: u32,
    pub no_symbols: bool,
    pub overwrite: bool,
    pub pgp_executable: String,
}

#[derive(Debug, Clone)]
pub struct EditEntryRequest {
    pub config_path: String,
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
    pub pgp_executable: Option<String>,
    pub ssh_dir: Option<String>,
    pub name: Option<String>,
    pub armored_text: String,
}

#[derive(Debug, Clone)]
pub struct ImportKeyFileRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub ssh_dir: Option<String>,
    pub name: Option<String>,
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct InspectPgpKeyTextRequest {
    pub armored_text: String,
}

#[derive(Debug, Clone)]
pub struct InspectPgpKeyFileRequest {
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct ImportPgpKeyTextRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub armored_text: String,
    /// Required only when inspection reports `requires_passphrase`.
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ImportPgpKeyFileRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub path: String,
    /// Required only when inspection reports `requires_passphrase`.
    pub passphrase: Option<String>,
}

/// What inspection found in the supplied material. Carries no key bytes.
#[derive(Debug, Clone)]
pub struct PgpKeyInspectionDto {
    pub kind: PgpKeyKindDto,
    pub fingerprint: String,
    pub identity: String,
    pub has_private_key: bool,
    pub requires_passphrase: bool,
    pub armored: bool,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum PgpKeyKindDto {
    Public,
    Private,
}

/// Why a PGP import failed, so Flutter can branch without matching on message text.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum PgpImportFailureKind {
    UnsupportedMaterial,
    KindMismatch,
    PassphraseRequired,
    IncorrectPassphrase,
    UnsupportedProtection,
    ReprotectionFailed,
    BackendError,
}

#[derive(Debug, Clone)]
pub struct PgpKeyInspectionResponse {
    pub inspection: Option<PgpKeyInspectionDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct PgpKeyImportResponse {
    pub inspection: Option<PgpKeyInspectionDto>,
    pub key: Option<KeyRecordDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct PreparePgpPrivateKeyRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub fingerprint: String,
    pub passphrase: String,
}

#[derive(Debug, Clone)]
pub struct PreparePgpPrivateKeyResponse {
    pub fingerprint: Option<String>,
    pub migrated: bool,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct ExportPgpKeyRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub fingerprint: String,
    pub confirmation: Option<String>,
}

#[derive(Debug, Clone)]
pub struct DeletePgpKeyRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
    pub fingerprint: String,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum PgpKeyDeletionFailureKind {
    PrivateRemovalFailed,
    PublicCleanupFailed,
}

#[derive(Debug, Clone)]
pub struct PgpKeyDeletionResultDto {
    pub fingerprint: String,
    pub had_private_key: bool,
    pub private_key_absent: bool,
    pub public_key_absent: bool,
}

#[derive(Debug, Clone)]
pub struct DeletePgpKeyResponse {
    pub result: Option<PgpKeyDeletionResultDto>,
    pub failure_kind: Option<PgpKeyDeletionFailureKind>,
    pub error: Option<BridgeFailure>,
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
pub struct DeleteSshKeyRequest {
    pub ssh_dir: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct OpenGithubSshSettingsRequest {}

#[derive(Debug, Clone)]
pub struct RebuildAutofillIndexRequest {
    pub index_path: String,
    pub store_id: String,
    pub store_name: String,
    pub root: String,
    pub entries: Vec<AutofillEntryMetadataDto>,
}

#[derive(Debug, Clone)]
pub struct AutofillEntryMetadataDto {
    pub path: String,
    pub is_favorite: bool,
    pub recent_rank: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct UpsertAutofillIndexEntryRequest {
    pub index_path: String,
    pub entry: AutofillEntryMetadataDto,
}

#[derive(Debug, Clone)]
pub struct MoveAutofillIndexEntryRequest {
    pub index_path: String,
    pub old_path: String,
    pub new_path: String,
    pub recursive: bool,
}

#[derive(Debug, Clone)]
pub struct RemoveAutofillIndexEntryRequest {
    pub index_path: String,
    pub path: String,
    pub recursive: bool,
}

#[derive(Debug, Clone)]
pub struct PatchAutofillIndexRankingRequest {
    pub index_path: String,
    pub entries: Vec<AutofillEntryMetadataDto>,
}

#[derive(Debug, Clone)]
pub struct ReconcileAutofillIndexRequest {
    pub index_path: String,
    pub store_id: String,
    pub store_name: String,
    pub root: String,
    pub entries: Vec<AutofillEntryMetadataDto>,
}

#[derive(Debug, Clone)]
pub struct EnrichAutofillIndexWebsitesRequest {
    pub config_path: String,
    pub index_path: String,
    pub root: String,
    pub pgp_executable: Option<String>,
    pub passphrase: Option<String>,
    pub paths: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct ClearAutofillIndexWebsitesRequest {
    pub index_path: String,
    pub paths: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct AutofillQueryRequest {
    pub index_path: String,
    pub website: Option<String>,
    pub app_name: Option<String>,
    pub query: Option<String>,
    pub limit: u32,
}

#[derive(Debug, Clone)]
pub struct AutofillCredentialRequest {
    pub config_path: String,
    pub index_path: String,
    pub root: String,
    pub path: String,
    pub pgp_executable: Option<String>,
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ClearAutofillIndexRequest {
    pub index_path: String,
}

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

#[derive(Debug, Clone)]
pub struct AutofillCandidateDto {
    pub path: String,
    pub display_name: String,
    pub username: String,
    pub match_kind: String,
    pub match_value: String,
    pub score: i32,
    pub is_favorite: bool,
    pub recent_rank: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct AutofillCredentialDto {
    pub path: String,
    pub username: String,
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

pub async fn configure_pgp_backend(request: ConfigurePgpBackendRequest) -> UnitResponse {
    UnitResponse { error: configure_pgp_backend_inner(request).err() }
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

pub async fn rebuild_autofill_index(request: RebuildAutofillIndexRequest) -> UnitResponse {
    let result = autofill::rebuild_autofill_index(autofill::RebuildAutofillIndexRequest {
        index_path: PathBuf::from(request.index_path),
        store_id: request.store_id,
        store_name: request.store_name,
        store_root: PathBuf::from(request.root),
        entries: request.entries.into_iter().map(AutofillEntryMetadata::from).collect(),
    });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn upsert_autofill_index_entry(request: UpsertAutofillIndexEntryRequest) -> UnitResponse {
    let result = autofill::upsert_autofill_index_entry(autofill::UpsertAutofillIndexEntryRequest {
        index_path: PathBuf::from(request.index_path),
        entry: request.entry.into(),
    });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn move_autofill_index_entry(request: MoveAutofillIndexEntryRequest) -> UnitResponse {
    let result = autofill::move_autofill_index_entry(autofill::MoveAutofillIndexEntryRequest {
        index_path: PathBuf::from(request.index_path),
        old_path: request.old_path,
        new_path: request.new_path,
        recursive: request.recursive,
    });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn remove_autofill_index_entry(request: RemoveAutofillIndexEntryRequest) -> UnitResponse {
    let result = autofill::remove_autofill_index_entry(autofill::RemoveAutofillIndexEntryRequest {
        index_path: PathBuf::from(request.index_path),
        path: request.path,
        recursive: request.recursive,
    });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn patch_autofill_index_ranking(
    request: PatchAutofillIndexRankingRequest,
) -> UnitResponse {
    let result =
        autofill::patch_autofill_index_ranking(autofill::PatchAutofillIndexRankingRequest {
            index_path: PathBuf::from(request.index_path),
            entries: request.entries.into_iter().map(AutofillEntryMetadata::from).collect(),
        });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn reconcile_autofill_index(request: ReconcileAutofillIndexRequest) -> UnitResponse {
    let result = autofill::reconcile_autofill_index(autofill::ReconcileAutofillIndexRequest {
        index_path: PathBuf::from(request.index_path),
        store_id: request.store_id,
        store_name: request.store_name,
        store_root: PathBuf::from(request.root),
        entries: request.entries.into_iter().map(AutofillEntryMetadata::from).collect(),
    });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn enrich_autofill_index_websites(
    request: EnrichAutofillIndexWebsitesRequest,
) -> UnitResponse {
    let backend = match pgp_backend(&request.config_path, request.pgp_executable.as_deref()) {
        Ok(backend) => backend,
        Err(error) => return UnitResponse { error: Some(error) },
    };
    let result = autofill::enrich_autofill_index_websites_with_backend(
        autofill::EnrichAutofillIndexWebsitesRequest {
            index_path: PathBuf::from(request.index_path),
            store_root: PathBuf::from(request.root),
            pgp_executable: request.pgp_executable.unwrap_or_default(),
            passphrase: request.passphrase,
            paths: request.paths,
        },
        backend.as_ref(),
    );
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn clear_autofill_index_websites(
    request: ClearAutofillIndexWebsitesRequest,
) -> UnitResponse {
    let result =
        autofill::clear_autofill_index_websites(autofill::ClearAutofillIndexWebsitesRequest {
            index_path: PathBuf::from(request.index_path),
            paths: request.paths,
        });
    UnitResponse { error: result.err().map(BridgeFailure::from) }
}

pub async fn query_autofill_candidates(
    request: AutofillQueryRequest,
) -> AutofillCandidatesResponse {
    match autofill::query_autofill_candidates(CoreAutofillQueryRequest {
        index_path: PathBuf::from(request.index_path),
        website: request.website,
        app_name: request.app_name,
        query: request.query,
        limit: request.limit as usize,
    }) {
        Ok(candidates) => AutofillCandidatesResponse {
            candidates: candidates.into_iter().map(AutofillCandidateDto::from).collect(),
            error: None,
        },
        Err(error) => AutofillCandidatesResponse {
            candidates: Vec::new(),
            error: Some(BridgeFailure::from(error)),
        },
    }
}

pub async fn resolve_autofill_credential(
    request: AutofillCredentialRequest,
) -> AutofillCredentialResponse {
    let backend = match pgp_backend(&request.config_path, request.pgp_executable.as_deref()) {
        Ok(backend) => backend,
        Err(error) => {
            return AutofillCredentialResponse { credential: None, error: Some(error) };
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
        Ok(credential) => AutofillCredentialResponse {
            credential: Some(AutofillCredentialDto::from(credential)),
            error: None,
        },
        Err(error) => {
            AutofillCredentialResponse { credential: None, error: Some(BridgeFailure::from(error)) }
        }
    }
}

pub async fn clear_autofill_index(request: ClearAutofillIndexRequest) -> UnitResponse {
    UnitResponse {
        error: autofill::clear_autofill_index(Path::new(&request.index_path))
            .err()
            .map(BridgeFailure::from),
    }
}

pub async fn insert_entry(request: InsertEntryRequest) -> InsertEntryResponse {
    let backend = match pgp_backend(&request.config_path, Some(&request.pgp_executable)) {
        Ok(backend) => backend,
        Err(error) => return InsertEntryResponse { result: None, error: Some(error) },
    };
    match gui::insert_entry_with_backend(
        gui::InsertEntryRequest {
            entry: match entry_ref(&request.root, &request.path) {
                Ok(entry) => entry,
                Err(error) => return InsertEntryResponse { result: None, error: Some(error) },
            },
            content: request.content,
            overwrite: request.overwrite,
            pgp_executable: request.pgp_executable,
        },
        backend.as_ref(),
    ) {
        Ok(result) => InsertEntryResponse { result: Some(result.into()), error: None },
        Err(error) => InsertEntryResponse { result: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn generate_entry(request: GenerateEntryRequest) -> GenerateEntryResponse {
    let backend = match pgp_backend(&request.config_path, Some(&request.pgp_executable)) {
        Ok(backend) => backend,
        Err(error) => return GenerateEntryResponse { result: None, error: Some(error) },
    };
    match gui::generate_entry_with_backend(
        gui::GenerateEntryRequest {
            entry: match entry_ref(&request.root, &request.path) {
                Ok(entry) => entry,
                Err(error) => return GenerateEntryResponse { result: None, error: Some(error) },
            },
            length: request.length as usize,
            no_symbols: request.no_symbols,
            overwrite: request.overwrite,
            pgp_executable: request.pgp_executable,
        },
        backend.as_ref(),
    ) {
        Ok(result) => GenerateEntryResponse { result: Some(result.into()), error: None },
        Err(error) => {
            GenerateEntryResponse { result: None, error: Some(BridgeFailure::from(error)) }
        }
    }
}

pub async fn edit_entry(request: EditEntryRequest) -> MutationResponse {
    let backend = match pgp_backend(&request.config_path, Some(&request.pgp_executable)) {
        Ok(backend) => backend,
        Err(error) => return MutationResponse { result: None, error: Some(error) },
    };
    match gui::edit_entry_with_backend(
        gui::EditEntryRequest {
            entry: match entry_ref(&request.root, &request.path) {
                Ok(entry) => entry,
                Err(error) => return MutationResponse { result: None, error: Some(error) },
            },
            content: request.content,
            pgp_executable: request.pgp_executable,
        },
        backend.as_ref(),
    ) {
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

/// Inspects pasted PGP key material without touching any keyring.
pub async fn inspect_pgp_key_text(request: InspectPgpKeyTextRequest) -> PgpKeyInspectionResponse {
    match inspect_pgp_key_bytes(request.armored_text.into_bytes()) {
        Ok(inspected) => PgpKeyInspectionResponse {
            inspection: Some(PgpKeyInspectionDto::from(inspected.inspection())),
            error: None,
        },
        Err(error) => {
            PgpKeyInspectionResponse { inspection: None, error: Some(BridgeFailure::from(error)) }
        }
    }
}

/// Inspects a local key file. The file's bytes are read here and never returned to Flutter.
pub async fn inspect_pgp_key_file(request: InspectPgpKeyFileRequest) -> PgpKeyInspectionResponse {
    match inspect_pgp_key_file_core(Path::new(&request.path)) {
        Ok(inspected) => PgpKeyInspectionResponse {
            inspection: Some(PgpKeyInspectionDto::from(inspected.inspection())),
            error: None,
        },
        Err(error) => {
            PgpKeyInspectionResponse { inspection: None, error: Some(BridgeFailure::from(error)) }
        }
    }
}

/// Imports pasted PGP key material of either kind, validating any passphrase before mutating.
pub async fn import_pgp_key_text(request: ImportPgpKeyTextRequest) -> PgpKeyImportResponse {
    let passphrase = request.passphrase.map(SecretString::from);
    pgp_key_import_response(
        pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
            import_pgp_key_text_core(
                backend.as_ref(),
                request.armored_text,
                passphrase.as_ref(),
                None,
            )
            .map_err(BridgeFailure::from)
        }),
    )
}

/// Imports a PGP key file of either kind. Binary exports are supported because the file is read as
/// bytes rather than UTF-8 text.
pub async fn import_pgp_key_file(request: ImportPgpKeyFileRequest) -> PgpKeyImportResponse {
    let passphrase = request.passphrase.map(SecretString::from);
    pgp_key_import_response(
        pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
            import_pgp_key_file_core(
                backend.as_ref(),
                Path::new(&request.path),
                passphrase.as_ref(),
                None,
            )
            .map_err(BridgeFailure::from)
        }),
    )
}

pub async fn import_pgp_public_key(request: ImportKeyTextRequest) -> KeyMutationResponse {
    legacy_import_pgp_key_text(request, PgpKeyMaterialKind::Public)
}

pub async fn import_pgp_private_key_text(request: ImportKeyTextRequest) -> KeyMutationResponse {
    legacy_import_pgp_key_text(request, PgpKeyMaterialKind::Private)
}

pub async fn import_pgp_private_key_file(request: ImportKeyFileRequest) -> KeyMutationResponse {
    let outcome =
        pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
            import_pgp_key_file_core(
                backend.as_ref(),
                Path::new(&request.path),
                None,
                Some(PgpKeyMaterialKind::Private),
            )
            .map_err(BridgeFailure::from)
        });
    legacy_key_mutation_response(
        outcome,
        request.name,
        pgp_import_source_label(PgpKeyMaterialKind::Private),
    )
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
    match export_pgp_private_key_inner(request) {
        Ok(export) => KeyExportResponse { export: Some(export.into()), error: None },
        Err(error) => KeyExportResponse { export: None, error: Some(error) },
    }
}

pub async fn prepare_pgp_private_key(
    request: PreparePgpPrivateKeyRequest,
) -> PreparePgpPrivateKeyResponse {
    let passphrase = SecretString::from(request.passphrase);
    match pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
        backend
            .prepare_private_key(&request.fingerprint, &passphrase)
            .map_err(pgp_preparation_failure)
    }) {
        Ok(prepared) => PreparePgpPrivateKeyResponse {
            fingerprint: Some(prepared.fingerprint),
            migrated: prepared.migrated,
            error: None,
        },
        Err(error) => {
            PreparePgpPrivateKeyResponse { fingerprint: None, migrated: false, error: Some(error) }
        }
    }
}

pub async fn delete_pgp_key(request: DeletePgpKeyRequest) -> DeletePgpKeyResponse {
    let outcome =
        pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
            backend
                .delete_key(&request.fingerprint)
                .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
        });
    match outcome {
        Ok(mut result) => {
            let cleanup_error = result.public_cleanup_error.take();
            DeletePgpKeyResponse {
                result: Some(result.into()),
                failure_kind: cleanup_error
                    .as_ref()
                    .map(|_| PgpKeyDeletionFailureKind::PublicCleanupFailed),
                error: cleanup_error
                    .map(|message| BridgeFailure::simple(BridgeFailureCategory::PgpError, message)),
            }
        }
        Err(error) => DeletePgpKeyResponse {
            result: None,
            failure_kind: Some(PgpKeyDeletionFailureKind::PrivateRemovalFailed),
            error: Some(error),
        },
    }
}

fn pgp_preparation_failure(error: PgpBackendError) -> BridgeFailure {
    match error {
        PgpBackendError::PassphraseRequired => {
            BridgeFailure::from(PgpImportError::PassphraseRequired)
        }
        PgpBackendError::IncorrectPassphrase => {
            BridgeFailure::from(PgpImportError::IncorrectPassphrase)
        }
        PgpBackendError::UnsupportedProtection => {
            BridgeFailure::from(PgpImportError::UnsupportedProtection)
        }
        PgpBackendError::ReprotectionFailed => {
            BridgeFailure::from(PgpImportError::ReprotectionFailed)
        }
        other => BridgeFailure::from(CoreError::PgpError(other.to_string())),
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
                pgp_executable: request.pgp_executable,
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

pub async fn delete_ssh_key(request: DeleteSshKeyRequest) -> UnitResponse {
    UnitResponse {
        error: delete_ssh_key_core(Path::new(&request.ssh_dir), &request.name)
            .err()
            .map(BridgeFailure::from),
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
                is_default: root_path == Path::new(&config.path_config.default_repo),
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

fn pgp_key_import_response(
    outcome: Result<PgpImportOutcome, BridgeFailure>,
) -> PgpKeyImportResponse {
    match outcome {
        Ok(outcome) => PgpKeyImportResponse {
            inspection: Some(PgpKeyInspectionDto::from(&outcome.inspection)),
            key: Some(pgp_key_record(
                &outcome,
                None,
                pgp_import_source_label(outcome.inspection.kind),
            )),
            error: None,
        },
        Err(error) => PgpKeyImportResponse { inspection: None, key: None, error: Some(error) },
    }
}

/// Legacy type-specific PGP import.
///
/// Kept so in-tree callers keep working during the migration; Settings and Onboarding use the
/// source-independent `import_pgp_key_text` / `import_pgp_key_file` instead. Classification now
/// comes from packet inspection rather than armor markers, and the fingerprint is the canonical one.
fn legacy_import_pgp_key_text(
    request: ImportKeyTextRequest,
    expected_kind: PgpKeyMaterialKind,
) -> KeyMutationResponse {
    let source = pgp_import_source_label(expected_kind);
    let outcome =
        pgp_backend(&request.config_path, request.pgp_executable.as_deref()).and_then(|backend| {
            import_pgp_key_text_core(
                backend.as_ref(),
                request.armored_text,
                None,
                Some(expected_kind),
            )
            .map_err(BridgeFailure::from)
        });
    legacy_key_mutation_response(outcome, request.name, source)
}

fn legacy_key_mutation_response(
    outcome: Result<PgpImportOutcome, BridgeFailure>,
    name: Option<String>,
    source: &str,
) -> KeyMutationResponse {
    match outcome {
        Ok(outcome) => {
            KeyMutationResponse { key: Some(pgp_key_record(&outcome, name, source)), error: None }
        }
        Err(error) => KeyMutationResponse { key: None, error: Some(error) },
    }
}

/// Builds the GUI-facing record from backend-confirmed metadata.
fn pgp_key_record(outcome: &PgpImportOutcome, name: Option<String>, source: &str) -> KeyRecordDto {
    KeyRecordDto {
        key_type: "pgp".to_string(),
        name: name.unwrap_or_else(|| outcome.identity.clone()),
        fingerprint: outcome.fingerprint.clone(),
        source: source.to_string(),
        has_private_key: outcome.imported_private_key,
    }
}

fn pgp_import_source_label(kind: PgpKeyMaterialKind) -> &'static str {
    match kind {
        PgpKeyMaterialKind::Public => "Imported public key",
        PgpKeyMaterialKind::Private => "Imported private key",
    }
}

fn export_pgp_private_key_inner(
    request: ExportPgpKeyRequest,
) -> Result<KeyExportResult, BridgeFailure> {
    let backend = pgp_backend(&request.config_path, request.pgp_executable.as_deref())?;
    let identity = pgp_key_identity_for_confirmation(backend.as_ref(), &request.fingerprint)?;
    let expected = format!("EXPORT PRIVATE KEY {identity}");
    if request.confirmation.as_deref() != Some(expected.as_str()) {
        return Err(BridgeFailure::from(CoreError::ValidationError(format!(
            "private key export requires confirmation phrase: {expected}"
        ))));
    }

    backend
        .export_private_key(&request.fingerprint, None)
        .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))
}

fn pgp_key_identity_for_confirmation(
    backend: &dyn PgpBackend,
    fingerprint: &str,
) -> Result<String, BridgeFailure> {
    let normalized = fingerprint.trim();
    let key = backend
        .list_keys()
        .map_err(|error| BridgeFailure::from(CoreError::PgpError(error.to_string())))?
        .into_iter()
        .find(|key| key.fingerprint == normalized)
        .ok_or_else(|| {
            BridgeFailure::from(CoreError::ValidationError(format!(
                "PGP key is not listed for fingerprint: {normalized}"
            )))
        })?;
    let identity = key.identity.trim();
    if identity.is_empty() {
        return Err(BridgeFailure::from(CoreError::ValidationError(format!(
            "PGP key identity is empty for fingerprint: {normalized}"
        ))));
    }
    Ok(identity.to_string())
}

pub(crate) fn pgp_backend(
    config_path: &str,
    pgp_executable: Option<&str>,
) -> Result<Box<dyn PgpBackend>, BridgeFailure> {
    let mut config = if Path::new(config_path).is_file() {
        load_core_config(config_path)
            .map_err(|error| CoreError::ConfigError(error.to_string()))
            .map_err(BridgeFailure::from)?
    } else {
        ParsConfig::default()
    };
    if let Some(executable) = pgp_executable {
        if matches!(config.pgp_config.backend, PgpBackendKind::SystemGpg) {
            config.pgp_config.system_gpg_path = Some(executable.to_string());
        }
    }
    match config.pgp_config.backend {
        PgpBackendKind::SystemGpg | PgpBackendKind::Bundled => {
            SystemGpgBackend::from_config(&config.pgp_config)
                .map(|backend| Box::new(backend) as Box<dyn PgpBackend>)
        }
        PgpBackendKind::PureRust => RpgpBackend::from_config(&config.pgp_config)
            .map(|backend| Box::new(backend) as Box<dyn PgpBackend>),
    }
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
    let managed_pgp_keys = if request.pgp_executable.is_none() {
        pgp_backend(&request.config_path, None)
            .ok()
            .and_then(|backend| backend.list_keys().ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    };
    let stores = config
        .path_config
        .repos
        .iter()
        .enumerate()
        .map(|(index, root)| {
            inspect_store(
                index,
                root,
                root == &default_repo,
                request.pgp_executable.as_deref(),
                if request.pgp_executable.is_none() {
                    Some(managed_pgp_keys.as_slice())
                } else {
                    None
                },
            )
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
    managed_pgp_keys: Option<&[PgpKeySummary]>,
) -> StoreStatusDto {
    let root_path = PathBuf::from(root);
    let name = store_name(&root_path);
    let exists = root_path.is_dir();
    let gpg_id_path = root_path.join(".gpg-id");
    let has_gpg_id = gpg_id_path.is_file();
    let has_git_repo = root_path.join(".git").is_dir();
    let has_git_remote = exists && has_git_repo && git_remote_exists(&root_path);
    let pgp_key_missing =
        has_gpg_id && pgp_key_missing(&gpg_id_path, pgp_executable, managed_pgp_keys);
    let mut issues = Vec::new();

    if !exists {
        issues.push("store_missing".to_string());
    }
    if exists && !has_gpg_id {
        issues.push("missing_gpg_id".to_string());
    }
    if exists && has_git_repo && !has_git_remote {
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
    let root_path = PathBuf::from(&root);
    let expected_confirmation =
        root_path.file_name().and_then(|name| name.to_str()).ok_or_else(|| {
            BridgeFailure::from(CoreError::ValidationError(
                "delete confirmation could not derive a store name from the root".to_string(),
            ))
        })?;
    if request.confirmation != expected_confirmation {
        return Err(BridgeFailure::from(CoreError::ValidationError(format!(
            "delete confirmation must match the store name: {expected_confirmation}"
        ))));
    }
    let mut config = load_config_for_mutation(&request.config_path)?;
    if !config.path_config.repos.iter().any(|repo| repo == &root) {
        return Err(BridgeFailure::from(CoreError::ValidationError(format!(
            "refusing to delete unconfigured store: {root}"
        ))));
    }
    if root_path.exists() && !root_path.is_dir() {
        return Err(BridgeFailure::from(CoreError::StoreError(format!(
            "password store root is not a directory: {root}"
        ))));
    }
    if root_path.parent().is_none() || root_path == Path::new("/") {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "refusing to delete filesystem root".to_string(),
        )));
    }

    // Delete the app-owned files first. If deletion is interrupted, the store
    // remains configured and the user can retry instead of being left with an
    // invisible orphan directory that is no longer reachable from the UI.
    if root_path.is_dir() {
        fs::remove_dir_all(&root_path).map_err(store_failure)?;
    }

    config.path_config.repos.retain(|repo| repo != &root);
    if config.path_config.default_repo == root {
        config.path_config.default_repo =
            config.path_config.repos.first().cloned().unwrap_or_default();
    }
    save_config_for_mutation(&config, &request.config_path)
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

fn configure_pgp_backend_inner(request: ConfigurePgpBackendRequest) -> Result<(), BridgeFailure> {
    let mut config = load_config_for_mutation(&request.config_path)?;
    match request.backend.as_str() {
        "system_gpg" => {
            config.pgp_config.backend = PgpBackendKind::SystemGpg;
            config.pgp_config.system_gpg_path = request.pgp_executable;
        }
        "bundled" => {
            config.pgp_config.backend = PgpBackendKind::Bundled;
            config.pgp_config.bundled_gpg_path = request.pgp_executable;
        }
        "pure_rust" => {
            let keyring_home = request.keyring_home.ok_or_else(|| {
                BridgeFailure::from(CoreError::ConfigError(
                    "pure_rust PGP backend requires keyring_home".to_string(),
                ))
            })?;
            config.pgp_config.backend = PgpBackendKind::PureRust;
            config.pgp_config.keyring_home = Some(keyring_home);
            config.pgp_config.pure_rust_enabled = true;
        }
        other => {
            return Err(BridgeFailure::from(CoreError::ConfigError(format!(
                "unsupported PGP backend: {other}"
            ))));
        }
    }
    save_config_for_mutation(&config, &request.config_path)
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

fn pgp_key_missing(
    gpg_id_path: &Path,
    pgp_executable: Option<&str>,
    managed_pgp_keys: Option<&[PgpKeySummary]>,
) -> bool {
    let Ok(content) = fs::read_to_string(gpg_id_path) else {
        return true;
    };
    let keys = content.lines().map(str::trim).filter(|line| !line.is_empty()).collect::<Vec<_>>();
    if keys.is_empty() {
        return true;
    }
    if let Some(executable) = pgp_executable {
        return keys.iter().any(|key| {
            Command::new(executable)
                .args(["--list-secret-keys", key])
                .output()
                .map(|output| !output.status.success())
                .unwrap_or(true)
        });
    }
    let available = managed_pgp_keys.unwrap_or_default();
    keys.iter().any(|required| {
        !available.iter().any(|key| key.has_private_key && pgp_key_matches(required, key))
    })
}

fn pgp_key_matches(required: &str, key: &PgpKeySummary) -> bool {
    let required_compact =
        required.chars().filter(|value| !value.is_whitespace()).collect::<String>();
    let fingerprint_compact =
        key.fingerprint.chars().filter(|value| !value.is_whitespace()).collect::<String>();
    let required_upper = required_compact.to_uppercase();
    let fingerprint_upper = fingerprint_compact.to_uppercase();
    if fingerprint_upper == required_upper || fingerprint_upper.ends_with(&required_upper) {
        return true;
    }
    let identity = key.identity.trim();
    identity.eq_ignore_ascii_case(required)
        || identity.to_lowercase().contains(&format!("<{}>", required.to_lowercase()))
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
    let executable = request.pgp_executable.clone().unwrap_or_else(|| "gpg".to_string());
    let backend = pgp_backend(&request.config_path, Some(&executable))?;
    gui::read_entry_with_backend(
        gui::ReadEntryRequest {
            entry: entry_ref(&request.root, &request.path)?,
            pgp_executable: executable,
            passphrase: request.passphrase,
        },
        backend.as_ref(),
    )
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

impl From<AutofillEntryMetadataDto> for AutofillEntryMetadata {
    fn from(value: AutofillEntryMetadataDto) -> Self {
        Self { path: value.path, is_favorite: value.is_favorite, recent_rank: value.recent_rank }
    }
}

impl From<autofill::AutofillCandidate> for AutofillCandidateDto {
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

impl From<AutofillCredential> for AutofillCredentialDto {
    fn from(value: AutofillCredential) -> Self {
        Self { path: value.path, username: value.username, password: value.password }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(fingerprint: &str, identity: &str, has_private_key: bool) -> PgpKeySummary {
        PgpKeySummary {
            identity: identity.to_string(),
            fingerprint: fingerprint.to_string(),
            has_private_key,
        }
    }

    #[test]
    fn pure_rust_key_check_requires_matching_private_material() {
        let temp = tempfile::tempdir().expect("tempdir");
        let gpg_id = temp.path().join(".gpg-id");
        fs::write(&gpg_id, "A1B2C3D4").expect("gpg id");

        let private = key("00000000A1B2C3D4", "Alice <alice@example.com>", true);
        assert!(!pgp_key_missing(&gpg_id, None, Some(&[private])));

        let public_only = key("00000000A1B2C3D4", "Alice <alice@example.com>", false);
        assert!(pgp_key_missing(&gpg_id, None, Some(&[public_only])));
        assert!(pgp_key_missing(&gpg_id, None, Some(&[])));
    }

    #[test]
    fn pure_rust_key_check_accepts_identity_email() {
        let temp = tempfile::tempdir().expect("tempdir");
        let gpg_id = temp.path().join(".gpg-id");
        fs::write(&gpg_id, "alice@example.com").expect("gpg id");
        let private = key("A1B2C3D4", "Alice <alice@example.com>", true);

        assert!(!pgp_key_missing(&gpg_id, None, Some(&[private])));
    }
}
