use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

use git2::build::CheckoutBuilder;
#[cfg(any(target_os = "android", target_os = "ios"))]
use git2::build::RepoBuilder;
use git2::{
    BranchType, Cred, CredentialType, FetchOptions, IndexAddOption, PushOptions, RemoteCallbacks,
    Repository, Signature, Status, StatusOptions,
};
use pars_core::autofill::{
    self, AutofillCredential, AutofillCredentialRequest as CoreAutofillCredentialRequest,
    AutofillEntryMetadata, AutofillQueryRequest as CoreAutofillQueryRequest,
};
use pars_core::config::cli::{
    load_config as load_core_config, save_config as save_core_config, ParsConfig, PgpBackendKind,
};
use pars_core::gui::{
    self, CoreError, EntryRef, GitOperationRequest, KeyExportResult, PgpKeySummary, SshKeySummary,
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
    "git_list_remotes",
    "git_add_remote",
    "git_set_remote_url",
    "git_remove_remote",
    "run_git_args",
    "inspect_store_git",
    "initialize_git_repository",
    "inspect_app_state",
    "create_local_store",
    "import_local_store",
    "clone_store",
    "disconnect_store",
    "delete_local_store",
    "list_keys",
    "detect_imported_key",
    "generate_pgp_key",
    "inspect_pgp_key_text",
    "inspect_pgp_key_file",
    "import_pgp_key_text",
    "import_pgp_key_file",
    "prepare_pgp_private_key",
    "initialize_store_recipients",
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
    "patch_autofill_index_favorites",
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
    pub ssh_private_key_path: Option<String>,
    pub ssh_dir: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GitCommitRequest {
    pub root: String,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct GitRemoteRequest {
    pub root: String,
    pub name: String,
    pub url: Option<String>,
}

#[derive(Debug, Clone)]
pub struct GitArgsRequest {
    pub root: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct InspectStoreGitRequest {
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct InspectStoreGitResponse {
    pub mode: Option<StoreGitModeDto>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Clone)]
pub struct InitializeGitRepositoryRequest {
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct InspectAppStateRequest {
    pub config_path: String,
    pub pgp_executable: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CreateLocalStoreRequest {
    pub config_path: String,
    pub name: String,
    pub root: String,
    pub pgp_keys: Vec<String>,
    pub initialize_git: bool,
}

#[derive(Debug, Clone)]
pub struct ImportLocalStoreRequest {
    pub config_path: String,
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct CloneStoreRequest {
    pub config_path: String,
    pub remote_url: String,
    pub root: String,
    pub ssh_private_key_path: Option<String>,
    pub ssh_dir: Option<String>,
}

#[derive(Debug, Clone)]
pub struct DisconnectStoreRequest {
    pub config_path: String,
    pub root: String,
}

#[derive(Debug, Clone)]
pub struct DeleteLocalStoreRequest {
    pub config_path: String,
    pub root: String,
    pub managed_store_base: String,
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
pub struct InitializeStoreRecipientsRequest {
    pub config_path: String,
    pub root: String,
    pub fingerprints: Vec<String>,
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
pub struct PatchAutofillIndexFavoritesRequest {
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
    pub onboarding_state: String,
    pub issues: Vec<String>,
    pub store: Option<StoreStatusDto>,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum StoreGitModeDto {
    Disabled,
    Local,
    Remote,
    Invalid,
}

#[derive(Debug, Clone)]
pub struct StoreStatusDto {
    pub name: String,
    pub root: String,
    pub exists: bool,
    pub has_gpg_id: bool,
    pub pgp_recipients: Vec<String>,
    pub git_mode: StoreGitModeDto,
    pub pgp_key_missing: bool,
    pub issues: Vec<String>,
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

pub async fn patch_autofill_index_favorites(
    request: PatchAutofillIndexFavoritesRequest,
) -> UnitResponse {
    let result =
        autofill::patch_autofill_index_favorites(autofill::PatchAutofillIndexFavoritesRequest {
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
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = (request.ssh_private_key_path, request.ssh_dir);
        return structured_git_response("git status --short --branch", || {
            structured_git_status(Path::new(&request.root))
        });
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let _ = (request.ssh_private_key_path, request.ssh_dir);
        run_git_command_response(request.root, vec!["status", "--short", "--branch"])
    }
}

pub async fn git_pull(request: GitRequest) -> GitCommandResponse {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        return structured_git_response("git pull", || {
            structured_git_pull(
                Path::new(&request.root),
                request.ssh_private_key_path.as_deref().map(Path::new),
                request.ssh_dir.as_deref().map(Path::new),
            )
        });
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let _ = (request.ssh_private_key_path, request.ssh_dir);
        run_git_command_response(request.root, vec!["pull"])
    }
}

pub async fn git_push(request: GitRequest) -> GitCommandResponse {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        return structured_git_response("git push", || {
            structured_git_push(
                Path::new(&request.root),
                request.ssh_private_key_path.as_deref().map(Path::new),
                request.ssh_dir.as_deref().map(Path::new),
            )
        });
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let _ = (request.ssh_private_key_path, request.ssh_dir);
        run_git_command_response(request.root, vec!["push"])
    }
}

pub async fn git_commit(request: GitCommitRequest) -> GitCommandResponse {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        return structured_git_response(&format!("git commit -m {:?}", request.message), || {
            structured_git_commit(Path::new(&request.root), &request.message)
        });
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    run_git_command_response(request.root, vec!["commit", "-m", &request.message])
}

pub async fn git_list_remotes(request: GitRequest) -> GitCommandResponse {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = request.ssh_private_key_path;
        return structured_git_response("git remote -v", || {
            structured_git_list_remotes(Path::new(&request.root))
        });
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let _ = request.ssh_private_key_path;
        run_git_command_response(request.root, vec!["remote", "-v"])
    }
}

pub async fn git_add_remote(request: GitRemoteRequest) -> GitCommandResponse {
    let command = format!(
        "git remote add {} {}",
        request.name,
        sanitized_remote_url(request.url.as_deref().unwrap_or(""))
    );
    structured_or_system_remote_response(command, request, GitRemoteMutation::Add)
}

pub async fn git_set_remote_url(request: GitRemoteRequest) -> GitCommandResponse {
    let command = format!(
        "git remote set-url {} {}",
        request.name,
        sanitized_remote_url(request.url.as_deref().unwrap_or(""))
    );
    structured_or_system_remote_response(command, request, GitRemoteMutation::SetUrl)
}

pub async fn git_remove_remote(request: GitRemoteRequest) -> GitCommandResponse {
    let command = format!("git remote remove {}", request.name);
    structured_or_system_remote_response(command, request, GitRemoteMutation::Remove)
}

pub async fn run_git_args(request: GitArgsRequest) -> GitCommandResponse {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = request;
        return GitCommandResponse {
            output: None,
            error: Some(BridgeFailure {
                category: BridgeFailureCategory::UnsupportedPlatform,
                message: "advanced Git arguments are unavailable on mobile".to_string(),
                conflict_kind: None,
                path: None,
                pgp_import_kind: None,
            }),
        };
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    match GitOperationRequest::new(PathBuf::from(request.root), request.args)
        .and_then(gui::run_git_args)
    {
        Ok(output) => GitCommandResponse { output: Some(output.into()), error: None },
        Err(error) => GitCommandResponse { output: None, error: Some(BridgeFailure::from(error)) },
    }
}

pub async fn inspect_store_git(request: InspectStoreGitRequest) -> InspectStoreGitResponse {
    let root = PathBuf::from(request.root);
    if !root.is_dir() {
        return InspectStoreGitResponse {
            mode: None,
            error: Some(BridgeFailure::from(CoreError::StoreError(
                "password store root does not exist".to_string(),
            ))),
        };
    }
    InspectStoreGitResponse { mode: Some(inspect_git_mode(&root)), error: None }
}

pub async fn initialize_git_repository(request: InitializeGitRepositoryRequest) -> UnitResponse {
    UnitResponse { error: init_git_repository(Path::new(&request.root)).err() }
}

pub async fn inspect_app_state(request: InspectAppStateRequest) -> AppStateResponse {
    match inspect_app_state_inner(request) {
        Ok(state) => AppStateResponse { state: Some(state), error: None },
        Err(error) => AppStateResponse { state: None, error: Some(error) },
    }
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

pub async fn disconnect_store(request: DisconnectStoreRequest) -> UnitResponse {
    UnitResponse { error: disconnect_store_inner(request).err() }
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

#[flutter_rust_bridge::frb(ignore)]
pub async fn import_pgp_public_key(request: ImportKeyTextRequest) -> KeyMutationResponse {
    legacy_import_pgp_key_text(request, PgpKeyMaterialKind::Public)
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn import_pgp_private_key_text(request: ImportKeyTextRequest) -> KeyMutationResponse {
    legacy_import_pgp_key_text(request, PgpKeyMaterialKind::Private)
}

#[flutter_rust_bridge::frb(ignore)]
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

#[flutter_rust_bridge::frb(ignore)]
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

#[flutter_rust_bridge::frb(ignore)]
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

#[flutter_rust_bridge::frb(ignore)]
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

#[flutter_rust_bridge::frb(ignore)]
pub async fn add_pgp_key_to_gpg_id(request: AddPgpKeyToGpgIdRequest) -> UnitResponse {
    UnitResponse {
        error: add_pgp_key_to_gpg_id_core(Path::new(&request.root), &request.fingerprint)
            .err()
            .map(BridgeFailure::from),
    }
}

pub async fn initialize_store_recipients(
    request: InitializeStoreRecipientsRequest,
) -> UnitResponse {
    UnitResponse { error: initialize_store_recipients_inner(request).err() }
}

fn initialize_store_recipients_inner(
    request: InitializeStoreRecipientsRequest,
) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let config = load_config_for_mutation(&request.config_path)?;
    if config.path_config.default_repo != root {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "recipient repair requires the canonical password store".to_string(),
        )));
    }
    let root_path = PathBuf::from(&root);
    if !root_path.is_dir() {
        return Err(BridgeFailure::from(CoreError::StoreError(
            "password store root does not exist".to_string(),
        )));
    }
    let gpg_id = root_path.join(".gpg-id");
    match fs::symlink_metadata(&gpg_id) {
        Ok(_) => {
            return Err(BridgeFailure::from(CoreError::ValidationError(
                ".gpg-id already exists; recipient rotation requires migration".to_string(),
            )));
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(store_failure(error)),
    }
    let recipients = validated_recipients(request.fingerprints)?;
    write_new_gpg_id(&gpg_id, &recipients)
}

fn validated_recipients(recipients: Vec<String>) -> Result<Vec<String>, BridgeFailure> {
    if recipients.iter().any(|recipient| recipient.contains(['\r', '\n'])) {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "PGP recipient values must not contain line breaks".to_string(),
        )));
    }
    normalized_keys(recipients)
}

fn write_new_gpg_id(path: &Path, recipients: &[String]) -> Result<(), BridgeFailure> {
    let mut file =
        OpenOptions::new().write(true).create_new(true).open(path).map_err(store_failure)?;
    file.write_all(recipients.join("\n").as_bytes()).map_err(store_failure)?;
    file.sync_all().map_err(store_failure)
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
            onboarding_state: "no_config".to_string(),
            issues: vec!["no_config".to_string()],
            store: None,
        });
    }

    let config = load_core_config(&config_path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .map_err(BridgeFailure::from)?;
    let root = config.path_config.default_repo.trim();
    if root.is_empty() {
        return Ok(AppStateDto {
            config_path: request.config_path,
            config_exists: true,
            onboarding_state: "store_missing".to_string(),
            issues: vec!["store_missing".to_string()],
            store: None,
        });
    }

    let managed_pgp_keys = if request.pgp_executable.is_none() {
        pgp_backend(&request.config_path, None)
            .ok()
            .and_then(|backend| backend.list_keys().ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    };
    let store = inspect_store(
        root,
        request.pgp_executable.as_deref(),
        if request.pgp_executable.is_none() { Some(managed_pgp_keys.as_slice()) } else { None },
    );
    let issues = store.issues.clone();
    let onboarding_state = lifecycle_state(&issues);

    Ok(AppStateDto {
        config_path: request.config_path,
        config_exists: true,
        onboarding_state,
        issues,
        store: Some(store),
    })
}

fn inspect_store(
    root: &str,
    pgp_executable: Option<&str>,
    managed_pgp_keys: Option<&[PgpKeySummary]>,
) -> StoreStatusDto {
    let root_path = PathBuf::from(root);
    let name = store_name(&root_path);
    let exists = root_path.is_dir();
    let gpg_id_path = root_path.join(".gpg-id");
    let gpg_id_content = read_regular_gpg_id(&gpg_id_path);
    let has_gpg_id = gpg_id_content.is_some();
    let pgp_recipients = gpg_id_content
        .as_deref()
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect();
    let git_mode = if exists { inspect_git_mode(&root_path) } else { StoreGitModeDto::Disabled };
    let pgp_key_missing =
        has_gpg_id && pgp_key_missing(&gpg_id_path, pgp_executable, managed_pgp_keys);
    let mut issues = Vec::new();

    if !exists {
        issues.push("store_missing".to_string());
    }
    if exists && !has_gpg_id {
        issues.push("missing_gpg_id".to_string());
    }
    if exists && git_mode == StoreGitModeDto::Invalid {
        issues.push("git_invalid".to_string());
    }
    if exists && pgp_key_missing {
        issues.push("pgp_key_missing".to_string());
    }

    StoreStatusDto {
        name,
        root: root.to_string(),
        exists,
        has_gpg_id,
        pgp_recipients,
        git_mode,
        pgp_key_missing,
        issues,
    }
}

fn lifecycle_state(issues: &[String]) -> String {
    for state in ["store_missing", "missing_gpg_id", "git_invalid", "pgp_key_missing"] {
        if issues.iter().any(|issue| issue == state) {
            return state.to_string();
        }
    }
    "ready".to_string()
}

fn inspect_git_mode(root: &Path) -> StoreGitModeDto {
    let git_entry = root.join(".git");
    let metadata = match fs::symlink_metadata(&git_entry) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return StoreGitModeDto::Disabled;
        }
        Err(_) => return StoreGitModeDto::Invalid,
    };
    if metadata.file_type().is_symlink() {
        return StoreGitModeDto::Invalid;
    }
    let Ok(root_canonical) = root.canonicalize() else {
        return StoreGitModeDto::Invalid;
    };
    let Ok(repo) = Repository::open(root) else {
        return StoreGitModeDto::Invalid;
    };
    let Ok(git_dir) = repo.path().canonicalize() else {
        return StoreGitModeDto::Invalid;
    };
    let Some(workdir) = repo.workdir() else {
        return StoreGitModeDto::Invalid;
    };
    let Ok(workdir) = workdir.canonicalize() else {
        return StoreGitModeDto::Invalid;
    };
    if workdir != root_canonical
        || !git_dir.starts_with(&root_canonical)
        || git_dir == root_canonical
    {
        return StoreGitModeDto::Invalid;
    }
    match repo.remotes() {
        Ok(remotes) if !remotes.is_empty() => StoreGitModeDto::Remote,
        Ok(_) => StoreGitModeDto::Local,
        Err(_) => StoreGitModeDto::Invalid,
    }
}

fn create_local_store_inner(request: CreateLocalStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let root_path = PathBuf::from(&root);
    let keys = validated_recipients(request.pgp_keys)?;
    let mut config = load_config_for_mutation(&request.config_path)?;
    require_empty_canonical_store(&config)?;

    create_new_store_tree(&root_path, &keys, |staging| {
        if request.initialize_git {
            init_git_repository(staging)?;
        }
        Ok(())
    })?;

    set_canonical_store(&mut config, &root);
    if let Err(error) = save_config_for_mutation(&config, &request.config_path) {
        let _ = fs::remove_dir_all(&root_path);
        return Err(error);
    }
    Ok(())
}

fn create_new_store_tree<F>(
    root: &Path,
    recipients: &[String],
    prepare: F,
) -> Result<(), BridgeFailure>
where
    F: FnOnce(&Path) -> Result<(), BridgeFailure>,
{
    match fs::symlink_metadata(root) {
        Ok(_) => {
            return Err(BridgeFailure::from(CoreError::Conflict(gui::EntryConflict {
                kind: gui::EntryConflictKind::EntryAlreadyExists,
                path: root.display().to_string(),
            })));
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(store_failure(error)),
    }
    let parent = root.parent().ok_or_else(|| {
        BridgeFailure::from(CoreError::ValidationError(
            "password store root requires a parent directory".to_string(),
        ))
    })?;
    fs::create_dir_all(parent).map_err(store_failure)?;
    let staging = tempfile::Builder::new()
        .prefix(".pars-create-")
        .tempdir_in(parent)
        .map_err(store_failure)?;
    write_new_gpg_id(&staging.path().join(".gpg-id"), recipients)?;
    prepare(staging.path())?;

    let staging_path = staging.keep();
    if let Err(error) = rename_directory_noreplace(&staging_path, root) {
        let _ = fs::remove_dir_all(&staging_path);
        if error.kind() == std::io::ErrorKind::AlreadyExists {
            return Err(BridgeFailure::from(CoreError::Conflict(gui::EntryConflict {
                kind: gui::EntryConflictKind::EntryAlreadyExists,
                path: root.display().to_string(),
            })));
        }
        return Err(store_failure(error));
    }
    Ok(())
}

#[cfg(any(target_os = "linux", target_os = "android"))]
fn rename_directory_noreplace(from: &Path, to: &Path) -> std::io::Result<()> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let from = CString::new(from.as_os_str().as_bytes())?;
    let to = CString::new(to.as_os_str().as_bytes())?;
    // SAFETY: both C strings are NUL-terminated and remain alive for the call.
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE as _,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn rename_directory_noreplace(from: &Path, to: &Path) -> std::io::Result<()> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let from = CString::new(from.as_os_str().as_bytes())?;
    let to = CString::new(to.as_os_str().as_bytes())?;
    // SAFETY: both C strings are NUL-terminated and remain alive for the call.
    let result = unsafe { libc::renamex_np(from.as_ptr(), to.as_ptr(), libc::RENAME_EXCL) };
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(windows)]
fn rename_directory_noreplace(from: &Path, to: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "Kernel32")]
    extern "system" {
        fn MoveFileExW(existing: *const u16, replacement: *const u16, flags: u32) -> i32;
    }
    let from = from.as_os_str().encode_wide().chain(Some(0)).collect::<Vec<_>>();
    let to = to.as_os_str().encode_wide().chain(Some(0)).collect::<Vec<_>>();
    // A zero flag set refuses to replace an existing destination.
    let result = unsafe { MoveFileExW(from.as_ptr(), to.as_ptr(), 0) };
    if result != 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(not(any(
    target_os = "linux",
    target_os = "android",
    target_os = "macos",
    target_os = "ios",
    windows,
)))]
fn rename_directory_noreplace(from: &Path, to: &Path) -> std::io::Result<()> {
    // Unsupported niche targets still reserve the final path without replacing it.
    fs::create_dir(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        fs::rename(entry.path(), to.join(entry.file_name()))?;
    }
    fs::remove_dir(from)
}

