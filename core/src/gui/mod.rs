use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::io;
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

pub type GuiResult<T> = Result<T, CoreError>;

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub enum CoreError {
    ConfigError(String),
    StoreError(String),
    PgpError(String),
    GitError(String),
    ClipboardError(String),
    ValidationError(String),
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
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct InsertEntryRequest {
    pub entry: EntryRef,
    pub content: String,
    pub overwrite: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct GenerateEntryRequest {
    pub entry: EntryRef,
    pub length: usize,
    pub no_symbols: bool,
    pub overwrite: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct EditEntryRequest {
    pub entry: EntryRef,
    pub content: String,
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

    let max_depth = if request.recursive { usize::MAX } else { 1 };
    let mut paths = BTreeSet::<String>::new();
    let mut entry_types = BTreeMap::<String, EntryType>::new();

    for entry in WalkDir::new(&walk_root).min_depth(1).max_depth(max_depth).follow_links(false) {
        let entry = entry?;
        let path = entry.path();
        if is_hidden_store_file(path) {
            continue;
        }

        if entry.file_type().is_dir() {
            let store_path = store_path_from_fs_path(&root, path, false)?;
            paths.insert(store_path.clone());
            entry_types.insert(store_path, EntryType::Directory);
        } else if entry.file_type().is_file()
            && path.extension().is_some_and(|extension| extension == "gpg")
        {
            let store_path = store_path_from_fs_path(&root, path, true)?;
            paths.insert(store_path.clone());
            entry_types.insert(store_path, EntryType::Password);
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

fn is_hidden_store_file(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name == ".gpg-id" || name == ".git")
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
