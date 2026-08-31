use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::gui::{
    self, CoreError, EntryRef, EntrySecret, EntryType, ListEntriesRequest, ReadEntryRequest,
};
use crate::pgp::backend::PgpBackend;

pub const AUTOFILL_INDEX_VERSION: u32 = 2;
pub const AUTOFILL_HISTORY_LIMIT: u32 = 20;

static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillEntryMetadata {
    pub path: String,
    pub is_favorite: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RebuildAutofillIndexRequest {
    pub index_path: PathBuf,
    pub store_id: String,
    pub store_name: String,
    pub store_root: PathBuf,
    pub entries: Vec<AutofillEntryMetadata>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpsertAutofillIndexEntryRequest {
    pub index_path: PathBuf,
    pub entry: AutofillEntryMetadata,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MoveAutofillIndexEntryRequest {
    pub index_path: PathBuf,
    pub old_path: String,
    pub new_path: String,
    pub recursive: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RemoveAutofillIndexEntryRequest {
    pub index_path: PathBuf,
    pub path: String,
    pub recursive: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchAutofillIndexFavoritesRequest {
    pub index_path: PathBuf,
    pub entries: Vec<AutofillEntryMetadata>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecordAutofillCompletionRequest {
    pub index_path: PathBuf,
    pub path: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReconcileAutofillIndexRequest {
    pub index_path: PathBuf,
    pub store_id: String,
    pub store_name: String,
    pub store_root: PathBuf,
    pub entries: Vec<AutofillEntryMetadata>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnrichAutofillIndexWebsitesRequest {
    pub index_path: PathBuf,
    pub store_root: PathBuf,
    pub pgp_executable: String,
    pub passphrase: Option<String>,
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ClearAutofillIndexWebsitesRequest {
    pub index_path: PathBuf,
    /// Empty clears enrichment for every indexed entry.
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillQueryRequest {
    pub index_path: PathBuf,
    pub website: Option<String>,
    pub app_name: Option<String>,
    pub query: Option<String>,
    pub limit: usize,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillCredentialRequest {
    pub index_path: PathBuf,
    pub store_root: PathBuf,
    pub path: String,
    pub pgp_executable: String,
    pub passphrase: Option<String>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillIndex {
    pub version: u32,
    pub store_id: String,
    pub store_name: String,
    pub store_root: String,
    pub generated_at_epoch_seconds: i64,
    pub entries: Vec<AutofillIndexEntry>,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillIndexEntry {
    pub path: String,
    pub display_name: String,
    pub service_name: Option<String>,
    pub username: String,
    pub path_website: Option<String>,
    pub enriched_websites: Vec<String>,
    pub is_favorite: bool,
    pub autofill_rank: Option<u32>,
    pub updated_at_epoch_seconds: i64,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillCandidate {
    pub path: String,
    pub display_name: String,
    pub username: String,
    pub match_kind: String,
    pub match_value: String,
    pub score: i32,
    pub is_favorite: bool,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillCredential {
    pub path: String,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
struct AutofillIndexVersion {
    version: u32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyAutofillIndexV1 {
    version: u32,
    store_id: String,
    store_name: String,
    store_root: String,
    generated_at_epoch_seconds: i64,
    entries: Vec<LegacyAutofillIndexEntryV1>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyAutofillIndexEntryV1 {
    path: String,
    display_name: String,
    service_name: Option<String>,
    username: String,
    path_website: Option<String>,
    enriched_websites: Vec<String>,
    is_favorite: bool,
    recent_rank: Option<u32>,
    updated_at_epoch_seconds: i64,
}

pub fn rebuild_autofill_index(
    request: RebuildAutofillIndexRequest,
) -> gui::GuiResult<AutofillIndex> {
    validate_store_root(&request.store_root)?;
    let metadata = metadata_by_path(request.entries)?;
    let previous = read_index_if_initialized(&request.index_path)?
        .filter(|index| index_matches_store(index, &request.store_id, &request.store_root))
        .map(|index| {
            index
                .entries
                .into_iter()
                .map(|entry| (entry.path.clone(), entry))
                .collect::<BTreeMap<_, _>>()
        })
        .unwrap_or_default();
    let now = Utc::now().timestamp();
    let mut entries = list_password_paths(&request.store_root)?
        .into_iter()
        .map(|path| {
            let ranking = metadata.get(&path);
            derive_index_entry(
                &path,
                ranking.is_some_and(|value| value.is_favorite),
                previous.get(&path).and_then(|value| value.autofill_rank),
                Vec::new(),
                now,
            )
        })
        .collect::<gui::GuiResult<Vec<_>>>()?;
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

pub fn upsert_autofill_index_entry(
    request: UpsertAutofillIndexEntryRequest,
) -> gui::GuiResult<Option<AutofillIndex>> {
    let Some(mut index) = read_index_if_initialized(&request.index_path)? else {
        return Ok(None);
    };
    let path = normalize_entry_path(&request.entry.path)?;
    let now = Utc::now().timestamp();
    let enriched_websites = index
        .entries
        .iter()
        .find(|entry| entry.path == path)
        .map(|entry| entry.enriched_websites.clone())
        .unwrap_or_default();
    let autofill_rank =
        index.entries.iter().find(|entry| entry.path == path).and_then(|entry| entry.autofill_rank);
    let replacement = derive_index_entry(
        &path,
        request.entry.is_favorite,
        autofill_rank,
        enriched_websites,
        now,
    )?;
    index.entries.retain(|entry| entry.path != path);
    index.entries.push(replacement);
    finish_index_mutation(&request.index_path, index).map(Some)
}

pub fn move_autofill_index_entry(
    request: MoveAutofillIndexEntryRequest,
) -> gui::GuiResult<Option<AutofillIndex>> {
    let Some(mut index) = read_index_if_initialized(&request.index_path)? else {
        return Ok(None);
    };
    let old_path = normalize_entry_path(&request.old_path)?;
    let new_path = normalize_entry_path(&request.new_path)?;
    let now = Utc::now().timestamp();
    let mut replacements = Vec::new();
    let mut retained = Vec::with_capacity(index.entries.len());

    for entry in index.entries {
        let Some(suffix) = matching_path_suffix(&entry.path, &old_path, request.recursive) else {
            retained.push(entry);
            continue;
        };
        let moved_path =
            if suffix.is_empty() { new_path.clone() } else { format!("{new_path}/{suffix}") };
        replacements.push(derive_index_entry(
            &moved_path,
            entry.is_favorite,
            None,
            entry.enriched_websites,
            now,
        )?);
    }

    if replacements.is_empty() && !request.recursive {
        replacements.push(derive_index_entry(&new_path, false, None, Vec::new(), now)?);
    }
    retained.extend(replacements);
    index.entries = retained;
    finish_index_mutation(&request.index_path, index).map(Some)
}

pub fn remove_autofill_index_entry(
    request: RemoveAutofillIndexEntryRequest,
) -> gui::GuiResult<Option<AutofillIndex>> {
    let Some(mut index) = read_index_if_initialized(&request.index_path)? else {
        return Ok(None);
    };
    let path = normalize_entry_path(&request.path)?;
    index
        .entries
        .retain(|entry| matching_path_suffix(&entry.path, &path, request.recursive).is_none());
    finish_index_mutation(&request.index_path, index).map(Some)
}

pub fn patch_autofill_index_favorites(
    request: PatchAutofillIndexFavoritesRequest,
) -> gui::GuiResult<Option<AutofillIndex>> {
    let Some(mut index) = read_index_if_initialized(&request.index_path)? else {
        return Ok(None);
    };
    let metadata = metadata_by_path(request.entries)?;
    let now = Utc::now().timestamp();
    for entry in &mut index.entries {
        if let Some(ranking) = metadata.get(&entry.path) {
            entry.is_favorite = ranking.is_favorite;
            entry.updated_at_epoch_seconds = now;
        }
    }
    finish_index_mutation(&request.index_path, index).map(Some)
}

pub fn reconcile_autofill_index(
    request: ReconcileAutofillIndexRequest,
) -> gui::GuiResult<Option<AutofillIndex>> {
    let Some(mut index) = read_index_if_initialized(&request.index_path)? else {
        return Ok(None);
    };
    validate_store_root(&request.store_root)?;
    let requested_root = fs::canonicalize(&request.store_root)?;
    let indexed_root = fs::canonicalize(Path::new(&index.store_root)).ok();
    if index.store_id != request.store_id || indexed_root.as_ref() != Some(&requested_root) {
        clear_autofill_index(&request.index_path)?;
        return Err(CoreError::ValidationError(
            "autofill index belongs to a different password store; rebuild required".to_string(),
        ));
    }
    let metadata = metadata_by_path(request.entries)?;
    let existing = index
        .entries
        .into_iter()
        .map(|entry| (entry.path.clone(), entry))
        .collect::<BTreeMap<_, _>>();
    let now = Utc::now().timestamp();
    let mut entries = Vec::new();

    for path in list_password_paths(&request.store_root)? {
        let ranking = metadata.get(&path);
        let previous = existing.get(&path);
        let enriched_websites =
            previous.map(|entry| entry.enriched_websites.clone()).unwrap_or_default();
        let is_favorite = ranking.map_or_else(
            || previous.is_some_and(|entry| entry.is_favorite),
            |entry| entry.is_favorite,
        );
        let autofill_rank = previous.and_then(|entry| entry.autofill_rank);
        let mut entry =
            derive_index_entry(&path, is_favorite, autofill_rank, enriched_websites, now)?;
        if previous.is_some_and(|previous| same_logical_entry(previous, &entry)) {
            entry.updated_at_epoch_seconds =
                previous.expect("checked above").updated_at_epoch_seconds;
        }
        entries.push(entry);
    }
    index.store_id = request.store_id;
    index.store_name = request.store_name;
    index.store_root = request.store_root.display().to_string();
    index.entries = entries;
    finish_index_mutation(&request.index_path, index).map(Some)
}

pub fn record_autofill_completion(
    request: RecordAutofillCompletionRequest,
) -> gui::GuiResult<AutofillIndex> {
    let mut index = read_autofill_index(&request.index_path)?;
    let path = normalize_entry_path(&request.path)?;
    normalize_autofill_ranks(&mut index.entries);
    let selected_rank = index
        .entries
        .iter()
        .find(|entry| entry.path == path)
        .ok_or_else(|| {
            CoreError::ValidationError(format!("autofill entry is not indexed: {path}"))
        })?
        .autofill_rank;
    let now = Utc::now().timestamp();

    for entry in &mut index.entries {
        if entry.path == path {
            entry.autofill_rank = Some(0);
            entry.updated_at_epoch_seconds = now;
            continue;
        }
        let should_shift = match (selected_rank, entry.autofill_rank) {
            (None, Some(_)) => true,
            (Some(selected), Some(rank)) => rank < selected,
            _ => false,
        };
        if should_shift {
            entry.autofill_rank = entry
                .autofill_rank
                .and_then(|rank| (rank + 1 < AUTOFILL_HISTORY_LIMIT).then_some(rank + 1));
            entry.updated_at_epoch_seconds = now;
        }
    }
    finish_index_mutation(&request.index_path, index)
}

pub fn enrich_autofill_index_websites_with_backend(
    request: EnrichAutofillIndexWebsitesRequest,
    backend: &dyn PgpBackend,
) -> gui::GuiResult<AutofillIndex> {
    if request.paths.is_empty() {
        return Err(CoreError::ValidationError(
            "autofill website enrichment requires at least one path".to_string(),
        ));
    }
    validate_store_root(&request.store_root)?;
    let mut index = read_autofill_index(&request.index_path)?;
    let paths = request
        .paths
        .iter()
        .map(|path| normalize_entry_path(path))
        .collect::<gui::GuiResult<BTreeSet<_>>>()?;
    for path in &paths {
        if !index.entries.iter().any(|entry| &entry.path == path) {
            return Err(CoreError::ValidationError(format!(
                "autofill entry is not indexed: {path}"
            )));
        }
    }

    let mut aliases = BTreeMap::new();
    for path in &paths {
        let secret = gui::read_entry_with_backend(
            ReadEntryRequest {
                entry: EntryRef::new(request.store_root.clone(), path)?,
                pgp_executable: request.pgp_executable.clone(),
                passphrase: request.passphrase.clone(),
            },
            backend,
        )?;
        aliases.insert(path.clone(), website_identifiers_for_secret(&secret));
    }

    let now = Utc::now().timestamp();
    for entry in &mut index.entries {
        if let Some(values) = aliases.remove(&entry.path) {
            entry.enriched_websites = values;
            entry.updated_at_epoch_seconds = now;
        }
    }
    finish_index_mutation(&request.index_path, index)
}

pub fn clear_autofill_index_websites(
    request: ClearAutofillIndexWebsitesRequest,
) -> gui::GuiResult<Option<AutofillIndex>> {
    let Some(mut index) = read_index_if_initialized(&request.index_path)? else {
        return Ok(None);
    };
    let paths = request
        .paths
        .iter()
        .map(|path| normalize_entry_path(path))
        .collect::<gui::GuiResult<BTreeSet<_>>>()?;
    let clear_all = paths.is_empty();
    let now = Utc::now().timestamp();
    for entry in &mut index.entries {
        if clear_all || paths.contains(&entry.path) {
            entry.enriched_websites.clear();
            entry.updated_at_epoch_seconds = now;
        }
    }
    finish_index_mutation(&request.index_path, index).map(Some)
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
    let requested_path = normalize_entry_path(&request.path)?;
    let entry =
        index.entries.iter().find(|entry| entry.path == requested_path).ok_or_else(|| {
            CoreError::ValidationError(format!("autofill entry is not indexed: {requested_path}"))
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
        username: entry.username.clone(),
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
    let version: AutofillIndexVersion = serde_json::from_str(&raw).map_err(|error| {
        CoreError::ValidationError(format!(
            "failed to parse autofill index {}: {error}",
            index_path.display()
        ))
    })?;
    match version.version {
        AUTOFILL_INDEX_VERSION => serde_json::from_str(&raw).map_err(|error| {
            CoreError::ValidationError(format!(
                "failed to parse autofill index {}: {error}",
                index_path.display()
            ))
        }),
        1 => {
            let legacy: LegacyAutofillIndexV1 = serde_json::from_str(&raw).map_err(|error| {
                CoreError::ValidationError(format!(
                    "failed to parse autofill index {}: {error}",
                    index_path.display()
                ))
            })?;
            debug_assert_eq!(legacy.version, 1);
            let index = AutofillIndex {
                version: AUTOFILL_INDEX_VERSION,
                store_id: legacy.store_id,
                store_name: legacy.store_name,
                store_root: legacy.store_root,
                generated_at_epoch_seconds: legacy.generated_at_epoch_seconds,
                entries: legacy
                    .entries
                    .into_iter()
                    .map(|entry| {
                        let _legacy_recent_rank = entry.recent_rank;
                        AutofillIndexEntry {
                            path: entry.path,
                            display_name: entry.display_name,
                            service_name: entry.service_name,
                            username: entry.username,
                            path_website: entry.path_website,
                            enriched_websites: entry.enriched_websites,
                            is_favorite: entry.is_favorite,
                            autofill_rank: None,
                            updated_at_epoch_seconds: entry.updated_at_epoch_seconds,
                        }
                    })
                    .collect(),
            };
            write_autofill_index(index_path, &index)?;
            Ok(index)
        }
        unsupported => Err(CoreError::ValidationError(format!(
            "unsupported autofill index version: {unsupported}"
        ))),
    }
}

pub fn write_autofill_index(index_path: &Path, index: &AutofillIndex) -> gui::GuiResult<()> {
    if index.version != AUTOFILL_INDEX_VERSION {
        return Err(CoreError::ValidationError(format!(
            "cannot write unsupported autofill index version: {}",
            index.version
        )));
    }
    if let Some(parent) = index_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let raw = serde_json::to_vec_pretty(index)
        .map_err(|error| CoreError::ValidationError(error.to_string()))?;
    let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let temp_path =
        index_path.with_extension(format!("autofill-tmp-{}-{sequence}", std::process::id()));
    let result = (|| -> gui::GuiResult<()> {
        let mut file = OpenOptions::new().create_new(true).write(true).open(&temp_path)?;
        file.write_all(&raw)?;
        file.sync_all()?;
        fs::rename(&temp_path, index_path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}

pub fn match_autofill_candidates(
    index: &AutofillIndex,
    request: &AutofillQueryRequest,
) -> Vec<AutofillCandidate> {
    let website = request.website.as_deref().and_then(normalize_website_identifier);
    let app_name = request.app_name.as_deref().and_then(normalize_service_name);
    let query = normalize_query(request.query.as_deref());
    let mut candidates = Vec::new();

    for entry in &index.entries {
        let mut best = None::<(&str, String, i32)>;
        if let Some(website) = &website {
            if entry.path_website.as_ref() == Some(website) {
                best = Some(("path_website", website.clone(), 4000));
            }
        }
        if best.is_none() {
            if let (Some(app_name), Some(service_name)) = (&app_name, &entry.service_name) {
                if normalize_service_name(service_name).as_ref() == Some(app_name) {
                    best = Some(("app_name", app_name.clone(), 3500));
                }
            }
        }
        if best.is_none() {
            if let Some(website) = &website {
                if entry.enriched_websites.iter().any(|value| value == website) {
                    best = Some(("enriched_website", website.clone(), 3000));
                }
            }
        }
        if best.is_none() && !query.is_empty() && entry_matches_query(entry, &query) {
            best = Some(("fallback", query.clone(), 1000));
        }

        if let Some((match_kind, match_value, base_score)) = best {
            candidates.push(AutofillCandidate {
                path: entry.path.clone(),
                display_name: entry.display_name.clone(),
                username: entry.username.clone(),
                match_kind: match_kind.to_string(),
                match_value,
                score: base_score + ranking_bonus(entry),
                is_favorite: entry.is_favorite,
            });
        }
    }

    candidates.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| left.display_name.cmp(&right.display_name))
            .then_with(|| left.username.cmp(&right.username))
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

fn validate_store_root(store_root: &Path) -> gui::GuiResult<()> {
    if store_root.is_dir() {
        Ok(())
    } else {
        Err(CoreError::StoreError(format!(
            "password store root does not exist: {}",
            store_root.display()
        )))
    }
}

fn metadata_by_path(
    entries: Vec<AutofillEntryMetadata>,
) -> gui::GuiResult<BTreeMap<String, AutofillEntryMetadata>> {
    entries.into_iter().map(|entry| Ok((normalize_entry_path(&entry.path)?, entry))).collect()
}

fn list_password_paths(store_root: &Path) -> gui::GuiResult<Vec<String>> {
    Ok(gui::list_entries(ListEntriesRequest {
        root: store_root.to_path_buf(),
        target: None,
        recursive: true,
    })?
    .into_iter()
    .filter(|summary| summary.entry_type == EntryType::Password)
    .map(|summary| summary.path)
    .collect())
}

fn derive_index_entry(
    path: &str,
    is_favorite: bool,
    autofill_rank: Option<u32>,
    enriched_websites: Vec<String>,
    updated_at_epoch_seconds: i64,
) -> gui::GuiResult<AutofillIndexEntry> {
    let path = normalize_entry_path(path)?;
    let mut components = path.split('/');
    let username = components.next_back().unwrap_or_default().to_string();
    let service_name = components.next_back().map(ToOwned::to_owned);
    let path_website = service_name.as_deref().and_then(normalize_path_website);
    let display_name = service_name.clone().unwrap_or_else(|| username.clone());
    let enriched_websites = enriched_websites
        .into_iter()
        .filter_map(|value| normalize_website_identifier(&value))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    Ok(AutofillIndexEntry {
        path,
        display_name,
        service_name,
        username,
        path_website,
        enriched_websites,
        is_favorite,
        autofill_rank,
        updated_at_epoch_seconds,
    })
}

fn normalize_path_website(value: &str) -> Option<String> {
    normalize_website_identifier(value).filter(|value| value.contains('.'))
}

fn normalize_service_name(value: &str) -> Option<String> {
    let value = value.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase();
    (!value.is_empty()).then_some(value)
}

fn normalize_entry_path(path: &str) -> gui::GuiResult<String> {
    EntryRef::new(PathBuf::from("."), path).map(|entry| entry.path)
}

fn matching_path_suffix(entry_path: &str, path: &str, recursive: bool) -> Option<String> {
    if entry_path == path {
        return Some(String::new());
    }
    if recursive {
        return entry_path.strip_prefix(&format!("{path}/")).map(ToOwned::to_owned);
    }
    None
}

fn read_index_if_initialized(index_path: &Path) -> gui::GuiResult<Option<AutofillIndex>> {
    if index_path.is_file() {
        read_autofill_index(index_path).map(Some)
    } else {
        Ok(None)
    }
}

fn finish_index_mutation(
    index_path: &Path,
    mut index: AutofillIndex,
) -> gui::GuiResult<AutofillIndex> {
    normalize_autofill_ranks(&mut index.entries);
    index.entries.sort_by(|left, right| left.path.cmp(&right.path));
    index.generated_at_epoch_seconds = Utc::now().timestamp();
    write_autofill_index(index_path, &index)?;
    Ok(index)
}

fn normalize_autofill_ranks(entries: &mut [AutofillIndexEntry]) {
    let mut ranked = entries
        .iter()
        .enumerate()
        .filter_map(|(index, entry)| entry.autofill_rank.map(|rank| (index, rank)))
        .collect::<Vec<_>>();
    ranked.sort_by(|(left_index, left_rank), (right_index, right_rank)| {
        left_rank
            .cmp(right_rank)
            .then_with(|| entries[*left_index].path.cmp(&entries[*right_index].path))
    });
    for entry in entries.iter_mut() {
        entry.autofill_rank = None;
    }
    for (rank, (index, _)) in ranked.into_iter().take(AUTOFILL_HISTORY_LIMIT as usize).enumerate() {
        entries[index].autofill_rank = Some(rank as u32);
    }
}

fn index_matches_store(index: &AutofillIndex, store_id: &str, store_root: &Path) -> bool {
    if index.store_id != store_id {
        return false;
    }
    match (fs::canonicalize(&index.store_root), fs::canonicalize(store_root)) {
        (Ok(indexed), Ok(requested)) => indexed == requested,
        _ => index.store_root == store_root.display().to_string(),
    }
}

fn same_logical_entry(left: &AutofillIndexEntry, right: &AutofillIndexEntry) -> bool {
    left.path == right.path
        && left.display_name == right.display_name
        && left.service_name == right.service_name
        && left.username == right.username
        && left.path_website == right.path_website
        && left.enriched_websites == right.enriched_websites
        && left.is_favorite == right.is_favorite
        && left.autofill_rank == right.autofill_rank
}

fn website_identifiers_for_secret(secret: &EntrySecret) -> Vec<String> {
    let mut websites = BTreeSet::new();
    for field in &secret.fields {
        let key = field.key.trim().to_ascii_lowercase();
        if matches!(key.as_str(), "url" | "website" | "service") {
            for value in field.value.split([',', ';', '\n']).map(str::trim) {
                if let Some(host) = normalize_website_identifier(value) {
                    websites.insert(host);
                }
            }
        }
    }
    websites.into_iter().collect()
}

fn normalize_query(query: Option<&str>) -> String {
    query.unwrap_or_default().trim().to_lowercase()
}

fn entry_matches_query(entry: &AutofillIndexEntry, query: &str) -> bool {
    entry.path.to_lowercase().contains(query)
        || entry.display_name.to_lowercase().contains(query)
        || entry.username.to_lowercase().contains(query)
        || entry.service_name.as_ref().is_some_and(|value| value.to_lowercase().contains(query))
}

fn ranking_bonus(entry: &AutofillIndexEntry) -> i32 {
    let favorite = if entry.is_favorite { 100 } else { 0 };
    let autofill_history = entry
        .autofill_rank
        .map(|rank| 50_i32.saturating_sub(i32::try_from(rank).unwrap_or(i32::MAX)))
        .unwrap_or(0)
        .max(0);
    favorite + autofill_history
}