fn import_local_store_inner(request: ImportLocalStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let root_path = Path::new(&root);
    if !root_path.is_dir() {
        return Err(BridgeFailure::from(CoreError::StoreError(
            "password store root is unavailable".to_string(),
        )));
    }
    let mut config = load_config_for_mutation(&request.config_path)?;
    require_empty_canonical_store(&config)?;
    if inspect_git_mode(root_path) == StoreGitModeDto::Invalid {
        return Err(BridgeFailure::from(CoreError::GitError(
            "imported store contains invalid Git metadata".to_string(),
        )));
    }
    set_canonical_store(&mut config, &root);
    save_config_for_mutation(&config, &request.config_path)
}

fn clone_store_inner(request: CloneStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let root_path = PathBuf::from(&root);
    let mut config = load_config_for_mutation(&request.config_path)?;
    require_empty_canonical_store(&config)?;
    if root_path.exists() {
        return Err(BridgeFailure::from(CoreError::Conflict(gui::EntryConflict {
            kind: gui::EntryConflictKind::EntryAlreadyExists,
            path: root,
        })));
    }
    if let Some(parent) = root_path.parent() {
        fs::create_dir_all(parent).map_err(store_failure)?;
    }
    if let Err(error) = clone_git_repository(
        &request.remote_url,
        &root_path,
        request.ssh_private_key_path.as_deref(),
        request.ssh_dir.as_deref(),
    ) {
        if root_path.exists() {
            let _ = fs::remove_dir_all(&root_path);
        }
        return Err(error);
    }
    set_canonical_store(&mut config, &root_path.display().to_string());
    if let Err(error) = save_config_for_mutation(&config, &request.config_path) {
        let _ = fs::remove_dir_all(&root_path);
        return Err(error);
    }
    Ok(())
}

