use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::{fs, io};

use passwords::PasswordGenerator;
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::pgp::backend::{PgpBackend, SystemGpgBackend};

pub type GuiResult<T> = Result<T, CoreError>;

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub enum CoreError {
    ConfigError(String),
    StoreError(String),
    PgpError(String),
    GitError(String),
    ClipboardError(String),
    ValidationError(String),
    Conflict(EntryConflict),
    UnsupportedPlatform(String),
}

impl Display for CoreError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreError::ConfigError(message) => write!(f, "config error: {message}"),
            CoreError::StoreError(message) => write!(f, "store error: {message}"),
            CoreError::PgpError(message) => write!(f, "pgp error: {message}"),
            CoreError::GitError(message) => write!(f, "git error: {message}"),
            CoreError::ClipboardError(message) => write!(f, "clipboard error: {message}"),
            CoreError::ValidationError(message) => write!(f, "validation error: {message}"),
            CoreError::Conflict(conflict) => write!(f, "conflict: {conflict}"),
            CoreError::UnsupportedPlatform(message) => {
                write!(f, "unsupported platform: {message}")
            }
        }
    }
}

impl Error for CoreError {}

impl From<io::Error> for CoreError {
    fn from(value: io::Error) -> Self {
        CoreError::StoreError(value.to_string())
    }
}

