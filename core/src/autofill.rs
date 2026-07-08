use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::gui::{
    self, CoreError, EntryRef, EntrySecret, EntryType, ListEntriesRequest, ReadEntryRequest,
};
use crate::pgp::backend::PgpBackend;

pub const AUTOFILL_INDEX_VERSION: u32 = 1;

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillEntryMetadata {
    pub path: String,
    pub display_name: Option<String>,
    pub is_favorite: bool,
    pub recent_rank: Option<u32>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct RefreshAutofillIndexRequest {
    pub index_path: PathBuf,
    pub store_id: String,
    pub store_name: String,
    pub store_root: PathBuf,
    pub pgp_executable: String,
    pub passphrase: Option<String>,
    pub entries: Vec<AutofillEntryMetadata>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillQueryRequest {
    pub index_path: PathBuf,
    pub website: Option<String>,
    pub android_package: Option<String>,
    pub query: Option<String>,
    pub limit: usize,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillCredentialRequest {
    pub index_path: PathBuf,
    pub store_root: PathBuf,
    pub path: String,
    pub pgp_executable: String,
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillIndex {
    pub version: u32,
    pub store_id: String,
    pub store_name: String,
    pub store_root: String,
    pub generated_at_epoch_seconds: i64,
    pub entries: Vec<AutofillIndexEntry>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillIndexEntry {
    pub path: String,
    pub display_name: String,
    pub username: Option<String>,
    pub websites: Vec<String>,
    pub android_packages: Vec<String>,
    pub is_favorite: bool,
    pub recent_rank: Option<u32>,
    pub updated_at_epoch_seconds: i64,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillCandidate {
    pub path: String,
    pub display_name: String,
    pub username: Option<String>,
    pub match_kind: String,
    pub match_value: String,
    pub score: i32,
    pub is_favorite: bool,
    pub recent_rank: Option<u32>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AutofillCredential {
    pub path: String,
    pub username: Option<String>,
    pub password: String,
}

pub fn refresh_autofill_index_with_backend(
    request: RefreshAutofillIndexRequest,
    backend: &dyn PgpBackend,
) -> gui::GuiResult<AutofillIndex> {
    if !request.store_root.is_dir() {
        return Err(CoreError::StoreError(format!(
            "password store root does not exist: {}",
            request.store_root.display()
        )));
    }

    let metadata = request
        .entries
        .into_iter()
        .map(|entry| Ok((normalize_entry_path_for_metadata(&entry.path)?, entry)))
        .collect::<gui::GuiResult<BTreeMap<_, _>>>()?;

    let summaries = gui::list_entries(ListEntriesRequest {
        root: request.store_root.clone(),
        target: None,
        recursive: true,
    })?;
    let now = Utc::now().timestamp();
    let mut entries = Vec::new();

    for summary in summaries {
        if summary.entry_type != EntryType::Password {
            continue;
        }

        let entry = EntryRef::new(request.store_root.clone(), &summary.path)?;
        let secret = gui::read_entry_with_backend(
            ReadEntryRequest {
                entry,
                pgp_executable: request.pgp_executable.clone(),
                passphrase: request.passphrase.clone(),
            },
            backend,
        )?;
        let metadata = metadata.get(&summary.path);

        entries.push(AutofillIndexEntry {
            path: summary.path,
            display_name: metadata
                .and_then(|entry| entry.display_name.clone())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or(summary.name),
            username: username_for_secret(&secret),
            websites: website_identifiers_for_secret(&secret),
            android_packages: android_packages_for_secret(&secret),
            is_favorite: metadata.is_some_and(|entry| entry.is_favorite),
            recent_rank: metadata.and_then(|entry| entry.recent_rank),
            updated_at_epoch_seconds: now,
        });
    }

    entries.sort_by(|left, right| left.path.cmp(&right.path));
    let index = AutofillIndex {
        version: AUTOFILL_INDEX_VERSION,
        store_id: request.store_id,
        store_name: request.store_name,
        store_root: request.store_root.display().to_string(),
        generated_at_epoch_seconds: now,
        entries,
    };
    write_autofill_index(&request.index_path, &index)?;
    Ok(index)
}

pub fn query_autofill_candidates(
    request: AutofillQueryRequest,
) -> gui::GuiResult<Vec<AutofillCandidate>> {
    let index = read_autofill_index(&request.index_path)?;
    Ok(match_autofill_candidates(&index, &request))
}

pub fn resolve_autofill_credential_with_backend(
    request: AutofillCredentialRequest,
    backend: &dyn PgpBackend,
) -> gui::GuiResult<AutofillCredential> {
    let index = read_autofill_index(&request.index_path)?;
    let entry = index.entries.iter().find(|entry| entry.path == request.path).ok_or_else(|| {
        CoreError::ValidationError(format!("autofill entry is not indexed: {}", request.path))
    })?;

    let secret = gui::read_entry_with_backend(
        ReadEntryRequest {
            entry: EntryRef::new(request.store_root, &entry.path)?,
            pgp_executable: request.pgp_executable,
            passphrase: request.passphrase,
        },
        backend,
    )?;

    Ok(AutofillCredential {
        path: entry.path.clone(),
        username: username_for_secret(&secret).or_else(|| entry.username.clone()),
        password: secret.password,
    })
}

pub fn clear_autofill_index(index_path: &Path) -> gui::GuiResult<()> {
    if index_path.exists() {
        fs::remove_file(index_path)?;
    }
    Ok(())
}

pub fn read_autofill_index(index_path: &Path) -> gui::GuiResult<AutofillIndex> {
    let raw = fs::read_to_string(index_path).map_err(|error| {
        CoreError::StoreError(format!(
            "failed to read autofill index {}: {error}",
            index_path.display()
        ))
    })?;
    serde_json::from_str(&raw).map_err(|error| {
        CoreError::ValidationError(format!(
            "failed to parse autofill index {}: {error}",
            index_path.display()
        ))
    })
}

pub fn write_autofill_index(index_path: &Path, index: &AutofillIndex) -> gui::GuiResult<()> {
    if let Some(parent) = index_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let raw = serde_json::to_string_pretty(index)
        .map_err(|error| CoreError::ValidationError(error.to_string()))?;
    fs::write(index_path, raw)?;
    Ok(())
}

pub fn match_autofill_candidates(
    index: &AutofillIndex,
    request: &AutofillQueryRequest,
) -> Vec<AutofillCandidate> {
    let website = request.website.as_deref().and_then(normalize_website_identifier);
    let android_package = request.android_package.as_deref().and_then(normalize_android_package);
    let query = normalize_query(request.query.as_deref());
    let mut candidates = Vec::new();

    for entry in &index.entries {
        let mut best = None::<(&str, String, i32)>;
        if let Some(package) = &android_package {
            if entry.android_packages.iter().any(|value| value == package) {
                best = Some(("android_package", package.clone(), 3000));
            }
        }
        if best.is_none() {
            if let Some(website) = &website {
                if entry.websites.iter().any(|value| value == website) {
                    best = Some(("website", website.clone(), 2000));
                }
            }
        }
        if best.is_none() && !query.is_empty() && entry_matches_query(entry, &query) {
            best = Some(("fallback", query.clone(), 1000));
        }

        if let Some((match_kind, match_value, base_score)) = best {
            let score = base_score + ranking_bonus(entry);
            candidates.push(AutofillCandidate {
                path: entry.path.clone(),
                display_name: entry.display_name.clone(),
                username: entry.username.clone(),
                match_kind: match_kind.to_string(),
                match_value,
                score,
                is_favorite: entry.is_favorite,
                recent_rank: entry.recent_rank,
            });
        }
    }

    candidates.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| left.display_name.cmp(&right.display_name))
            .then_with(|| left.path.cmp(&right.path))
    });
    if request.limit > 0 {
        candidates.truncate(request.limit);
    }
    candidates
}

pub fn normalize_website_identifier(value: &str) -> Option<String> {
    let mut value = value.trim().to_ascii_lowercase();
    if value.is_empty() {
        return None;
    }
    if let Some(index) = value.find("://") {
        value = value[index + 3..].to_string();
    }
    if let Some(index) = value.find('@') {
        value = value[index + 1..].to_string();
    }
    value = value
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default()
        .trim()
        .trim_end_matches('.')
        .to_string();
    if value.starts_with('[') {
        return None;
    }
    if let Some((host, _port)) = value.rsplit_once(':') {
        if !host.contains(':') {
            value = host.to_string();
        }
    }
    while let Some(stripped) = value.strip_prefix("www.") {
        value = stripped.to_string();
    }
    if value.is_empty() || value.contains(char::is_whitespace) {
        return None;
    }
    Some(value)
}

pub fn normalize_android_package(value: &str) -> Option<String> {
    let value = value.trim().to_ascii_lowercase();
    if value.is_empty() || !value.contains('.') {
        return None;
    }
    if value
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '.')
    {
        Some(value)
    } else {
        None
    }
}

fn normalize_entry_path_for_metadata(path: &str) -> gui::GuiResult<String> {
    EntryRef::new(PathBuf::from("."), path).map(|entry| entry.path)
}

fn username_for_secret(secret: &EntrySecret) -> Option<String> {
    ["username", "login", "email", "user"]
        .iter()
        .find_map(|key| secret.field_value(key))
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn website_identifiers_for_secret(secret: &EntrySecret) -> Vec<String> {
    let mut websites = BTreeSet::new();
    for field in &secret.fields {
        let key = normalize_field_key(&field.key);
        if matches!(key.as_str(), "url" | "website" | "service") {
            for value in split_service_values(&field.value) {
                if let Some(host) = normalize_website_identifier(value) {
                    websites.insert(host);
                }
            }
        }
    }
    websites.into_iter().collect()
}

fn android_packages_for_secret(secret: &EntrySecret) -> Vec<String> {
    let mut packages = BTreeSet::new();
    for field in &secret.fields {
        let key = normalize_field_key(&field.key);
        if matches!(key.as_str(), "android-package" | "android_package") {
            for value in split_service_values(&field.value) {
                if let Some(package) = normalize_android_package(value) {
                    packages.insert(package);
                }
            }
        }
    }
    packages.into_iter().collect()
}

fn split_service_values(value: &str) -> impl Iterator<Item = &str> {
    value.split([',', ';', '\n']).map(str::trim).filter(|value| !value.is_empty())
}

fn normalize_field_key(key: &str) -> String {
    key.trim().to_ascii_lowercase()
}

fn normalize_query(query: Option<&str>) -> String {
    query.unwrap_or_default().trim().to_ascii_lowercase()
}

fn entry_matches_query(entry: &AutofillIndexEntry, query: &str) -> bool {
    entry.path.to_ascii_lowercase().contains(query)
        || entry.display_name.to_ascii_lowercase().contains(query)
        || entry.username.as_ref().is_some_and(|value| value.to_ascii_lowercase().contains(query))
}

fn ranking_bonus(entry: &AutofillIndexEntry) -> i32 {
    let favorite = if entry.is_favorite { 100 } else { 0 };
    let recent = entry
        .recent_rank
        .map(|rank| 50_i32.saturating_sub(i32::try_from(rank).unwrap_or(i32::MAX)))
        .unwrap_or(0)
        .max(0);
    favorite + recent
}