fn disconnect_store_inner(request: DisconnectStoreRequest) -> Result<(), BridgeFailure> {
    let root = normalize_store_root(&request.root)?;
    let mut config = load_config_for_mutation(&request.config_path)?;
    require_canonical_store(&config, &root)?;
    clear_canonical_store(&mut config);
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
    require_canonical_store(&config, &root)?;
    require_app_managed_root(&root_path, Path::new(&request.managed_store_base))?;
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

    clear_canonical_store(&mut config);
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
    let mut canonical = load_config_copy(config)?;
    canonical.path_config.normalize_canonical_store();
    save_core_config(&canonical, path)
        .map_err(|error| CoreError::ConfigError(error.to_string()))
        .map_err(BridgeFailure::from)
}

fn load_config_copy(config: &ParsConfig) -> Result<ParsConfig, BridgeFailure> {
    toml::to_string(config)
        .map_err(|error| BridgeFailure::from(CoreError::ConfigError(error.to_string())))
        .and_then(|text| {
            toml::from_str(&text)
                .map_err(|error| BridgeFailure::from(CoreError::ConfigError(error.to_string())))
        })
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

fn set_canonical_store(config: &mut ParsConfig, root: &str) {
    config.path_config.default_repo = root.to_string();
    config.path_config.repos = vec![root.to_string()];
}

fn clear_canonical_store(config: &mut ParsConfig) {
    config.path_config.default_repo.clear();
    config.path_config.repos.clear();
}

fn require_empty_canonical_store(config: &ParsConfig) -> Result<(), BridgeFailure> {
    if config.path_config.default_repo.trim().is_empty() {
        return Ok(());
    }
    Err(BridgeFailure::from(CoreError::ValidationError(
        "disconnect or delete the current password store before adding another".to_string(),
    )))
}

fn require_canonical_store(config: &ParsConfig, root: &str) -> Result<(), BridgeFailure> {
    if config.path_config.default_repo == root {
        return Ok(());
    }
    Err(BridgeFailure::from(CoreError::ValidationError(format!(
        "store is not the configured canonical store: {root}"
    ))))
}

fn require_app_managed_root(root: &Path, managed_base: &Path) -> Result<(), BridgeFailure> {
    let base = managed_base.canonicalize().map_err(store_failure)?;
    let candidate = if root.exists() {
        root.canonicalize().map_err(store_failure)?
    } else {
        let parent = root.parent().ok_or_else(|| {
            BridgeFailure::from(CoreError::ValidationError(
                "managed store path has no parent".to_string(),
            ))
        })?;
        let parent = parent.canonicalize().map_err(store_failure)?;
        let name = root.file_name().ok_or_else(|| {
            BridgeFailure::from(CoreError::ValidationError(
                "managed store path has no final component".to_string(),
            ))
        })?;
        parent.join(name)
    };
    if candidate != base && candidate.starts_with(&base) {
        return Ok(());
    }
    Err(BridgeFailure::from(CoreError::ValidationError(
        "refusing to delete a store outside app-managed storage".to_string(),
    )))
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

fn read_regular_gpg_id(path: &Path) -> Option<String> {
    let metadata = fs::symlink_metadata(path).ok()?;
    let file_type = metadata.file_type();
    if file_type.is_symlink() || !file_type.is_file() {
        return None;
    }
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    let mut file = options.open(path).ok()?;
    let after = fs::symlink_metadata(path).ok()?;
    if after.file_type().is_symlink() || !after.file_type().is_file() {
        return None;
    }
    let mut content = String::new();
    file.read_to_string(&mut content).ok()?;
    Some(content)
}

fn pgp_key_missing(
    gpg_id_path: &Path,
    pgp_executable: Option<&str>,
    managed_pgp_keys: Option<&[PgpKeySummary]>,
) -> bool {
    let Some(content) = read_regular_gpg_id(gpg_id_path) else {
        return true;
    };
    let keys = content.lines().map(str::trim).filter(|line| !line.is_empty()).collect::<Vec<_>>();
    if keys.is_empty() {
        return true;
    }
    if let Some(executable) = pgp_executable {
        return keys.iter().all(|key| {
            Command::new(executable)
                .args(["--list-secret-keys", key])
                .output()
                .map(|output| !output.status.success())
                .unwrap_or(true)
        });
    }
    let available = managed_pgp_keys.unwrap_or_default();
    keys.iter().all(|required| {
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

#[allow(dead_code)]
fn git_failure(_error: git2::Error) -> BridgeFailure {
    BridgeFailure::from(CoreError::GitError("Git operation failed".to_string()))
}

#[allow(dead_code)]
fn structured_git_response(
    command: &str,
    operation: impl FnOnce() -> Result<String, BridgeFailure>,
) -> GitCommandResponse {
    match operation() {
        Ok(stdout) => GitCommandResponse {
            output: Some(GitCommandOutputDto {
                command: sanitize_git_text(command),
                stdout: sanitize_git_text(&stdout),
                stderr: String::new(),
                exit_code: Some(0),
                success: true,
            }),
            error: None,
        },
        Err(error) => GitCommandResponse { output: None, error: Some(error) },
    }
}

#[allow(dead_code)]
fn structured_git_status(root: &Path) -> Result<String, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let mut output = String::new();
    let head = repo.head().ok();
    let branch_name =
        head.as_ref().and_then(|reference| reference.shorthand()).unwrap_or("HEAD").to_string();
    output.push_str("## ");
    output.push_str(&branch_name);

    if let Ok(branch) = repo.find_branch(&branch_name, BranchType::Local) {
        if let Ok(upstream) = branch.upstream() {
            let upstream_name = upstream
                .name()
                .ok()
                .flatten()
                .unwrap_or("upstream")
                .trim_start_matches("refs/remotes/")
                .to_string();
            if let (Some(local_oid), Some(upstream_oid)) =
                (branch.get().target(), upstream.get().target())
            {
                let (ahead, behind) =
                    repo.graph_ahead_behind(local_oid, upstream_oid).map_err(git_failure)?;
                output.push_str("...");
                output.push_str(&upstream_name);
                if ahead > 0 || behind > 0 {
                    output.push_str(" [");
                    if ahead > 0 {
                        output.push_str(&format!("ahead {ahead}"));
                    }
                    if ahead > 0 && behind > 0 {
                        output.push_str(", ");
                    }
                    if behind > 0 {
                        output.push_str(&format!("behind {behind}"));
                    }
                    output.push(']');
                }
            }
        }
    }
    output.push('\n');

    let mut options = StatusOptions::new();
    options.include_untracked(true).recurse_untracked_dirs(true).renames_head_to_index(true);
    let statuses = repo.statuses(Some(&mut options)).map_err(git_failure)?;
    for entry in statuses.iter() {
        let path = entry.path().unwrap_or("<unknown>");
        output.push_str(status_code(entry.status()));
        output.push(' ');
        output.push_str(path);
        output.push('\n');
    }
    Ok(output)
}

#[allow(dead_code)]
fn status_code(status: Status) -> &'static str {
    if status.is_conflicted() {
        "UU"
    } else if status.contains(Status::WT_NEW) {
        "??"
    } else if status.contains(Status::INDEX_NEW) {
        "A "
    } else if status.contains(Status::INDEX_DELETED) {
        "D "
    } else if status.contains(Status::WT_DELETED) {
        " D"
    } else if status
        .intersects(Status::INDEX_MODIFIED | Status::INDEX_RENAMED | Status::INDEX_TYPECHANGE)
    {
        "M "
    } else if status.intersects(Status::WT_MODIFIED | Status::WT_RENAMED | Status::WT_TYPECHANGE) {
        " M"
    } else {
        "  "
    }
}

#[allow(dead_code)]
fn structured_git_commit(root: &Path, message: &str) -> Result<String, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let mut index = repo.index().map_err(git_failure)?;
    index.add_all(["*"].iter(), IndexAddOption::DEFAULT, None).map_err(git_failure)?;
    index.update_all(["*"].iter(), None).map_err(git_failure)?;
    index.write().map_err(git_failure)?;
    let tree_oid = index.write_tree().map_err(git_failure)?;
    let tree = repo.find_tree(tree_oid).map_err(git_failure)?;
    let signature = repo
        .signature()
        .or_else(|_| Signature::now("Pars", "pars@localhost"))
        .map_err(git_failure)?;
    let parent =
        repo.head().ok().and_then(|head| head.target()).and_then(|oid| repo.find_commit(oid).ok());
    if parent.as_ref().is_some_and(|commit| commit.tree_id() == tree_oid) {
        return Err(BridgeFailure::from(CoreError::GitError("nothing to commit".to_string())));
    }
    let oid = match parent.as_ref() {
        Some(parent) => repo
            .commit(Some("HEAD"), &signature, &signature, message, &tree, &[parent])
            .map_err(git_failure)?,
        None => repo
            .commit(Some("HEAD"), &signature, &signature, message, &tree, &[])
            .map_err(git_failure)?,
    };
    Ok(format!("[{oid}] {message}\n"))
}

#[allow(dead_code)]
fn structured_git_list_remotes(root: &Path) -> Result<String, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let names = repo.remotes().map_err(git_failure)?;
    let mut output = String::new();
    for name in names.iter().flatten() {
        let remote = repo.find_remote(name).map_err(git_failure)?;
        if let Some(url) = remote.url() {
            output.push_str(&format!("{name}\t{} (fetch)\n", sanitized_remote_url(url)));
        }
        let push_url = remote.pushurl().or_else(|| remote.url());
        if let Some(url) = push_url {
            output.push_str(&format!("{name}\t{} (push)\n", sanitized_remote_url(url)));
        }
    }
    Ok(output)
}

fn sanitized_remote_url(url: &str) -> String {
    let mut value = url.split(['?', '#']).next().unwrap_or(url).to_string();
    if let Some(scheme_end) = value.find("://") {
        let authority_start = scheme_end + 3;
        let authority_end = value[authority_start..]
            .find('/')
            .map(|index| authority_start + index)
            .unwrap_or(value.len());
        if let Some(at) = value[authority_start..authority_end].rfind('@') {
            value.replace_range(authority_start..authority_start + at + 1, "***@");
        }
    } else if let Some(at) = value.rfind('@') {
        let userinfo = &value[..at];
        let host_path = &value[at + 1..];
        if !userinfo.contains(['/', '\\'])
            && host_path.split_once(':').is_some_and(|(host, path)| {
                !host.is_empty() && !path.is_empty() && !host.contains(['/', '\\'])
            })
        {
            value.replace_range(..at + 1, "***@");
        }
    }
    value
}

fn sanitize_git_text(raw: &str) -> String {
    raw.split_inclusive(char::is_whitespace)
        .map(|part| {
            let content_len = part.trim_end_matches(char::is_whitespace).len();
            let (content, whitespace) = part.split_at(content_len);
            format!("{}{}", sanitize_git_token(content), whitespace)
        })
        .collect()
}

fn sanitize_git_token(token: &str) -> String {
    let leading_len = token
        .chars()
        .take_while(|value| matches!(value, '\'' | '"' | '(' | '[' | '{'))
        .map(char::len_utf8)
        .sum::<usize>();
    let trailing_len = token
        .chars()
        .rev()
        .take_while(|value| matches!(value, '\'' | '"' | ')' | ']' | '}' | ',' | ';'))
        .map(char::len_utf8)
        .sum::<usize>();
    if leading_len + trailing_len > token.len() {
        return token.to_string();
    }
    let core_end = token.len() - trailing_len;
    let core = &token[leading_len..core_end];
    let sanitized = if core.starts_with("content://") || core.starts_with("file://") {
        "[uri]".to_string()
    } else if core.contains("://") {
        sanitized_remote_url(core)
    } else if core.starts_with('/')
        || (core.len() > 2
            && core.as_bytes()[1] == b':'
            && matches!(core.as_bytes()[2], b'\\' | b'/'))
    {
        "[path]".to_string()
    } else {
        sanitized_remote_url(core)
    };
    format!("{}{}{}", &token[..leading_len], sanitized, &token[core_end..])
}

#[derive(Clone, Copy)]
enum GitRemoteMutation {
    Add,
    SetUrl,
    Remove,
}

fn structured_or_system_remote_response(
    _command: String,
    request: GitRemoteRequest,
    mutation: GitRemoteMutation,
) -> GitCommandResponse {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        structured_git_response(&_command, || {
            structured_git_remote_mutation(Path::new(&request.root), &request, mutation)
        })
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let mut args = vec!["remote".to_string()];
        match mutation {
            GitRemoteMutation::Add => {
                args.push("add".to_string());
                args.push(request.name);
                args.push(request.url.unwrap_or_default());
            }
            GitRemoteMutation::SetUrl => {
                args.push("set-url".to_string());
                args.push(request.name);
                args.push(request.url.unwrap_or_default());
            }
            GitRemoteMutation::Remove => {
                args.push("remove".to_string());
                args.push(request.name);
            }
        }
        run_git_command_response_owned(request.root, args)
    }
}