impl From<walkdir::Error> for CoreError {
    fn from(value: walkdir::Error) -> Self {
        CoreError::StoreError(value.to_string())
    }
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct StoreId(pub String);

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct StoreInfo {
    pub id: StoreId,
    pub name: String,
    pub root: PathBuf,
    pub is_default: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct StoreStatus {
    pub store: StoreInfo,
    pub git_status: Option<GitStatusSummary>,
    pub has_gpg_id: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GitStatusSummary {
    pub branch: Option<String>,
    pub is_clean: bool,
    pub has_remote: bool,
    pub ahead: usize,
    pub behind: usize,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GitCommandOutput {
    pub command: String,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: Option<i32>,
    pub success: bool,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize, Deserialize)]
pub enum EntryConflictKind {
    EntryAlreadyExists,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EntryConflict {
    pub kind: EntryConflictKind,
    pub path: String,
}

impl EntryConflict {
    pub fn already_exists(path: impl Into<String>) -> Self {
        Self { kind: EntryConflictKind::EntryAlreadyExists, path: path.into() }
    }
}

impl Display for EntryConflict {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self.kind {
            EntryConflictKind::EntryAlreadyExists => {
                write!(f, "entry already exists: {}", self.path)
            }
        }
    }
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EntryRef {
    pub root: PathBuf,
    pub path: String,
}

impl EntryRef {
    pub fn new(root: PathBuf, path: impl AsRef<str>) -> GuiResult<Self> {
        let path = normalize_entry_path(path.as_ref())?;
        Ok(Self { root, path })
    }

    pub fn encrypted_path(&self) -> PathBuf {
        self.root.join(format!("{}.gpg", self.path))
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize, Deserialize)]
pub enum EntryType {
    Directory,
    Password,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EntrySummary {
    pub path: String,
    pub name: String,
    pub parent_path: Option<String>,
    pub entry_type: EntryType,
    pub child_count: usize,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct DeleteEntryResult {
    pub deleted_path: String,
    pub deleted_type: EntryType,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct InsertEntryResult {
    pub entry_path: String,
    pub overwrote_existing: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EntryMutationResult {
    pub path: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GenerateEntryResult {
    pub entry_path: String,
    pub password: String,
    pub overwrote_existing: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct ParsedEntryField {
    pub key: String,
    pub label: String,
    pub value: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EntrySecret {
    pub password: String,
    pub fields: Vec<ParsedEntryField>,
    pub raw_notes: String,
}

impl EntrySecret {
    pub fn field_value(&self, key: &str) -> Option<&str> {
        self.fields.iter().find(|field| field.key == key).map(|field| field.value.as_str())
    }
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct PgpKeySummary {
    pub identity: String,
    pub fingerprint: String,
    pub has_private_key: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct SshKeySummary {
    pub name: String,
    pub fingerprint: String,
    pub has_private_key: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct KeyImportResult {
    pub fingerprint: String,
    pub imported_private_key: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct KeyExportResult {
    pub armored_text: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct ListEntriesRequest {
    pub root: PathBuf,
    pub target: Option<String>,
    pub recursive: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct ReadEntryRequest {
    pub entry: EntryRef,
    pub pgp_executable: String,
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct InsertEntryRequest {
    pub entry: EntryRef,
    pub content: String,
    pub overwrite: bool,
    pub pgp_executable: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GenerateEntryRequest {
    pub entry: EntryRef,
    pub length: usize,
    pub no_symbols: bool,
    pub overwrite: bool,
    pub pgp_executable: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EditEntryRequest {
    pub entry: EntryRef,
    pub content: String,
    pub pgp_executable: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct MoveEntryRequest {
    pub from: EntryRef,
    pub to: EntryRef,
    pub overwrite: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct DeleteEntryRequest {
    pub entry: EntryRef,
    pub recursive: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct BatchOperationRequest {
    pub entries: Vec<EntryRef>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GitOperationRequest {
    pub root: PathBuf,
    pub args: Vec<String>,
}

impl GitOperationRequest {
    pub fn new(root: PathBuf, args: Vec<String>) -> GuiResult<Self> {
        validate_git_args(&args)?;
        Ok(Self { root, args })
    }
}

pub fn validate_git_args(args: &[String]) -> GuiResult<()> {
    if args.is_empty() {
        return Err(CoreError::ValidationError("git args cannot be empty".to_string()));
    }

    for arg in args {
        let trimmed = arg.trim();
        if trimmed.is_empty() {
            return Err(CoreError::ValidationError(
                "git args cannot contain empty values".to_string(),
            ));
        }

        if trimmed == "git" {
            return Err(CoreError::ValidationError(
                "enter only args after git, for example: status".to_string(),
            ));
        }

        if contains_shell_syntax(trimmed) {
            return Err(CoreError::ValidationError(format!(
                "shell syntax is not allowed in git args: {trimmed}"
            )));
        }
    }

    Ok(())
}

pub fn run_git_args(request: GitOperationRequest) -> GuiResult<GitCommandOutput> {
    validate_git_args(&request.args)?;
    if !request.root.is_dir() {
        return Err(CoreError::StoreError(format!(
            "git working directory does not exist: {}",
            request.root.display()
        )));
    }

    let output = Command::new("git")
        .args(&request.args)
        .current_dir(&request.root)
        .output()
        .map_err(|err| CoreError::GitError(err.to_string()))?;

    Ok(GitCommandOutput {
        command: format!("git {}", request.args.join(" ")),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        exit_code: output.status.code(),
        success: output.status.success(),
    })
}

pub fn list_entries(request: ListEntriesRequest) -> GuiResult<Vec<EntrySummary>> {
    let root = request.root;
    if !root.is_dir() {
        return Err(CoreError::StoreError(format!(
            "password store root does not exist: {}",
            root.display()
        )));
    }

    let target = match request.target {
        Some(target) => Some(normalize_entry_path(&target)?),
        None => None,
    };
    let walk_root = target.as_ref().map(|target| root.join(target)).unwrap_or_else(|| root.clone());

    if !walk_root.exists() {
        return Err(CoreError::StoreError(format!(
            "entry target does not exist: {}",
            walk_root.display()
        )));
    }

    let mut paths = BTreeSet::<String>::new();
    let mut entry_types = BTreeMap::<String, EntryType>::new();

    for entry in WalkDir::new(&walk_root)
        .min_depth(1)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| entry.file_name() != ".git")
    {
        let entry = entry?;
        let path = entry.path();
        if !entry.file_type().is_file()
            || !path.extension().is_some_and(|extension| extension == "gpg")
        {
            continue;
        }

        let relative_to_walk_root = path.strip_prefix(&walk_root).map_err(|_| {
            CoreError::ValidationError(format!(
                "entry path is outside password store target: {}",
                path.display()
            ))
        })?;
        let relative_components = relative_to_walk_root.components().collect::<Vec<_>>();
        if request.recursive || relative_components.len() == 1 {
            let store_path = store_path_from_fs_path(&root, path, true)?;
            paths.insert(store_path.clone());
            entry_types.insert(store_path, EntryType::Password);
        }

        if request.recursive {
            let mut parent = path.parent();
            while let Some(directory) = parent {
                if directory == walk_root {
                    break;
                }
                if !directory.starts_with(&walk_root) {
                    break;
                }
                let store_path = store_path_from_fs_path(&root, directory, false)?;
                paths.insert(store_path.clone());
                entry_types.insert(store_path, EntryType::Directory);
                parent = directory.parent();
            }
        } else if relative_components.len() > 1 {
            let directory = walk_root.join(relative_components[0].as_os_str());
            let store_path = store_path_from_fs_path(&root, &directory, false)?;
            paths.insert(store_path.clone());
            entry_types.insert(store_path, EntryType::Directory);
        }
    }

    let child_counts = child_counts(&paths);

    Ok(paths
        .into_iter()
        .map(|path| {
            let name = entry_name(&path);
            let parent_path = parent_path(&path);
            let entry_type = *entry_types.get(&path).unwrap_or(&EntryType::Directory);
            let child_count = child_counts.get(&path).copied().unwrap_or(0);
            EntrySummary { path, name, parent_path, entry_type, child_count }
        })
        .collect())
}

pub fn delete_entry(request: DeleteEntryRequest) -> GuiResult<DeleteEntryResult> {
    let encrypted_path = request.entry.encrypted_path();
    if encrypted_path.is_file() {
        fs::remove_file(&encrypted_path)?;
        return Ok(DeleteEntryResult {
            deleted_path: request.entry.path,
            deleted_type: EntryType::Password,
        });
    }

    let directory_path = request.entry.root.join(&request.entry.path);
    if !directory_path.exists() {
        return Err(CoreError::StoreError(format!("entry does not exist: {}", request.entry.path)));
    }

    let metadata = fs::symlink_metadata(&directory_path)?;
    if metadata.file_type().is_symlink() {
        return Err(CoreError::ValidationError(format!(
            "refusing to delete symlink entry: {}",
            request.entry.path
        )));
    }

    if !metadata.is_dir() {
        return Err(CoreError::StoreError(format!(
            "entry is neither password file nor directory: {}",
            request.entry.path
        )));
    }

    if !request.recursive {
        return Err(CoreError::ValidationError(format!(
            "directory deletion requires recursive=true: {}",
            request.entry.path
        )));
    }

    fs::remove_dir_all(&directory_path)?;
    Ok(DeleteEntryResult { deleted_path: request.entry.path, deleted_type: EntryType::Directory })
}

pub fn insert_entry(request: InsertEntryRequest) -> GuiResult<InsertEntryResult> {
    let backend = SystemGpgBackend::new(request.pgp_executable.clone());
    insert_entry_with_backend(request, &backend)
}

pub fn insert_entry_with_backend(
    request: InsertEntryRequest,
    backend: &dyn PgpBackend,
) -> GuiResult<InsertEntryResult> {
    let encrypted_path = request.entry.encrypted_path();
    let overwrote_existing = encrypted_path.exists();

    if overwrote_existing && !request.overwrite {
        return Err(CoreError::Conflict(EntryConflict::already_exists(request.entry.path)));
    }

    if let Some(parent) = encrypted_path.parent() {
        fs::create_dir_all(parent)?;
    } else {
        return Err(CoreError::StoreError(format!(
            "entry path has no parent directory: {}",
            request.entry.path
        )));
    }

    let content = SecretString::new(request.content.into());
    let recipients = backend
        .validate_gpg_id(&request.entry.root, &encrypted_path)
        .map_err(|err| CoreError::PgpError(err.to_string()))?;
    backend
        .encrypt_content(&content, &encrypted_path, &recipients)
        .map_err(|err| CoreError::PgpError(err.to_string()))?;

    Ok(InsertEntryResult { entry_path: request.entry.path, overwrote_existing })
}

pub fn generate_entry(request: GenerateEntryRequest) -> GuiResult<GenerateEntryResult> {
    let backend = SystemGpgBackend::new(request.pgp_executable.clone());
    generate_entry_with_backend(request, &backend)
}

pub fn generate_entry_with_backend(
    request: GenerateEntryRequest,
    backend: &dyn PgpBackend,
) -> GuiResult<GenerateEntryResult> {
    if request.length == 0 {
        return Err(CoreError::ValidationError(
            "password length must be greater than 0".to_string(),
        ));
    }

    let generator = PasswordGenerator::new()
        .length(request.length)
        .numbers(true)
        .lowercase_letters(true)
        .uppercase_letters(true)
        .symbols(!request.no_symbols)
        .spaces(false)
        .exclude_similar_characters(true)
        .strict(true);
    let password =
        generator.generate_one().map_err(|err| CoreError::ValidationError(err.to_string()))?;

    let insert_result = insert_entry_with_backend(
        InsertEntryRequest {
            entry: request.entry,
            content: password.clone(),
            overwrite: request.overwrite,
            pgp_executable: request.pgp_executable,
        },
        backend,
    )?;

    Ok(GenerateEntryResult {
        entry_path: insert_result.entry_path,
        password,
        overwrote_existing: insert_result.overwrote_existing,
    })
}

pub fn edit_entry(request: EditEntryRequest) -> GuiResult<EntryMutationResult> {
    let backend = SystemGpgBackend::new(request.pgp_executable.clone());
    edit_entry_with_backend(request, &backend)
}

pub fn edit_entry_with_backend(
    request: EditEntryRequest,
    backend: &dyn PgpBackend,
) -> GuiResult<EntryMutationResult> {
    if !request.entry.encrypted_path().is_file() {
        return Err(CoreError::StoreError(format!("entry does not exist: {}", request.entry.path)));
    }

    let result = insert_entry_with_backend(
        InsertEntryRequest {
            entry: request.entry,
            content: request.content,
            overwrite: true,
            pgp_executable: request.pgp_executable,
        },
        backend,
    )?;

    Ok(EntryMutationResult { path: result.entry_path })
}

pub fn move_entry(request: MoveEntryRequest) -> GuiResult<EntryMutationResult> {
    if request.from.root != request.to.root {
        return Err(CoreError::ValidationError(
            "cannot move entries across different password store roots".to_string(),
        ));
    }

    let from_path = request.from.encrypted_path();
    let to_path = request.to.encrypted_path();

    if !from_path.is_file() {
        return Err(CoreError::StoreError(format!("entry does not exist: {}", request.from.path)));
    }

    if to_path.exists() && !request.overwrite {
        return Err(CoreError::Conflict(EntryConflict::already_exists(request.to.path)));
    }

    if to_path.exists() && !to_path.is_file() {
        return Err(CoreError::StoreError(format!(
            "destination is not a password file: {}",
            request.to.path
        )));
    }

    if let Some(parent) = to_path.parent() {
        fs::create_dir_all(parent)?;
    } else {
        return Err(CoreError::StoreError(format!(
            "entry has no parent path: {}",
            request.to.path
        )));
    }

    if to_path.exists() {
        fs::remove_file(&to_path)?;
    }
    fs::rename(&from_path, &to_path)?;

    Ok(EntryMutationResult { path: request.to.path })
}

pub fn read_entry(request: ReadEntryRequest) -> GuiResult<EntrySecret> {
    let backend = SystemGpgBackend::new(request.pgp_executable.clone());
    read_entry_with_backend(request, &backend)
}

pub fn read_entry_with_backend(
    request: ReadEntryRequest,
    backend: &dyn PgpBackend,
) -> GuiResult<EntrySecret> {
    let encrypted_path = request.entry.encrypted_path();
    if !encrypted_path.is_file() {
        return Err(CoreError::StoreError(format!("entry does not exist: {}", request.entry.path)));
    }

    let passphrase = request.passphrase.as_ref().map(|value| SecretString::from(value.clone()));
    let plain_text = backend
        .decrypt_file(&encrypted_path, passphrase.as_ref())
        .map_err(|err| CoreError::PgpError(err.to_string()))?;

    Ok(parse_entry_secret(plain_text.expose_secret()))
}

pub fn parse_entry_secret(plain_text: &str) -> EntrySecret {
    let normalized = plain_text.replace("\r\n", "\n");
    let mut lines = normalized.split('\n');
    let password = lines.next().unwrap_or_default().to_string();
    let mut fields = Vec::new();
    let mut raw_notes = Vec::new();

    for line in lines {
        match parse_field(line) {
            Some(field) => fields.push(field),
            None if !line.is_empty() => raw_notes.push(line.to_string()),
            None => {}
        }
    }

    EntrySecret { password, fields, raw_notes: raw_notes.join("\n") }
}

fn parse_field(line: &str) -> Option<ParsedEntryField> {
    let (key, value) = line.split_once(':')?;
    let key = key.trim().to_lowercase();
    let value = value.trim();
    if value.is_empty() {
        return None;
    }

    let label = match key.as_str() {
        "username" => "Username",
        "user" => "User",
        "login" => "Login",
        "email" => "Email",
        "url" => "URL",
        "website" => "Website",
        "service" => "Service",
        "android-package" => "Android package",
        "android_package" => "Android package",
        "totp" => "TOTP",
        "otp" => "OTP",
        "note" => "Note",
        _ => return None,
    };

    Some(ParsedEntryField { key, label: label.to_string(), value: value.to_string() })
}

fn normalize_entry_path(path: &str) -> GuiResult<String> {
    let path = Path::new(path);
    let mut parts = Vec::new();

    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let part = part.to_str().ok_or_else(|| {
                    CoreError::ValidationError("entry path must be valid UTF-8".to_string())
                })?;
                parts.push(part.to_string());
            }
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(CoreError::ValidationError(format!(
                    "entry path is outside password store: {}",
                    path.display()
                )));
            }
        }
    }

    if parts.is_empty() {
        return Err(CoreError::ValidationError("entry path cannot be empty".to_string()));
    }

    Ok(parts.join("/"))
}

fn contains_shell_syntax(arg: &str) -> bool {
    arg.contains("$(")
        || arg.contains(';')
        || arg.contains('|')
        || arg.contains('&')
        || arg.contains('>')
        || arg.contains('<')
        || arg.contains('`')
        || arg.contains('\n')
        || arg.contains('\r')
}

fn store_path_from_fs_path(root: &Path, path: &Path, trim_gpg: bool) -> GuiResult<String> {
    let relative = path.strip_prefix(root).map_err(|_| {
        CoreError::ValidationError(format!(
            "entry path is outside password store: {}",
            path.display()
        ))
    })?;

    let mut parts = relative
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => part.to_str().map(|part| part.to_string()),
            _ => None,
        })
        .collect::<Vec<_>>();

    if trim_gpg {
        if let Some(last) = parts.last_mut() {
            if let Some(without_ext) = last.strip_suffix(".gpg") {
                *last = without_ext.to_string();
            }
        }
    }

    Ok(parts.join("/"))
}

fn entry_name(path: &str) -> String {
    path.rsplit('/').next().unwrap_or(path).to_string()
}

fn parent_path(path: &str) -> Option<String> {
    path.rsplit_once('/').map(|(parent, _)| parent.to_string())
}

fn child_counts(paths: &BTreeSet<String>) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();

    for path in paths {
        if let Some(parent) = parent_path(path) {
            *counts.entry(parent).or_insert(0) += 1;
        }
    }

    counts
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::path::Path;

    use super::*;
    use crate::config::cli::PgpBackendKind;
    use crate::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
    use crate::pgp::backend::{
        KeyGenerationRequest, PgpBackend, PgpBackendConfig, PgpBackendResult,
    };
    use crate::pgp::import::InspectedPgpKey;
    use crate::pgp::rpgp_backend::RpgpBackend;

    #[test]
    fn entry_crypto_can_use_pure_rust_backend() {
        let temp = tempfile::tempdir().expect("tempdir");
        let root = temp.path().join("store");
        let keyring_home = temp.path().join("pgp");
        fs::create_dir_all(&root).expect("store");

        let backend = RpgpBackend::from_config(&PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            keyring_home: Some(keyring_home.display().to_string()),
            ..Default::default()
        })
        .expect("backend");
        let key = backend
            .generate_key(KeyGenerationRequest {
                name: "GUI Example".to_string(),
                email: "gui@example.com".to_string(),
                passphrase: None,
            })
            .expect("key");
        fs::write(root.join(".gpg-id"), format!("{}\n", key.fingerprint)).expect("gpg-id");

        let entry = EntryRef::new(root.clone(), "work/example").expect("entry");
        insert_entry_with_backend(
            InsertEntryRequest {
                entry: entry.clone(),
                content: "secret\nusername: gui".to_string(),
                overwrite: false,
                pgp_executable: String::new(),
            },
            &backend,
        )
        .expect("insert");

        let secret = read_entry_with_backend(
            ReadEntryRequest { entry, pgp_executable: String::new(), passphrase: None },
            &backend,
        )
        .expect("read");

        assert_eq!(secret.password, "secret");
        assert_eq!(secret.field_value("username"), Some("gui"));
    }

    #[test]
    fn read_entry_with_backend_passes_optional_passphrase_to_backend() {
        let temp = tempfile::tempdir().expect("tempdir");
        let root = temp.path().join("store");
        fs::create_dir_all(&root).expect("store");
        fs::write(root.join("github.gpg"), "encrypted").expect("entry");

        let backend = RecordingDecryptBackend::default();
        let secret = read_entry_with_backend(
            ReadEntryRequest {
                entry: EntryRef::new(root, "github").expect("entry ref"),
                pgp_executable: String::new(),
                passphrase: Some("session-passphrase".to_string()),
            },
            &backend,
        )
        .expect("read");

        assert_eq!(secret.password, "hunter2");
        assert_eq!(backend.seen_passphrase.borrow().as_deref(), Some("session-passphrase"));
    }

    #[derive(Default)]
    struct RecordingDecryptBackend {
        seen_passphrase: RefCell<Option<String>>,
    }

    impl PgpBackend for RecordingDecryptBackend {
        fn decrypt_file(
            &self,
            _encrypted_path: &Path,
            passphrase: Option<&SecretString>,
        ) -> PgpBackendResult<SecretString> {
            *self.seen_passphrase.borrow_mut() =
                passphrase.map(|value| value.expose_secret().to_string());
            Ok(SecretString::from("hunter2\nusername: alice".to_string()))
        }

        fn encrypt_content(
            &self,
            _plaintext: &SecretString,
            _output_path: &Path,
            _recipients: &[String],
        ) -> PgpBackendResult<()> {
            Ok(())
        }

        fn generate_key(
            &self,
            _request: KeyGenerationRequest,
        ) -> PgpBackendResult<KeyImportResult> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn import_key(&self, _key: &InspectedPgpKey) -> PgpBackendResult<KeyImportResult> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn export_public_key(&self, _fingerprint: &str) -> PgpBackendResult<KeyExportResult> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn export_private_key(
            &self,
            _fingerprint: &str,
            _passphrase: Option<&SecretString>,
        ) -> PgpBackendResult<KeyExportResult> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn delete_key(
            &self,
            _fingerprint: &str,
        ) -> PgpBackendResult<crate::pgp::backend::PgpKeyDeletionResult> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn list_keys(&self) -> PgpBackendResult<Vec<PgpKeySummary>> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn inspect_fingerprint(
            &self,
            _identity: &str,
        ) -> PgpBackendResult<crate::pgp::backend::PgpKeyDetails> {
            unreachable!("not used by read-entry passphrase test")
        }

        fn validate_gpg_id(
            &self,
            _store_root: &Path,
            _target_path: &Path,
        ) -> PgpBackendResult<Vec<String>> {
            unreachable!("not used by read-entry passphrase test")
        }
    }
}