#[allow(dead_code)]
fn structured_git_remote_mutation(
    root: &Path,
    request: &GitRemoteRequest,
    mutation: GitRemoteMutation,
) -> Result<String, BridgeFailure> {
    let name = request.name.trim();
    if name.is_empty() {
        return Err(BridgeFailure::from(CoreError::ValidationError(
            "Git remote name is required".to_string(),
        )));
    }
    let repo = Repository::open(root).map_err(git_failure)?;
    match mutation {
        GitRemoteMutation::Add => {
            let url = required_remote_url(request)?;
            repo.remote(name, url).map_err(git_failure)?;
        }
        GitRemoteMutation::SetUrl => {
            let url = required_remote_url(request)?;
            repo.remote_set_url(name, url).map_err(git_failure)?;
        }
        GitRemoteMutation::Remove => repo.remote_delete(name).map_err(git_failure)?,
    }
    Ok(String::new())
}

#[allow(dead_code)]
fn required_remote_url(request: &GitRemoteRequest) -> Result<&str, BridgeFailure> {
    request.url.as_deref().map(str::trim).filter(|url| !url.is_empty()).ok_or_else(|| {
        BridgeFailure::from(CoreError::ValidationError("Git remote URL is required".to_string()))
    })
}

#[allow(dead_code)]
fn git_remote_callbacks(
    ssh_private_key_path: Option<&Path>,
    ssh_dir: Option<&Path>,
) -> Result<RemoteCallbacks<'static>, BridgeFailure> {
    let mut callbacks = RemoteCallbacks::new();
    if let Some(private_key_path) = ssh_private_key_path {
        let ssh_dir = ssh_dir.ok_or_else(|| {
            BridgeFailure::from(CoreError::ValidationError(
                "SSH key directory is required".to_string(),
            ))
        })?;
        let root = ssh_dir.canonicalize().map_err(store_failure)?;
        let metadata = fs::symlink_metadata(private_key_path).map_err(store_failure)?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(BridgeFailure::from(CoreError::ValidationError(
                "SSH private key must be a regular managed file".to_string(),
            )));
        }
        let key_path = private_key_path.canonicalize().map_err(store_failure)?;
        if !key_path.starts_with(&root) || key_path == root {
            return Err(BridgeFailure::from(CoreError::ValidationError(
                "SSH private key is outside managed storage".to_string(),
            )));
        }
        callbacks.credentials(move |_url, username, allowed| {
            if !allowed.contains(CredentialType::SSH_KEY) {
                return Err(git2::Error::from_str("SSH key credentials are not accepted"));
            }
            Cred::ssh_key(username.unwrap_or("git"), None, &key_path, None)
        });
    }
    Ok(callbacks)
}

#[derive(Debug)]
struct ConfiguredUpstream {
    local_ref: String,
    branch_name: String,
    remote_name: String,
    merge_ref: String,
}

#[allow(dead_code)]
fn configured_upstream(repo: &Repository) -> Result<ConfiguredUpstream, BridgeFailure> {
    let head = repo.head().map_err(git_failure)?;
    if !head.is_branch() {
        return Err(BridgeFailure::from(CoreError::GitError(
            "current Git HEAD is detached".to_string(),
        )));
    }
    let local_ref = head.name().ok_or_else(|| {
        BridgeFailure::from(CoreError::GitError("current branch has no reference name".into()))
    })?;
    let branch_name = head.shorthand().ok_or_else(|| {
        BridgeFailure::from(CoreError::GitError("current branch has no name".into()))
    })?;
    let config = repo.config().map_err(git_failure)?;
    let remote_name = config.get_string(&format!("branch.{branch_name}.remote")).map_err(|_| {
        BridgeFailure::from(CoreError::GitError(
            "current branch has no configured upstream".to_string(),
        ))
    })?;
    let merge_ref = config.get_string(&format!("branch.{branch_name}.merge")).map_err(|_| {
        BridgeFailure::from(CoreError::GitError(
            "current branch has no configured upstream".to_string(),
        ))
    })?;
    if remote_name == "." || !merge_ref.starts_with("refs/heads/") {
        return Err(BridgeFailure::from(CoreError::GitError(
            "current branch has an unsupported upstream".to_string(),
        )));
    }
    Ok(ConfiguredUpstream {
        local_ref: local_ref.to_string(),
        branch_name: branch_name.to_string(),
        remote_name,
        merge_ref,
    })
}

#[allow(dead_code)]
fn structured_git_pull(
    root: &Path,
    ssh_private_key_path: Option<&Path>,
    ssh_dir: Option<&Path>,
) -> Result<String, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let upstream = configured_upstream(&repo)?;
    let mut remote = repo.find_remote(&upstream.remote_name).map_err(git_failure)?;
    let mut fetch_options = FetchOptions::new();
    fetch_options.remote_callbacks(git_remote_callbacks(ssh_private_key_path, ssh_dir)?);
    remote
        .fetch(&[upstream.merge_ref.as_str()], Some(&mut fetch_options), None)
        .map_err(git_failure)?;
    drop(remote);
    let branch = repo.find_branch(&upstream.branch_name, BranchType::Local).map_err(git_failure)?;
    let upstream_branch = branch.upstream().map_err(|_| {
        BridgeFailure::from(CoreError::GitError(
            "current branch has no configured upstream".to_string(),
        ))
    })?;
    let target = upstream_branch.get().target().ok_or_else(|| {
        BridgeFailure::from(CoreError::GitError("upstream branch has no target".to_string()))
    })?;
    let annotated = repo.find_annotated_commit(target).map_err(git_failure)?;
    let (analysis, _) = repo.merge_analysis(&[&annotated]).map_err(git_failure)?;
    if analysis.is_up_to_date() {
        return Ok("Already up to date.\n".to_string());
    }
    if !analysis.is_fast_forward() {
        return Err(BridgeFailure::from(CoreError::GitError(
            "mobile pull requires a fast-forward; resolve divergence with desktop Git".to_string(),
        )));
    }
    let target_object = repo.find_object(target, None).map_err(git_failure)?;
    repo.checkout_tree(&target_object, Some(CheckoutBuilder::new().safe())).map_err(git_failure)?;
    let mut reference = repo.find_reference(&upstream.local_ref).map_err(git_failure)?;
    reference.set_target(target, "Pars fast-forward pull").map_err(git_failure)?;
    repo.set_head(&upstream.local_ref).map_err(git_failure)?;
    Ok(format!("Fast-forwarded to {target}.\n"))
}

#[allow(dead_code)]
fn structured_git_push(
    root: &Path,
    ssh_private_key_path: Option<&Path>,
    ssh_dir: Option<&Path>,
) -> Result<String, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let upstream = configured_upstream(&repo)?;
    let refspec = format!("{}:{}", upstream.local_ref, upstream.merge_ref);
    let mut remote = repo.find_remote(&upstream.remote_name).map_err(git_failure)?;
    let mut push_options = PushOptions::new();
    push_options.remote_callbacks(git_remote_callbacks(ssh_private_key_path, ssh_dir)?);
    remote.push(&[&refspec], Some(&mut push_options)).map_err(git_failure)?;
    Ok(format!("Pushed {} to {}.\n", upstream.local_ref, upstream.remote_name))
}

fn init_git_repository(root: &Path) -> Result<(), BridgeFailure> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        Repository::init(root).map(|_| ()).map_err(git_failure)
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        run_system_git(root, &["init"])
    }
}

fn clone_git_repository(
    remote_url: &str,
    root: &Path,
    ssh_private_key_path: Option<&str>,
    ssh_dir: Option<&str>,
) -> Result<(), BridgeFailure> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let mut builder = RepoBuilder::new();
        let mut fetch = FetchOptions::new();
        fetch.remote_callbacks(git_remote_callbacks(
            ssh_private_key_path.map(Path::new),
            ssh_dir.map(Path::new),
        )?);
        builder.fetch_options(fetch);
        builder.clone(remote_url, root).map(|_| ()).map_err(git_failure)
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let _ = (ssh_private_key_path, ssh_dir);
        let output = Command::new("git")
            .args(["clone", remote_url, &root.display().to_string()])
            .output()
            .map_err(|_| {
                BridgeFailure::from(CoreError::GitError("Git command failed".to_string()))
            })?;
        if output.status.success() {
            Ok(())
        } else {
            Err(BridgeFailure::from(CoreError::GitError("Git command failed".to_string())))
        }
    }
}

#[allow(dead_code)]
fn run_system_git(root: &Path, args: &[&str]) -> Result<(), BridgeFailure> {
    let output = Command::new("git")
        .args(args)
        .current_dir(root)
        .output()
        .map_err(|error| BridgeFailure::from(CoreError::GitError(error.to_string())))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(BridgeFailure::from(CoreError::GitError("Git command failed".to_string())))
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

#[allow(dead_code)]
fn run_git_command_response(root: String, args: Vec<&str>) -> GitCommandResponse {
    run_git_command_response_owned(root, args.into_iter().map(str::to_string).collect::<Vec<_>>())
}

#[allow(dead_code)]
fn run_git_command_response_owned(root: String, args: Vec<String>) -> GitCommandResponse {
    match GitOperationRequest::new(PathBuf::from(root), args).and_then(gui::run_git_args) {
        Ok(output) => GitCommandResponse { output: Some(output.into()), error: None },
        Err(error) => GitCommandResponse { output: None, error: Some(BridgeFailure::from(error)) },
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
            command: sanitize_git_text(&value.command),
            stdout: sanitize_git_text(&value.stdout),
            stderr: sanitize_git_text(&value.stderr),
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
        Self { path: value.path, is_favorite: value.is_favorite }
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
    fn pure_rust_key_check_accepts_any_matching_private_recipient() {
        let temp = tempfile::tempdir().expect("tempdir");
        let gpg_id = temp.path().join(".gpg-id");
        fs::write(&gpg_id, "A1B2C3D4\nDEADBEEF\n").expect("gpg id");
        let matching_private = key("00000000A1B2C3D4", "Alice", true);
        let unrelated_public = key("DEADBEEF", "Bob", false);
        assert!(!pgp_key_missing(&gpg_id, None, Some(&[matching_private, unrelated_public])));
        let matching_public = key("00000000A1B2C3D4", "Alice", false);
        assert!(pgp_key_missing(&gpg_id, None, Some(&[matching_public])));
    }

    #[test]
    fn pure_rust_key_check_accepts_identity_email() {
        let temp = tempfile::tempdir().expect("tempdir");
        let gpg_id = temp.path().join(".gpg-id");
        fs::write(&gpg_id, "alice@example.com").expect("gpg id");
        let private = key("A1B2C3D4", "Alice <alice@example.com>", true);

        assert!(!pgp_key_missing(&gpg_id, None, Some(&[private])));
    }

    fn init_test_repository(root: &Path) -> Repository {
        let repo = Repository::init(root).expect("init repository");
        let mut config = repo.config().expect("repo config");
        config.set_str("user.name", "Pars Test").expect("user name");
        config.set_str("user.email", "pars@example.invalid").expect("user email");
        repo
    }

    #[test]
    fn remote_url_sanitization_removes_userinfo_query_and_fragment() {
        assert_eq!(
            sanitized_remote_url("https://token@example.com/pass.git?access_token=secret#x"),
            "https://***@example.com/pass.git"
        );
        assert_eq!(
            sanitized_remote_url("git@example.com:org/pass.git"),
            "***@example.com:org/pass.git"
        );
        assert_eq!(
            sanitized_remote_url("token-123@example.com:org/pass.git?secret=yes"),
            "***@example.com:org/pass.git"
        );
    }

    #[test]
    fn git_output_sanitization_redacts_credentials_uris_and_private_paths() {
        let raw =
            "git remote set-url origin https://token@example.com/pass.git?access_token=secret#x\n\
                   fatal: cannot open /data/user/0/top.vollate.pars_gui/files/store\n\
                   provider content://com.example.documents/tree/private-id";
        let sanitized = sanitize_git_text(raw);
        assert!(sanitized.contains("https://***@example.com/pass.git"));
        assert!(sanitized.contains("[path]"));
        assert!(sanitized.contains("[uri]"));
        assert!(!sanitized.contains("token@example"));
        assert!(!sanitized.contains("access_token"));
        assert!(!sanitized.contains("private-id"));
    }

    #[test]
    fn git_command_output_conversion_sanitizes_system_git_fields() {
        let output = gui::GitCommandOutput {
            command: "git remote add origin https://secret@example.com/pass.git?token=x".into(),
            stdout: "added https://secret@example.com/pass.git#fragment".into(),
            stderr: "failed at /Users/alice/Library/Application Support/Pars".into(),
            exit_code: Some(1),
            success: false,
        };
        let dto = GitCommandOutputDto::from(output);
        assert!(!dto.command.contains("secret@example"));
        assert!(!dto.command.contains("?token"));
        assert!(!dto.stdout.contains("#fragment"));
        assert!(!dto.stderr.contains("/Users/alice"));
    }

    #[test]
    fn structured_git_status_commit_and_remotes_use_repository_data() {
        let temp = tempfile::tempdir().expect("tempdir");
        let root = temp.path().join("store");
        fs::create_dir_all(&root).expect("store root");
        let repo = init_test_repository(&root);
        fs::write(root.join(".gpg-id"), "ABC\n").expect("gpg id");
        fs::write(root.join("entry.gpg"), b"ciphertext").expect("entry");

        let first = structured_git_commit(&root, "Initial password store").expect("first commit");
        assert!(first.contains("Initial password store"));
        let first_oid = repo.head().expect("head").target().expect("head oid");
        fs::write(root.join("entry.gpg"), b"changed ciphertext").expect("changed entry");
        let dirty = structured_git_status(&root).expect("dirty status");
        assert!(dirty.lines().any(|line| line.ends_with("entry.gpg")), "{dirty}");
        structured_git_commit(&root, "Update entry").expect("second commit");
        let second_oid = repo.head().expect("head").target().expect("head oid");
        assert_ne!(first_oid, second_oid);
        assert_eq!(repo.find_commit(second_oid).unwrap().parent_id(0).unwrap(), first_oid);

        repo.remote("origin", "https://example.invalid/passwords.git").expect("add remote");
        let remotes = structured_git_list_remotes(&root).expect("list remotes");
        assert!(remotes.contains("origin\thttps://example.invalid/passwords.git (fetch)"));
        assert!(remotes.contains("origin\thttps://example.invalid/passwords.git (push)"));
    }

    #[test]
    fn structured_git_push_rejects_untracked_and_detached_heads() {
        let temp = tempfile::tempdir().expect("tempdir");
        let root = temp.path().join("store");
        fs::create_dir_all(&root).unwrap();
        let repo = init_test_repository(&root);
        fs::write(root.join(".gpg-id"), "ABC\n").unwrap();
        structured_git_commit(&root, "Initial").unwrap();
        assert!(structured_git_push(&root, None, None).is_err());
        let oid = repo.head().unwrap().target().unwrap();
        repo.set_head_detached(oid).unwrap();
        assert!(structured_git_push(&root, None, None).is_err());
    }

    #[test]
    fn structured_git_push_and_fast_forward_pull_work_with_local_remote() {
        let temp = tempfile::tempdir().expect("tempdir");
        let bare_path = temp.path().join("remote.git");
        let bare = Repository::init_bare(&bare_path).expect("bare remote");

        let source_path = temp.path().join("source");
        fs::create_dir_all(&source_path).expect("source root");
        let source = init_test_repository(&source_path);
        fs::write(source_path.join(".gpg-id"), "ABC\n").expect("gpg id");
        structured_git_commit(&source_path, "Initial").expect("initial commit");
        source.remote("backup", bare_path.to_str().expect("remote path")).expect("backup");
        let branch_name = source.head().unwrap().shorthand().unwrap().to_string();
        let mut config = source.config().unwrap();
        config.set_str(&format!("branch.{branch_name}.remote"), "backup").unwrap();
        config.set_str(&format!("branch.{branch_name}.merge"), "refs/heads/mobile-main").unwrap();
        structured_git_push(&source_path, None, None).expect("initial push");
        bare.set_head("refs/heads/mobile-main").expect("remote head");

        let clone_path = temp.path().join("clone");
        let clone = Repository::clone(bare_path.to_str().unwrap(), &clone_path).expect("clone");
        let clone_branch = clone.head().unwrap().shorthand().unwrap().to_string();
        let mut clone_config = clone.config().unwrap();
        clone_config.set_str(&format!("branch.{clone_branch}.remote"), "origin").unwrap();
        clone_config
            .set_str(&format!("branch.{clone_branch}.merge"), "refs/heads/mobile-main")
            .unwrap();
        fs::write(source_path.join("entry.gpg"), b"ciphertext").expect("new entry");
        structured_git_commit(&source_path, "Second").expect("second commit");
        structured_git_push(&source_path, None, None).expect("second push");

        let before = Repository::open(&clone_path).unwrap().head().unwrap().target().unwrap();
        let pull = structured_git_pull(&clone_path, None, None).expect("fast-forward pull");
        assert!(pull.contains("Fast-forwarded"));
        let after = Repository::open(&clone_path).unwrap().head().unwrap().target().unwrap();
        assert_ne!(before, after);
        assert!(clone_path.join("entry.gpg").is_file());
    }

    #[test]
    fn ssh_callbacks_require_regular_key_inside_managed_root() {
        let temp = tempfile::tempdir().expect("tempdir");
        let ssh_dir = temp.path().join("ssh");
        fs::create_dir_all(&ssh_dir).unwrap();
        let key_path = ssh_dir.join("mobile-key");
        fs::write(&key_path, "synthetic-private-key").unwrap();
        assert!(git_remote_callbacks(Some(&key_path), Some(&ssh_dir)).is_ok());
        let outside = temp.path().join("outside-key");
        fs::write(&outside, "synthetic-private-key").unwrap();
        assert!(git_remote_callbacks(Some(&outside), Some(&ssh_dir)).is_err());
        assert!(git_remote_callbacks(Some(&key_path), None).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn ssh_callbacks_reject_symlinked_private_key() {
        use std::os::unix::fs::symlink;
        let temp = tempfile::tempdir().expect("tempdir");
        let ssh_dir = temp.path().join("ssh");
        fs::create_dir_all(&ssh_dir).unwrap();
        let target = ssh_dir.join("target");
        fs::write(&target, "synthetic-private-key").unwrap();
        let link = ssh_dir.join("link");
        symlink(&target, &link).unwrap();
        assert!(git_remote_callbacks(Some(&link), Some(&ssh_dir)).is_err());
    }

    #[test]
    fn git_mode_rejects_external_git_pointer() {
        let temp = tempfile::tempdir().expect("tempdir");
        let external = temp.path().join("external");
        fs::create_dir_all(&external).unwrap();
        Repository::init(&external).unwrap();
        let staged = temp.path().join("staged");
        fs::create_dir_all(&staged).unwrap();
        fs::write(staged.join(".git"), format!("gitdir: {}\n", external.join(".git").display()))
            .unwrap();
        assert_eq!(inspect_git_mode(&staged), StoreGitModeDto::Invalid);
    }

    #[test]
    fn app_managed_root_accepts_missing_direct_child() {
        let temp = tempfile::tempdir().expect("tempdir");
        let base = temp.path().join("stores");
        fs::create_dir_all(&base).unwrap();
        assert!(require_app_managed_root(&base.join("missing"), &base).is_ok());
        assert!(require_app_managed_root(&temp.path().join("outside"), &base).is_err());
    }

    #[test]
    fn create_store_refuses_existing_paths_without_changing_recipients() {
        let temp = tempfile::tempdir().unwrap();
        let directory = temp.path().join("existing");
        fs::create_dir(&directory).unwrap();
        fs::write(directory.join(".gpg-id"), "OLD\n").unwrap();
        assert!(create_new_store_tree(&directory, &["NEW".into()], |_| Ok(())).is_err());
        assert_eq!(fs::read_to_string(directory.join(".gpg-id")).unwrap(), "OLD\n");

        let file = temp.path().join("file-store");
        fs::write(&file, "marker").unwrap();
        assert!(create_new_store_tree(&file, &["NEW".into()], |_| Ok(())).is_err());
        assert_eq!(fs::read_to_string(&file).unwrap(), "marker");
    }

    #[cfg(unix)]
    #[test]
    fn create_store_refuses_symlink_and_raced_target() {
        use std::os::unix::fs::symlink;
        let temp = tempfile::tempdir().unwrap();
        let external = temp.path().join("external");
        fs::create_dir(&external).unwrap();
        fs::write(external.join(".gpg-id"), "OLD\n").unwrap();
        let link = temp.path().join("linked-store");
        symlink(&external, &link).unwrap();
        assert!(create_new_store_tree(&link, &["NEW".into()], |_| Ok(())).is_err());
        assert_eq!(fs::read_to_string(external.join(".gpg-id")).unwrap(), "OLD\n");

        let raced = temp.path().join("raced-store");
        let result = create_new_store_tree(&raced, &["NEW".into()], |_| {
            fs::create_dir(&raced).map_err(store_failure)?;
            fs::write(raced.join("marker"), "raced").map_err(store_failure)?;
            Ok(())
        });
        assert!(result.is_err());
        assert_eq!(fs::read_to_string(raced.join("marker")).unwrap(), "raced");
        assert!(!raced.join(".gpg-id").exists());
    }

    #[test]
    fn create_store_cleans_staging_on_prepare_and_config_failure() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("prepare-failure");
        let result = create_new_store_tree(&root, &["ABC".into()], |_| {
            Err(BridgeFailure::from(CoreError::GitError("synthetic failure".into())))
        });
        assert!(result.is_err());
        assert!(!root.exists());
        assert!(fs::read_dir(temp.path()).unwrap().all(|entry| !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".pars-create-")));

        let config_directory = temp.path().join("config-as-directory");
        fs::create_dir(&config_directory).unwrap();
        let installed = temp.path().join("config-failure");
        let result = create_local_store_inner(CreateLocalStoreRequest {
            config_path: config_directory.display().to_string(),
            name: "Synthetic".into(),
            root: installed.display().to_string(),
            pgp_keys: vec!["ABC".into()],
            initialize_git: false,
        });
        assert!(result.is_err());
        assert!(!installed.exists());
    }

    #[cfg(unix)]
    #[test]
    fn git_mode_treats_metadata_permission_error_as_invalid() {
        use std::os::unix::fs::PermissionsExt;
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("store");
        fs::create_dir(&root).unwrap();
        fs::set_permissions(&root, fs::Permissions::from_mode(0o000)).unwrap();
        let mode = inspect_git_mode(&root);
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
        assert_eq!(mode, StoreGitModeDto::Invalid);
    }

    #[test]
    fn git_mode_distinguishes_absent_valid_and_invalid_metadata() {
        let temp = tempfile::tempdir().expect("tempdir");
        let root = temp.path().join("store");
        fs::create_dir_all(&root).unwrap();
        assert_eq!(inspect_git_mode(&root), StoreGitModeDto::Disabled);
        Repository::init(&root).unwrap();
        assert_eq!(inspect_git_mode(&root), StoreGitModeDto::Local);
        fs::remove_dir_all(root.join(".git")).unwrap();
        fs::write(root.join(".git"), "gitdir: /missing/worktree").unwrap();
        assert_eq!(inspect_git_mode(&root), StoreGitModeDto::Invalid);
    }
}
