//! Git sync, recovery, history, branch, and identity operations.
//!
//! `lg_*` functions use libgit2 and back Android and iOS. `sys_*` functions run the system `git`
//! executable and back desktop. Both return the same DTOs so Flutter sees one contract.
// The libgit2 half only runs on mobile, but desktop tests exercise it too.
#![cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]

use std::cell::{Cell, RefCell};
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::{SystemTime, UNIX_EPOCH};

use git2::build::CheckoutBuilder;
use git2::{
    BranchType, CertificateCheckStatus, ConfigLevel, Cred, CredentialType, ErrorClass, ErrorCode,
    FetchOptions, Index, IndexAddOption, Oid, PushOptions, RebaseOptions, Reference,
    RemoteCallbacks, Repository, RepositoryState, ResetType, Signature, Sort,
};
use pars_core::gui::CoreError;
use pars_core::key_management::ssh_private_key_text_is_encrypted;

use crate::api::{
    git_failure, trace_git, remember_remote_host_key, ssh_identity_credential, store_failure,
    BridgeFailure, BridgeFailureCategory, GitIdentityDto, GitIntegrationStrategyDto,
    GitLogEntryDto, GitRequest, GitResetResultDto, GitStatusOperationDto, GitStatusSummaryDto,
    GitSyncConflictDto, GitSyncResultDto,
};
use crate::git_status::summarize_repository;

/// Remote name, current branch, and branch names on that remote.
pub(crate) type RemoteBranches = (Option<String>, Option<String>, Vec<String>);

pub(crate) const BACKUP_BRANCH_PREFIX: &str = "pars/backup-";

/// Transport inputs for one Git network operation. Secrets are borrowed from the request and
/// never logged or stored.
#[derive(Clone, Copy, Default)]
pub(crate) struct GitTransport<'a> {
    pub ssh_private_key_path: Option<&'a Path>,
    pub ssh_dir: Option<&'a Path>,
    /// Desktop only; mobile reads the remembered hosts from `ssh_dir`.
    #[cfg_attr(any(target_os = "android", target_os = "ios"), allow(dead_code))]
    pub known_hosts: Option<&'a str>,
    pub https_username: Option<&'a str>,
    pub https_token: Option<&'a str>,
    pub ssh_passphrase: Option<&'a str>,
}

impl<'a> GitTransport<'a> {
    pub(crate) fn from_request(request: &'a GitRequest) -> Self {
        Self {
            ssh_private_key_path: request.ssh_private_key_path.as_deref().map(Path::new),
            ssh_dir: request.ssh_dir.as_deref().map(Path::new),
            known_hosts: request.known_hosts.as_deref(),
            https_username: request.https_username.as_deref(),
            https_token: request.https_token.as_deref(),
            ssh_passphrase: request.ssh_passphrase.as_deref(),
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum AuthIssue {
    #[default]
    None,
    HttpsRequired,
    SshPassphraseRequired,
}

/// Records why credential callbacks gave up, so a transport error can be reported as a typed
/// failure instead of libgit2's generic text.
#[derive(Clone, Default)]
pub(crate) struct AuthProbe {
    issue: Rc<Cell<AuthIssue>>,
    encrypted_key_offered: Rc<Cell<bool>>,
}

impl AuthProbe {
    pub(crate) fn failure(&self, error: git2::Error) -> BridgeFailure {
        let issue = match self.issue.get() {
            AuthIssue::None
                if self.encrypted_key_offered.get() && error.class() == ErrorClass::Ssh =>
            {
                AuthIssue::SshPassphraseRequired
            }
            issue => issue,
        };
        match issue {
            AuthIssue::HttpsRequired => {
                trace_git("https authentication required");
                typed_failure(
                    BridgeFailureCategory::AuthenticationRequired,
                    "The remote needs a username and token.",
                )
            }
            AuthIssue::SshPassphraseRequired => {
                trace_git("ssh key passphrase required");
                typed_failure(
                    BridgeFailureCategory::SshPassphraseRequired,
                    "The SSH key needs its passphrase.",
                )
            }
            AuthIssue::None => git_failure(error),
        }
    }
}

fn typed_failure(category: BridgeFailureCategory, message: &str) -> BridgeFailure {
    BridgeFailure {
        category,
        message: message.to_string(),
        conflict_kind: None,
        path: None,
        pgp_import_kind: None,
    }
}

pub(crate) fn identity_required() -> BridgeFailure {
    typed_failure(
        BridgeFailureCategory::IdentityRequired,
        "Set a Git name and email before committing.",
    )
}

fn validation(message: &str) -> BridgeFailure {
    BridgeFailure::from(CoreError::ValidationError(message.to_string()))
}

fn git_error(message: &str) -> BridgeFailure {
    BridgeFailure::from(CoreError::GitError(message.to_string()))
}

fn managed_key_path(private_key_path: &Path, ssh_dir: Option<&Path>) -> Result<PathBuf, BridgeFailure> {
    let ssh_dir = ssh_dir.ok_or_else(|| validation("SSH key directory is required"))?;
    let root = ssh_dir.canonicalize().map_err(store_failure)?;
    let metadata = fs::symlink_metadata(private_key_path).map_err(store_failure)?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(validation("SSH private key must be a regular managed file"));
    }
    let key_path = private_key_path.canonicalize().map_err(store_failure)?;
    if !key_path.starts_with(&root) || key_path == root {
        return Err(validation("SSH private key is outside managed storage"));
    }
    Ok(key_path)
}

/// Builds credential and host-key callbacks. Each credential kind is offered at most once per
/// operation because libgit2 keeps calling the callback after a rejection.
pub(crate) fn transport_callbacks(
    transport: &GitTransport<'_>,
    remote_url: &str,
) -> Result<(RemoteCallbacks<'static>, AuthProbe), BridgeFailure> {
    let probe = AuthProbe::default();
    let mut callbacks = RemoteCallbacks::new();

    let key_path = transport
        .ssh_private_key_path
        .map(|path| managed_key_path(path, transport.ssh_dir))
        .transpose()?;
    let key_encrypted = key_path.as_deref().is_some_and(|path| {
        fs::read_to_string(path).is_ok_and(|text| ssh_private_key_text_is_encrypted(&text))
    });
    let passphrase = transport.ssh_passphrase.filter(|value| !value.is_empty()).map(str::to_string);
    let https_username = transport.https_username.map(str::to_string);
    let https_token = transport.https_token.map(str::to_string);
    let callback_probe = probe.clone();
    let mut ssh_offered = false;
    let mut https_offered = false;
    callbacks.credentials(move |_url, username, allowed| {
        if allowed.intersects(CredentialType::SSH_KEY | CredentialType::SSH_MEMORY) {
            let Some(key_path) = key_path.as_deref() else {
                return Err(git2::Error::from_str("an SSH key is required for this remote"));
            };
            if ssh_offered {
                if key_encrypted {
                    callback_probe.issue.set(AuthIssue::SshPassphraseRequired);
                }
                return Err(git2::Error::from_str("the SSH key was rejected"));
            }
            ssh_offered = true;
            if key_encrypted && passphrase.is_none() {
                callback_probe.issue.set(AuthIssue::SshPassphraseRequired);
                return Err(git2::Error::from_str("the SSH key needs its passphrase"));
            }
            callback_probe.encrypted_key_offered.set(key_encrypted);
            return ssh_identity_credential(
                username.unwrap_or("git"),
                key_path,
                passphrase.as_deref(),
            );
        }
        if allowed.contains(CredentialType::USER_PASS_PLAINTEXT) {
            if https_offered {
                callback_probe.issue.set(AuthIssue::HttpsRequired);
                return Err(git2::Error::from_str("the HTTPS credentials were rejected"));
            }
            https_offered = true;
            let user = https_username.as_deref().or(username).filter(|value| !value.is_empty());
            return match (user, https_token.as_deref().filter(|value| !value.is_empty())) {
                (Some(user), Some(token)) => Cred::userpass_plaintext(user, token),
                _ => {
                    callback_probe.issue.set(AuthIssue::HttpsRequired);
                    Err(git2::Error::from_str("HTTPS authentication is required"))
                }
            };
        }
        if allowed.contains(CredentialType::USERNAME) {
            return Cred::username(username.unwrap_or("git"));
        }
        Err(git2::Error::from_str("the remote asked for unsupported credentials"))
    });

    if let Some((host_name, port)) = crate::known_hosts::ssh_remote_endpoint(remote_url) {
        let ssh_dir =
            transport.ssh_dir.ok_or_else(|| validation("SSH key directory is required"))?;
        let ssh_dir = ssh_dir.to_path_buf();
        let stored = fs::read_to_string(ssh_dir.join("known_hosts")).unwrap_or_default();
        callbacks.certificate_check(move |cert, connected_host| {
            let Some(hostkey) = cert.as_hostkey() else {
                return Ok(CertificateCheckStatus::CertificatePassthrough);
            };
            let raw = hostkey
                .hostkey()
                .ok_or_else(|| git2::Error::from_str("remote SSH host key is missing"))?;
            let key_type = hostkey.hostkey_type().map(|kind| kind.name()).unwrap_or("unknown");
            let hostname =
                if connected_host.is_empty() { host_name.as_str() } else { connected_host };
            match crate::known_hosts::remote_host_key_trust(&stored, hostname, port, key_type, raw)
            {
                crate::known_hosts::RemoteHostKeyTrust::Trusted => {
                    trace_git(&format!("ssh host {hostname}:{port} trusted ({key_type})"));
                    Ok(CertificateCheckStatus::CertificateOk)
                }
                crate::known_hosts::RemoteHostKeyTrust::Changed => {
                    trace_git(&format!("ssh host {hostname}:{port} changed ({key_type})"));
                    Err(git2::Error::from_str(
                        "remote SSH host key does not match the remembered host key",
                    ))
                }
                crate::known_hosts::RemoteHostKeyTrust::Unknown => {
                    trace_git(&format!(
                        "ssh host {hostname}:{port} unknown; remembering ({key_type})"
                    ));
                    let line =
                        crate::known_hosts::format_known_host_line(hostname, port, key_type, raw);
                    remember_remote_host_key(&ssh_dir, &line).map_err(|_| {
                        git2::Error::from_str("could not remember the remote SSH host key")
                    })?;
                    Ok(CertificateCheckStatus::CertificateOk)
                }
            }
        });
    }
    Ok((callbacks, probe))
}

/// `pars/backup-<UTC yyyyMMdd-HHmmss>`, the name Flutter shows in the recovery dialog.
fn backup_branch_name(unix_seconds: i64) -> String {
    let days = unix_seconds.div_euclid(86_400);
    let seconds = unix_seconds.rem_euclid(86_400);
    // Civil-from-days (Howard Hinnant), valid for the proleptic Gregorian calendar.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{BACKUP_BRANCH_PREFIX}{year:04}{month:02}{day:02}-{:02}{:02}{:02}",
        seconds / 3_600,
        (seconds % 3_600) / 60,
        seconds % 60
    )
}

fn now_seconds() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|value| value.as_secs() as i64).unwrap_or(0)
}

fn valid_branch_name(branch: &str) -> Result<(), BridgeFailure> {
    if branch.is_empty()
        || branch.starts_with('-')
        || branch.contains(char::is_whitespace)
        || !Reference::is_valid_name(&format!("refs/heads/{branch}"))
    {
        return Err(validation("branch name is not valid"));
    }
    Ok(())
}

fn validated_identity(name: &str, email: &str) -> Result<(String, String), BridgeFailure> {
    let name = name.trim();
    let email = email.trim();
    if name.is_empty() || email.is_empty() {
        return Err(validation("Git name and email are required"));
    }
    if name.contains(['\n', '\r', '<', '>']) || email.contains(['\n', '\r', '<', '>', ' ']) {
        return Err(validation("Git name or email contains characters Git does not accept"));
    }
    Ok((name.to_string(), email.to_string()))
}

// ---------------------------------------------------------------------------------------------
// libgit2
// ---------------------------------------------------------------------------------------------

pub(crate) fn lg_signature(repo: &Repository) -> Result<Signature<'static>, BridgeFailure> {
    let signature = repo.signature().map_err(|_| identity_required())?;
    let has_name = signature.name().is_some_and(|value| !value.trim().is_empty());
    let has_email = signature.email().is_some_and(|value| !value.trim().is_empty());
    if !has_name || !has_email {
        return Err(identity_required());
    }
    Ok(signature.to_owned())
}

/// Stages every change and commits it. Returns `None` when the tree matches HEAD.
pub(crate) fn lg_commit_all(repo: &Repository, message: &str) -> Result<Option<Oid>, BridgeFailure> {
    let mut index = repo.index().map_err(git_failure)?;
    index.add_all(["*"].iter(), IndexAddOption::DEFAULT, None).map_err(git_failure)?;
    index.update_all(["*"].iter(), None).map_err(git_failure)?;
    index.write().map_err(git_failure)?;
    let tree_oid = index.write_tree().map_err(git_failure)?;
    let parent =
        repo.head().ok().and_then(|head| head.target()).and_then(|oid| repo.find_commit(oid).ok());
    if parent.as_ref().is_some_and(|commit| commit.tree_id() == tree_oid) {
        return Ok(None);
    }
    let signature = lg_signature(repo)?;
    let tree = repo.find_tree(tree_oid).map_err(git_failure)?;
    let parents = parent.iter().collect::<Vec<_>>();
    let oid = repo
        .commit(Some("HEAD"), &signature, &signature, message, &tree, &parents)
        .map_err(git_failure)?;
    Ok(Some(oid))
}

struct LgTarget {
    branch: String,
    local_ref: String,
    remote: String,
    /// `refs/heads/<name>` on the remote; `None` when the branch has no upstream yet.
    merge_ref: Option<String>,
}

impl LgTarget {
    fn destination_ref(&self) -> String {
        self.merge_ref.clone().unwrap_or_else(|| format!("refs/heads/{}", self.branch))
    }

    fn tracking_ref(&self) -> String {
        let destination = self.destination_ref();
        let short = destination.trim_start_matches("refs/heads/");
        format!("refs/remotes/{}/{short}", self.remote)
    }
}

fn lg_single_remote(repo: &Repository) -> Result<String, BridgeFailure> {
    let remotes = repo.remotes().map_err(git_failure)?;
    let names = remotes.iter().flatten().map(str::to_string).collect::<Vec<_>>();
    match names.as_slice() {
        [only] => Ok(only.clone()),
        [] => Err(git_error("no Git remote is configured")),
        _ => Err(git_error("current branch has no configured upstream")),
    }
}

fn lg_target(repo: &Repository) -> Result<LgTarget, BridgeFailure> {
    let head = repo.head().map_err(|_| git_error("the repository has no commits yet"))?;
    if !head.is_branch() {
        return Err(git_error("current Git HEAD is detached"));
    }
    let local_ref = head.name().ok_or_else(|| git_error("current branch has no name"))?.to_string();
    let branch = head.shorthand().ok_or_else(|| git_error("current branch has no name"))?.to_string();
    let config = repo.config().map_err(git_failure)?;
    let remote = config.get_string(&format!("branch.{branch}.remote")).ok();
    let merge_ref = config.get_string(&format!("branch.{branch}.merge")).ok();
    match (remote, merge_ref) {
        (Some(remote), Some(merge_ref)) if remote != "." && merge_ref.starts_with("refs/heads/") => {
            Ok(LgTarget { branch, local_ref, remote, merge_ref: Some(merge_ref) })
        }
        (Some(remote), Some(_)) if remote == "." => {
            Err(git_error("current branch has an unsupported upstream"))
        }
        _ => Ok(LgTarget { branch, local_ref, remote: lg_single_remote(repo)?, merge_ref: None }),
    }
}

fn lg_remote_name(repo: &Repository) -> Result<String, BridgeFailure> {
    match lg_target(repo) {
        Ok(target) => Ok(target.remote),
        Err(_) => lg_single_remote(repo),
    }
}

fn lg_fetch(repo: &Repository, remote_name: &str, transport: &GitTransport<'_>) -> Result<(), BridgeFailure> {
    crate::api::ensure_git_trace();
    trace_git(&format!("fetch {remote_name}"));
    let mut remote = repo.find_remote(remote_name).map_err(git_failure)?;
    let remote_url = remote.url().unwrap_or("").to_string();
    let (callbacks, probe) = transport_callbacks(transport, &remote_url)?;
    let mut options = FetchOptions::new();
    options.remote_callbacks(callbacks);
    remote.fetch(&[] as &[&str], Some(&mut options), None).map_err(|error| probe.failure(error))
}

pub(crate) fn lg_push(
    repo: &Repository,
    remote_name: &str,
    source_ref: &str,
    destination_ref: &str,
    transport: &GitTransport<'_>,
) -> Result<(), BridgeFailure> {
    crate::api::ensure_git_trace();
    trace_git(&format!("push {source_ref} to {remote_name}"));
    let mut remote = repo.find_remote(remote_name).map_err(git_failure)?;
    let remote_url = remote.url().unwrap_or("").to_string();
    let (mut callbacks, probe) = transport_callbacks(transport, &remote_url)?;
    let rejection = Rc::new(RefCell::new(None::<String>));
    let rejection_sink = rejection.clone();
    callbacks.push_update_reference(move |reference, status| {
        if let Some(status) = status {
            *rejection_sink.borrow_mut() = Some(format!("{reference}: {status}"));
        }
        Ok(())
    });
    let mut options = PushOptions::new();
    options.remote_callbacks(callbacks);
    let refspec = format!("{source_ref}:{destination_ref}");
    remote.push(&[&refspec], Some(&mut options)).map_err(|error| probe.failure(error))?;
    if let Some(reason) = rejection.borrow().as_deref() {
        return Err(git_error(&format!("the remote rejected the push ({reason})")));
    }
    Ok(())
}

fn lg_set_upstream(repo: &Repository, target: &LgTarget) -> Result<(), BridgeFailure> {
    let mut config = repo.config().map_err(git_failure)?;
    config.set_str(&format!("branch.{}.remote", target.branch), &target.remote).map_err(git_failure)?;
    config
        .set_str(&format!("branch.{}.merge", target.branch), &target.destination_ref())
        .map_err(git_failure)?;
    Ok(())
}

enum Integration {
    Done(Oid),
    Conflict(Vec<String>),
}

fn conflict_paths(index: &Index) -> Vec<String> {
    let mut paths = Vec::new();
    if let Ok(conflicts) = index.conflicts() {
        for conflict in conflicts.flatten() {
            let entry = conflict.our.or(conflict.their).or(conflict.ancestor);
            if let Some(entry) = entry {
                let path = String::from_utf8_lossy(&entry.path).into_owned();
                if !paths.contains(&path) {
                    paths.push(path);
                }
            }
        }
    }
    paths
}

fn lg_rebase(repo: &Repository, local: Oid, upstream: Oid) -> Result<Integration, BridgeFailure> {
    let committer = lg_signature(repo)?;
    let local_commit = repo.find_annotated_commit(local).map_err(git_failure)?;
    let upstream_commit = repo.find_annotated_commit(upstream).map_err(git_failure)?;
    let mut options = RebaseOptions::new();
    options.inmemory(true);
    let mut rebase = repo
        .rebase(Some(&local_commit), Some(&upstream_commit), None, Some(&mut options))
        .map_err(git_failure)?;
    let mut last = upstream;
    while let Some(operation) = rebase.next() {
        operation.map_err(git_failure)?;
        let index = rebase.inmemory_index().map_err(git_failure)?;
        if index.has_conflicts() {
            let paths = conflict_paths(&index);
            let _ = rebase.abort();
            return Ok(Integration::Conflict(paths));
        }
        match rebase.commit(None, &committer, None) {
            Ok(oid) => last = oid,
            Err(error) if error.code() == ErrorCode::Applied => {}
            Err(error) => {
                let _ = rebase.abort();
                return Err(git_failure(error));
            }
        }
    }
    rebase.finish(Some(&committer)).map_err(git_failure)?;
    Ok(Integration::Done(last))
}

fn lg_merge(
    repo: &Repository,
    local: Oid,
    upstream: Oid,
    message: &str,
) -> Result<Integration, BridgeFailure> {
    let signature = lg_signature(repo)?;
    let ours = repo.find_commit(local).map_err(git_failure)?;
    let theirs = repo.find_commit(upstream).map_err(git_failure)?;
    let mut index = repo.merge_commits(&ours, &theirs, None).map_err(git_failure)?;
    if index.has_conflicts() {
        return Ok(Integration::Conflict(conflict_paths(&index)));
    }
    let tree_oid = index.write_tree_to(repo).map_err(git_failure)?;
    let tree = repo.find_tree(tree_oid).map_err(git_failure)?;
    let oid = repo
        .commit(None, &signature, &signature, message, &tree, &[&ours, &theirs])
        .map_err(git_failure)?;
    Ok(Integration::Done(oid))
}

fn lg_create_backup(repo: &Repository, oid: Oid) -> Result<String, BridgeFailure> {
    let commit = repo.find_commit(oid).map_err(git_failure)?;
    let base = backup_branch_name(now_seconds());
    let mut name = base.clone();
    let mut suffix = 2;
    while repo.find_branch(&name, BranchType::Local).is_ok() {
        name = format!("{base}-{suffix}");
        suffix += 1;
    }
    repo.branch(&name, &commit, false).map_err(git_failure)?;
    trace_git("created local backup branch");
    Ok(name)
}

/// Moves the current branch from `expected` to `new` and forces the work tree to match. Fails if
/// another writer moved the branch in the meantime.
fn lg_move_branch(
    repo: &Repository,
    local_ref: &str,
    expected: Oid,
    new: Oid,
    force_checkout: bool,
) -> Result<(), BridgeFailure> {
    if !force_checkout {
        let object = repo.find_object(new, None).map_err(git_failure)?;
        repo.checkout_tree(&object, Some(CheckoutBuilder::new().safe())).map_err(git_failure)?;
    }
    repo.reference_matching(local_ref, new, true, expected, "Pars sync")
        .map_err(|_| git_error("the branch changed while syncing; try again"))?;
    repo.set_head(local_ref).map_err(git_failure)?;
    if force_checkout {
        repo.checkout_head(Some(CheckoutBuilder::new().force())).map_err(git_failure)?;
    }
    Ok(())
}

fn in_progress(summary: &GitStatusSummaryDto) -> bool {
    summary.operation != GitStatusOperationDto::None || summary.conflicted > 0
}

fn lg_conflicted_paths(repo: &Repository) -> Vec<String> {
    repo.index().map(|index| conflict_paths(&index)).unwrap_or_default()
}

pub(crate) fn lg_sync(
    root: &Path,
    transport: &GitTransport<'_>,
    message: &str,
    commit_pending: bool,
    strategy: GitIntegrationStrategyDto,
) -> Result<GitSyncResultDto, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let before = summarize_repository(root)?;
    let mut result = GitSyncResultDto {
        committed: false,
        pulled: 0,
        pushed: false,
        blocked_by_changes: false,
        conflict: None,
        summary: before.clone(),
    };
    if in_progress(&before) {
        result.conflict =
            Some(GitSyncConflictDto { backup_branch: None, paths: lg_conflicted_paths(&repo) });
        return Ok(result);
    }
    if commit_pending && before.changed > 0 {
        result.committed = lg_commit_all(&repo, message)?.is_some();
    }

    let target = lg_target(&repo)?;
    lg_fetch(&repo, &target.remote, transport)?;
    let Some(local) = repo.head().ok().and_then(|head| head.target()) else {
        result.summary = summarize_repository(root)?;
        return Ok(result);
    };
    let tracking = repo.refname_to_id(&target.tracking_ref()).ok();

    let mut current = local;
    if let Some(upstream) = tracking {
        let (ahead, behind) = repo.graph_ahead_behind(local, upstream).map_err(git_failure)?;
        if behind > 0 {
            let dirty = summarize_repository(root)?.changed > 0;
            if ahead == 0 {
                match lg_move_branch(&repo, &target.local_ref, local, upstream, false) {
                    Ok(()) => current = upstream,
                    Err(_) if dirty => {
                        result.blocked_by_changes = true;
                        result.summary = summarize_repository(root)?;
                        return Ok(result);
                    }
                    Err(error) => return Err(error),
                }
            } else {
                if dirty {
                    result.blocked_by_changes = true;
                    result.summary = summarize_repository(root)?;
                    return Ok(result);
                }
                let integration = match strategy {
                    GitIntegrationStrategyDto::Rebase => lg_rebase(&repo, local, upstream)?,
                    GitIntegrationStrategyDto::Merge => {
                        let upstream_name = target.tracking_ref().trim_start_matches("refs/remotes/").to_string();
                        let merge_message = format!("Merge {upstream_name} into {}", target.branch);
                        lg_merge(&repo, local, upstream, &merge_message)?
                    }
                };
                match integration {
                    Integration::Done(new) => {
                        lg_move_branch(&repo, &target.local_ref, local, new, true)?;
                        current = new;
                    }
                    Integration::Conflict(paths) => {
                        let backup = lg_create_backup(&repo, local)?;
                        result.conflict = Some(GitSyncConflictDto { backup_branch: Some(backup), paths });
                        result.summary = summarize_repository(root)?;
                        return Ok(result);
                    }
                }
            }
            result.pulled = u32::try_from(behind).unwrap_or(u32::MAX);
        }
        let (ahead_after, _) = repo.graph_ahead_behind(current, upstream).map_err(git_failure)?;
        if ahead_after > 0 {
            lg_push(&repo, &target.remote, &target.local_ref, &target.destination_ref(), transport)?;
            result.pushed = true;
        }
    } else {
        lg_push(&repo, &target.remote, &target.local_ref, &target.destination_ref(), transport)?;
        result.pushed = true;
    }
    if target.merge_ref.is_none() && result.pushed {
        lg_set_upstream(&repo, &target)?;
    }
    if result.pushed {
        // Keep the remote-tracking ref current so the summary does not report a stale ahead count.
        let _ = repo.reference(&target.tracking_ref(), current, true, "Pars push");
    }
    result.summary = summarize_repository(root)?;
    Ok(result)
}

fn lg_abort_operation(repo: &Repository) -> Result<(), BridgeFailure> {
    match repo.state() {
        RepositoryState::Clean => Ok(()),
        RepositoryState::Rebase | RepositoryState::RebaseInteractive | RepositoryState::RebaseMerge => {
            let mut rebase = repo.open_rebase(None).map_err(git_failure)?;
            rebase.abort().map_err(git_failure)
        }
        _ => {
            repo.cleanup_state().map_err(git_failure)?;
            let head = repo.head().and_then(|head| head.peel(git2::ObjectType::Commit)).map_err(git_failure)?;
            repo.reset(&head, ResetType::Hard, None).map_err(git_failure)
        }
    }
}

pub(crate) fn lg_reset(
    root: &Path,
    transport: &GitTransport<'_>,
    message: &str,
) -> Result<GitResetResultDto, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    lg_abort_operation(&repo)?;
    let target = lg_target(&repo)?;
    lg_fetch(&repo, &target.remote, transport)?;
    let upstream = repo
        .refname_to_id(&target.tracking_ref())
        .map_err(|_| git_error("the remote branch does not exist yet"))?;
    let committed = if summarize_repository(root)?.changed > 0 {
        lg_commit_all(&repo, message)?.is_some()
    } else {
        false
    };
    let local = repo.head().ok().and_then(|head| head.target());
    let backup_branch = match local {
        Some(local) if local != upstream && !repo.graph_descendant_of(upstream, local).map_err(git_failure)? => {
            Some(lg_create_backup(&repo, local)?)
        }
        _ => None,
    };
    let object = repo.find_object(upstream, None).map_err(git_failure)?;
    repo.reset(&object, ResetType::Hard, None).map_err(git_failure)?;
    Ok(GitResetResultDto { committed, backup_branch, summary: summarize_repository(root)? })
}

pub(crate) fn lg_push_branch(
    root: &Path,
    transport: &GitTransport<'_>,
    branch: &str,
) -> Result<String, BridgeFailure> {
    backup_branch_only(branch)?;
    let repo = Repository::open(root).map_err(git_failure)?;
    repo.find_branch(branch, BranchType::Local).map_err(|_| validation("backup branch not found"))?;
    let remote = lg_remote_name(&repo)?;
    let reference = format!("refs/heads/{branch}");
    lg_push(&repo, &remote, &reference, &reference, transport)?;
    Ok(format!("Pushed {branch} to {remote}.\n"))
}

fn backup_branch_only(branch: &str) -> Result<(), BridgeFailure> {
    valid_branch_name(branch)?;
    if !branch.starts_with(BACKUP_BRANCH_PREFIX) {
        return Err(validation("only Pars backup branches can be pushed this way"));
    }
    Ok(())
}

pub(crate) fn lg_log(root: &Path, limit: u32) -> Result<Vec<GitLogEntryDto>, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    if repo.head().ok().and_then(|head| head.target()).is_none() {
        return Ok(Vec::new());
    }
    let mut walk = repo.revwalk().map_err(git_failure)?;
    walk.set_sorting(Sort::TOPOLOGICAL | Sort::TIME).map_err(git_failure)?;
    walk.push_head().map_err(git_failure)?;
    let mut entries = Vec::new();
    for oid in walk.take(limit as usize) {
        let commit = repo.find_commit(oid.map_err(git_failure)?).map_err(git_failure)?;
        let id = commit
            .as_object()
            .short_id()
            .ok()
            .and_then(|buf| buf.as_str().map(str::to_string))
            .unwrap_or_else(|| commit.id().to_string()[..7].to_string());
        entries.push(GitLogEntryDto {
            id,
            summary: commit.summary().unwrap_or("").to_string(),
            author: commit.author().name().unwrap_or("").to_string(),
            time: commit.time().seconds(),
        });
    }
    Ok(entries)
}

pub(crate) fn lg_remote_branches(
    root: &Path,
) -> Result<RemoteBranches, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let current = repo.head().ok().filter(|head| head.is_branch()).and_then(|head| head.shorthand().map(str::to_string));
    let Ok(remote) = lg_remote_name(&repo) else {
        return Ok((None, current, Vec::new()));
    };
    let prefix = format!("{remote}/");
    let mut branches = Vec::new();
    for branch in repo.branches(Some(BranchType::Remote)).map_err(git_failure)?.flatten() {
        if let Ok(Some(name)) = branch.0.name() {
            if let Some(short) = name.strip_prefix(&prefix) {
                if short != "HEAD" && !short.starts_with(BACKUP_BRANCH_PREFIX) {
                    branches.push(short.to_string());
                }
            }
        }
    }
    branches.sort();
    Ok((Some(remote), current, branches))
}

fn require_switchable(summary: &GitStatusSummaryDto) -> Result<(), BridgeFailure> {
    if summary.changed > 0 || in_progress(summary) || summary.ahead > 0 {
        return Err(validation("sync before switching branch"));
    }
    Ok(())
}

pub(crate) fn lg_switch_branch(root: &Path, branch: &str) -> Result<GitStatusSummaryDto, BridgeFailure> {
    valid_branch_name(branch)?;
    require_switchable(&summarize_repository(root)?)?;
    let repo = Repository::open(root).map_err(git_failure)?;
    let remote = lg_remote_name(&repo)?;
    let remote_oid = repo
        .refname_to_id(&format!("refs/remotes/{remote}/{branch}"))
        .map_err(|_| validation("the remote branch does not exist"))?;
    let commit = repo.find_commit(remote_oid).map_err(git_failure)?;
    let local_ref = format!("refs/heads/{branch}");
    match repo.find_branch(branch, BranchType::Local) {
        Ok(existing) => {
            let local_oid = existing.get().target().ok_or_else(|| git_error("branch has no commit"))?;
            if local_oid != remote_oid && !repo.graph_descendant_of(remote_oid, local_oid).map_err(git_failure)? {
                return Err(validation("the local branch has commits that are not on the remote"));
            }
        }
        Err(_) => {
            repo.branch(branch, &commit, false).map_err(git_failure)?;
        }
    }
    repo.checkout_tree(commit.as_object(), Some(CheckoutBuilder::new().safe())).map_err(git_failure)?;
    repo.reference(&local_ref, remote_oid, true, "Pars switch branch").map_err(git_failure)?;
    repo.set_head(&local_ref).map_err(git_failure)?;
    let mut local = repo.find_branch(branch, BranchType::Local).map_err(git_failure)?;
    local.set_upstream(Some(&format!("{remote}/{branch}"))).map_err(git_failure)?;
    summarize_repository(root)
}

pub(crate) fn lg_identity(root: &Path) -> Result<Option<GitIdentityDto>, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let config = repo.config().map_err(git_failure)?;
    let read = |config: &git2::Config, key: &str| {
        config.get_string(key).ok().map(|value| value.trim().to_string()).filter(|value| !value.is_empty())
    };
    let (Some(name), Some(email)) = (read(&config, "user.name"), read(&config, "user.email")) else {
        return Ok(None);
    };
    let local = config
        .open_level(ConfigLevel::Local)
        .map(|local| read(&local, "user.name").is_some() && read(&local, "user.email").is_some())
        .unwrap_or(false);
    Ok(Some(GitIdentityDto { name, email, local }))
}

pub(crate) fn lg_set_identity(root: &Path, name: &str, email: &str) -> Result<(), BridgeFailure> {
    let (name, email) = validated_identity(name, email)?;
    let repo = Repository::open(root).map_err(git_failure)?;
    let mut local = repo.config().and_then(|config| config.open_level(ConfigLevel::Local)).map_err(git_failure)?;
    local.set_str("user.name", &name).map_err(git_failure)?;
    local.set_str("user.email", &email).map_err(git_failure)?;
    Ok(())
}

pub(crate) fn lg_fetch_summary(
    root: &Path,
    transport: &GitTransport<'_>,
) -> Result<GitStatusSummaryDto, BridgeFailure> {
    let repo = Repository::open(root).map_err(git_failure)?;
    let remote = lg_remote_name(&repo)?;
    lg_fetch(&repo, &remote, transport)?;
    summarize_repository(root)
}

// ---------------------------------------------------------------------------------------------
// System git (desktop)
// ---------------------------------------------------------------------------------------------

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) mod sys {
    use std::path::Path;
    use std::process::{Command, Output};

    use super::*;
    use crate::api::{git_process_failure, git_ssh_command, with_selected_known_hosts};
    use crate::git_status::parse_porcelain_v2;

    fn run(root: &Path, args: &[&str], known_hosts_file: Option<&Path>) -> Result<Output, BridgeFailure> {
        let mut command = Command::new("git");
        command
            .args(args)
            .current_dir(root)
            .env("GIT_EDITOR", "true")
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("LC_ALL", "C");
        if let Some(file) = known_hosts_file {
            command.env("GIT_SSH_COMMAND", git_ssh_command(file));
        }
        command.output().map_err(|error| git_error(&error.to_string()))
    }

    fn failure(output: &Output) -> BridgeFailure {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.contains("Please tell me who you are")
            || stderr.contains("empty ident name")
            || stderr.contains("unable to auto-detect email address")
        {
            return identity_required();
        }
        git_process_failure(output)
    }

    fn ok(root: &Path, args: &[&str], known_hosts_file: Option<&Path>) -> Result<String, BridgeFailure> {
        let output = run(root, args, known_hosts_file)?;
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        } else {
            Err(failure(&output))
        }
    }

    fn value(root: &Path, args: &[&str]) -> Option<String> {
        let output = run(root, args, None).ok()?;
        if !output.status.success() {
            return None;
        }
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        (!text.is_empty()).then_some(text)
    }

    fn with_known_hosts<T>(
        known_hosts: Option<&str>,
        body: impl FnOnce(Option<&Path>) -> Result<T, BridgeFailure>,
    ) -> Result<T, BridgeFailure> {
        with_selected_known_hosts(known_hosts, body)?
    }

    pub(crate) fn summary(root: &Path) -> Result<GitStatusSummaryDto, BridgeFailure> {
        let git_dir = ok(root, &["rev-parse", "--absolute-git-dir"], None)?;
        let output = run(root, &["status", "--porcelain=v2", "--branch", "-z"], None)?;
        if !output.status.success() {
            return Err(failure(&output));
        }
        parse_porcelain_v2(&output.stdout, Path::new(git_dir.trim()))
    }

    pub(crate) fn identity(root: &Path) -> Result<Option<GitIdentityDto>, BridgeFailure> {
        let (Some(name), Some(email)) =
            (value(root, &["config", "user.name"]), value(root, &["config", "user.email"]))
        else {
            return Ok(None);
        };
        let local = value(root, &["config", "--local", "user.name"]).is_some()
            && value(root, &["config", "--local", "user.email"]).is_some();
        Ok(Some(GitIdentityDto { name, email, local }))
    }

    pub(crate) fn set_identity(root: &Path, name: &str, email: &str) -> Result<(), BridgeFailure> {
        let (name, email) = validated_identity(name, email)?;
        ok(root, &["config", "--local", "user.name", &name], None)?;
        ok(root, &["config", "--local", "user.email", &email], None)?;
        Ok(())
    }

    fn require_identity(root: &Path) -> Result<(), BridgeFailure> {
        identity(root)?.map(|_| ()).ok_or_else(identity_required)
    }

    struct SysTarget {
        branch: String,
        remote: String,
        merge_ref: Option<String>,
    }

    impl SysTarget {
        fn destination_ref(&self) -> String {
            self.merge_ref.clone().unwrap_or_else(|| format!("refs/heads/{}", self.branch))
        }

        fn tracking_ref(&self) -> String {
            let destination = self.destination_ref();
            format!("refs/remotes/{}/{}", self.remote, destination.trim_start_matches("refs/heads/"))
        }
    }

    fn single_remote(root: &Path) -> Result<String, BridgeFailure> {
        let remotes = ok(root, &["remote"], None)?;
        let names = remotes.lines().map(str::trim).filter(|line| !line.is_empty()).collect::<Vec<_>>();
        match names.as_slice() {
            [only] => Ok((*only).to_string()),
            [] => Err(git_error("no Git remote is configured")),
            _ => Err(git_error("current branch has no configured upstream")),
        }
    }

    fn target(root: &Path) -> Result<SysTarget, BridgeFailure> {
        let branch = value(root, &["symbolic-ref", "--short", "-q", "HEAD"])
            .ok_or_else(|| git_error("current Git HEAD is detached"))?;
        let remote = value(root, &["config", &format!("branch.{branch}.remote")]);
        let merge_ref = value(root, &["config", &format!("branch.{branch}.merge")]);
        match (remote, merge_ref) {
            (Some(remote), Some(merge_ref)) if remote != "." && merge_ref.starts_with("refs/heads/") => {
                Ok(SysTarget { branch, remote, merge_ref: Some(merge_ref) })
            }
            (Some(remote), Some(_)) if remote == "." => {
                Err(git_error("current branch has an unsupported upstream"))
            }
            _ => Ok(SysTarget { branch, remote: single_remote(root)?, merge_ref: None }),
        }
    }

    fn remote_name(root: &Path) -> Result<String, BridgeFailure> {
        match target(root) {
            Ok(target) => Ok(target.remote),
            Err(_) => single_remote(root),
        }
    }

    fn rev(root: &Path, reference: &str) -> Option<String> {
        value(root, &["rev-parse", "--verify", "-q", &format!("{reference}^{{commit}}")])
    }

    fn count(root: &Path, range: &str) -> Result<u32, BridgeFailure> {
        let text = ok(root, &["rev-list", "--count", range], None)?;
        Ok(text.trim().parse().unwrap_or(0))
    }

    fn unmerged_paths(root: &Path) -> Vec<String> {
        value(root, &["diff", "--name-only", "--diff-filter=U"])
            .map(|text| text.lines().map(str::to_string).collect())
            .unwrap_or_default()
    }

    fn create_backup(root: &Path, commit: &str) -> Result<String, BridgeFailure> {
        let base = backup_branch_name(now_seconds());
        let mut name = base.clone();
        let mut suffix = 2;
        while rev(root, &format!("refs/heads/{name}")).is_some() {
            name = format!("{base}-{suffix}");
            suffix += 1;
        }
        ok(root, &["branch", &name, commit], None)?;
        Ok(name)
    }

    fn commit_all(root: &Path, message: &str) -> Result<bool, BridgeFailure> {
        require_identity(root)?;
        ok(root, &["add", "-A"], None)?;
        if run(root, &["diff", "--cached", "--quiet"], None)?.status.success() {
            return Ok(false);
        }
        ok(root, &["commit", "-m", message], None)?;
        Ok(true)
    }

    pub(crate) fn fetch(root: &Path, known_hosts: Option<&str>) -> Result<GitStatusSummaryDto, BridgeFailure> {
        let remote = remote_name(root)?;
        with_known_hosts(known_hosts, |file| ok(root, &["fetch", &remote], file).map(|_| ()))?;
        summary(root)
    }

    pub(crate) fn sync(
        root: &Path,
        known_hosts: Option<&str>,
        message: &str,
        commit_pending: bool,
        strategy: GitIntegrationStrategyDto,
    ) -> Result<GitSyncResultDto, BridgeFailure> {
        let before = summary(root)?;
        let mut result = GitSyncResultDto {
            committed: false,
            pulled: 0,
            pushed: false,
            blocked_by_changes: false,
            conflict: None,
            summary: before.clone(),
        };
        if in_progress(&before) {
            result.conflict = Some(GitSyncConflictDto { backup_branch: None, paths: unmerged_paths(root) });
            return Ok(result);
        }
        if commit_pending && before.changed > 0 {
            result.committed = commit_all(root, message)?;
        }
        let target = target(root)?;
        with_known_hosts(known_hosts, |file| {
            ok(root, &["fetch", &target.remote], file)?;
            let Some(local) = rev(root, "HEAD") else {
                return Ok(());
            };
            let tracking_ref = target.tracking_ref();
            let destination = format!("HEAD:{}", target.destination_ref());
            if rev(root, &tracking_ref).is_none() {
                ok(root, &["push", "--set-upstream", &target.remote, &destination], file)?;
                result.pushed = true;
                return Ok(());
            }
            let behind = count(root, &format!("HEAD..{tracking_ref}"))?;
            let ahead = count(root, &format!("{tracking_ref}..HEAD"))?;
            if behind > 0 {
                let dirty = summary(root)?.changed > 0;
                if ahead == 0 {
                    let output = run(root, &["merge", "--ff-only", &tracking_ref], None)?;
                    if !output.status.success() {
                        if dirty {
                            result.blocked_by_changes = true;
                            return Ok(());
                        }
                        return Err(failure(&output));
                    }
                } else {
                    if dirty {
                        result.blocked_by_changes = true;
                        return Ok(());
                    }
                    require_identity(root)?;
                    let upstream_name = tracking_ref.trim_start_matches("refs/remotes/").to_string();
                    let output = match strategy {
                        GitIntegrationStrategyDto::Rebase => run(root, &["rebase", &tracking_ref], None)?,
                        GitIntegrationStrategyDto::Merge => {
                            let merge_message = format!("Merge {upstream_name} into {}", target.branch);
                            run(root, &["merge", "--no-edit", "--no-ff", "-m", &merge_message, &tracking_ref], None)?
                        }
                    };
                    if !output.status.success() {
                        let paths = unmerged_paths(root);
                        let abort = match strategy {
                            GitIntegrationStrategyDto::Rebase => ["rebase", "--abort"],
                            GitIntegrationStrategyDto::Merge => ["merge", "--abort"],
                        };
                        let _ = run(root, &abort, None);
                        if paths.is_empty() {
                            return Err(failure(&output));
                        }
                        let backup = create_backup(root, &local)?;
                        result.conflict = Some(GitSyncConflictDto { backup_branch: Some(backup), paths });
                        return Ok(());
                    }
                }
                result.pulled = behind;
            }
            if count(root, &format!("{tracking_ref}..HEAD"))? > 0 {
                let mut args = vec!["push"];
                if target.merge_ref.is_none() {
                    args.push("--set-upstream");
                }
                args.push(&target.remote);
                args.push(&destination);
                ok(root, &args, file)?;
                result.pushed = true;
            }
            Ok(())
        })?;
        result.summary = summary(root)?;
        Ok(result)
    }

    fn abort_operation(root: &Path) {
        let current = summary(root).map(|summary| summary.operation).unwrap_or(GitStatusOperationDto::None);
        match current {
            GitStatusOperationDto::Rebasing => {
                let _ = run(root, &["rebase", "--abort"], None);
            }
            GitStatusOperationDto::Merging => {
                let _ = run(root, &["merge", "--abort"], None);
            }
            GitStatusOperationDto::Other => {
                let _ = run(root, &["cherry-pick", "--abort"], None);
                let _ = run(root, &["revert", "--abort"], None);
            }
            GitStatusOperationDto::None => {}
        }
    }

    pub(crate) fn reset(
        root: &Path,
        known_hosts: Option<&str>,
        message: &str,
    ) -> Result<GitResetResultDto, BridgeFailure> {
        abort_operation(root);
        let target = target(root)?;
        with_known_hosts(known_hosts, |file| ok(root, &["fetch", &target.remote], file).map(|_| ()))?;
        let tracking_ref = target.tracking_ref();
        if rev(root, &tracking_ref).is_none() {
            return Err(git_error("the remote branch does not exist yet"));
        }
        let committed = if summary(root)?.changed > 0 { commit_all(root, message)? } else { false };
        let backup_branch = match rev(root, "HEAD") {
            Some(local) if count(root, &format!("{tracking_ref}..HEAD"))? > 0 => Some(create_backup(root, &local)?),
            _ => None,
        };
        ok(root, &["reset", "--hard", &tracking_ref], None)?;
        Ok(GitResetResultDto { committed, backup_branch, summary: summary(root)? })
    }

    pub(crate) fn push_branch(root: &Path, known_hosts: Option<&str>, branch: &str) -> Result<String, BridgeFailure> {
        backup_branch_only(branch)?;
        let reference = format!("refs/heads/{branch}");
        if rev(root, &reference).is_none() {
            return Err(validation("backup branch not found"));
        }
        let remote = remote_name(root)?;
        let refspec = format!("{reference}:{reference}");
        with_known_hosts(known_hosts, |file| ok(root, &["push", &remote, &refspec], file))
    }

    pub(crate) fn log(root: &Path, limit: u32) -> Result<Vec<GitLogEntryDto>, BridgeFailure> {
        if rev(root, "HEAD").is_none() {
            return Ok(Vec::new());
        }
        let limit = limit.to_string();
        let text = ok(root, &["log", "-z", "--format=%h%x1f%s%x1f%an%x1f%at", "-n", &limit], None)?;
        Ok(text
            .split('\0')
            .filter(|record| !record.trim().is_empty())
            .filter_map(|record| {
                let mut fields = record.trim_start_matches('\n').split('\u{1f}');
                Some(GitLogEntryDto {
                    id: fields.next()?.to_string(),
                    summary: fields.next()?.to_string(),
                    author: fields.next()?.to_string(),
                    time: fields.next()?.trim().parse().ok()?,
                })
            })
            .collect())
    }

    pub(crate) fn remote_branches(
        root: &Path,
    ) -> Result<RemoteBranches, BridgeFailure> {
        let current = value(root, &["symbolic-ref", "--short", "-q", "HEAD"]);
        let Ok(remote) = remote_name(root) else {
            return Ok((None, current, Vec::new()));
        };
        let prefix = format!("refs/remotes/{remote}/");
        let text = ok(root, &["for-each-ref", "--format=%(refname)", &prefix], None)?;
        let mut branches = text
            .lines()
            .filter_map(|line| line.strip_prefix(&prefix))
            .filter(|name| *name != "HEAD" && !name.starts_with(BACKUP_BRANCH_PREFIX))
            .map(str::to_string)
            .collect::<Vec<_>>();
        branches.sort();
        Ok((Some(remote), current, branches))
    }

    pub(crate) fn switch_branch(root: &Path, branch: &str) -> Result<GitStatusSummaryDto, BridgeFailure> {
        valid_branch_name(branch)?;
        require_switchable(&summary(root)?)?;
        let remote = remote_name(root)?;
        let remote_ref = format!("refs/remotes/{remote}/{branch}");
        if rev(root, &remote_ref).is_none() {
            return Err(validation("the remote branch does not exist"));
        }
        if rev(root, &format!("refs/heads/{branch}")).is_some() {
            if count(root, &format!("{remote_ref}..refs/heads/{branch}"))? > 0 {
                return Err(validation("the local branch has commits that are not on the remote"));
            }
            ok(root, &["switch", branch], None)?;
            ok(root, &["merge", "--ff-only", &remote_ref], None)?;
            ok(root, &["branch", &format!("--set-upstream-to={remote}/{branch}")], None)?;
        } else {
            ok(root, &["switch", "--track", &format!("{remote}/{branch}")], None)?;
        }
        summary(root)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;

    fn init_repo(root: &Path) -> Repository {
        fs::create_dir_all(root).unwrap();
        let repo = Repository::init(root).expect("init");
        let mut config = repo.config().unwrap();
        config.set_str("user.name", "Pars Test").unwrap();
        config.set_str("user.email", "pars@example.invalid").unwrap();
        repo
    }

    fn write(root: &Path, name: &str, content: &str) {
        fs::write(root.join(name), content).unwrap();
    }

    struct Fixture {
        _temp: tempfile::TempDir,
        bare: PathBuf,
        source: PathBuf,
        clone: PathBuf,
    }

    fn clone_with_upstream(bare: &Path, path: &Path) -> Repository {
        let repo = Repository::clone(bare.to_str().unwrap(), path).unwrap();
        let mut config = repo.config().unwrap();
        config.set_str("user.name", "Pars Test").unwrap();
        config.set_str("user.email", "pars@example.invalid").unwrap();
        repo
    }

    /// A bare remote with one commit, plus two clones that both track it.
    fn fixture() -> Fixture {
        let temp = tempfile::tempdir().unwrap();
        let bare = temp.path().join("remote.git");
        let seed = temp.path().join("seed");
        let seed_repo = init_repo(&seed);
        write(&seed, ".gpg-id", "ABC\n");
        lg_commit_all(&seed_repo, "Initial").unwrap();
        let branch = seed_repo.head().unwrap().shorthand().unwrap().to_string();
        Repository::init_bare(&bare).unwrap();
        seed_repo.remote("origin", bare.to_str().unwrap()).unwrap();
        let reference = format!("refs/heads/{branch}");
        lg_push(&seed_repo, "origin", &reference, &reference, &GitTransport::default()).unwrap();
        Repository::open_bare(&bare).unwrap().set_head(&reference).unwrap();
        let source = temp.path().join("source");
        let clone = temp.path().join("clone");
        clone_with_upstream(&bare, &source);
        clone_with_upstream(&bare, &clone);
        Fixture { _temp: temp, bare, source, clone }
    }

    fn commit_file(root: &Path, name: &str, content: &str, message: &str) {
        write(root, name, content);
        let repo = Repository::open(root).unwrap();
        lg_commit_all(&repo, message).unwrap().expect("commit");
    }

    fn sync(root: &Path, commit_pending: bool, strategy: GitIntegrationStrategyDto) -> GitSyncResultDto {
        lg_sync(root, &GitTransport::default(), "Sync", commit_pending, strategy).unwrap()
    }

    fn head(root: &Path) -> Oid {
        Repository::open(root).unwrap().head().unwrap().target().unwrap()
    }

    fn remote_head(fixture: &Fixture) -> Oid {
        let bare = Repository::open_bare(&fixture.bare).unwrap();
        let oid = bare.head().unwrap().target().unwrap();
        oid
    }

    #[test]
    fn backup_branch_name_uses_utc_date_and_time() {
        assert_eq!(backup_branch_name(0), "pars/backup-19700101-000000");
        assert_eq!(backup_branch_name(1_790_762_400), "pars/backup-20260930-100000");
        assert_eq!(backup_branch_name(951_782_400), "pars/backup-20000229-000000");
    }

    #[test]
    fn fetch_reports_behind_without_touching_the_branch_or_work_tree() {
        let fixture = fixture();
        commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
        sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
        let before = head(&fixture.clone);
        let summary = lg_fetch_summary(&fixture.clone, &GitTransport::default()).unwrap();
        assert_eq!(summary.behind, 1);
        assert_eq!(summary.ahead, 0);
        assert!(summary.last_fetched_at.is_some());
        assert_eq!(head(&fixture.clone), before);
        assert!(!fixture.clone.join("remote.gpg").exists());
    }

    #[test]
    fn pending_edit_is_committed_and_pushed() {
        let fixture = fixture();
        write(&fixture.clone, "entry.gpg", "one");
        let result = sync(&fixture.clone, true, GitIntegrationStrategyDto::Rebase);
        assert!(result.committed);
        assert!(result.pushed);
        assert_eq!(result.summary.changed, 0);
        assert_eq!(result.summary.ahead, 0);
        assert_eq!(remote_head(&fixture), head(&fixture.clone));
    }

    #[test]
    fn fast_forward_keeps_an_unrelated_uncommitted_edit() {
        let fixture = fixture();
        commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
        sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
        write(&fixture.clone, "local.gpg", "local");
        let result = sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);
        assert!(!result.blocked_by_changes);
        assert_eq!(result.pulled, 1);
        assert!(fixture.clone.join("remote.gpg").is_file());
        assert_eq!(fs::read_to_string(fixture.clone.join("local.gpg")).unwrap(), "local");
        assert_eq!(result.summary.changed, 1);
    }

    #[test]
    fn overlapping_uncommitted_edit_blocks_fast_forward() {
        let fixture = fixture();
        commit_file(&fixture.source, ".gpg-id", "REMOTE\n", "Remote");
        sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
        let before = head(&fixture.clone);
        write(&fixture.clone, ".gpg-id", "LOCAL\n");
        let result = sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);
        assert!(result.blocked_by_changes);
        assert_eq!(head(&fixture.clone), before);
        assert_eq!(fs::read_to_string(fixture.clone.join(".gpg-id")).unwrap(), "LOCAL\n");
    }

    #[test]
    fn dirty_diverged_tree_is_blocked() {
        let fixture = fixture();
        commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
        sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
        commit_file(&fixture.clone, "local.gpg", "local", "Local");
        write(&fixture.clone, "pending.gpg", "pending");
        let before = head(&fixture.clone);
        let result = sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);
        assert!(result.blocked_by_changes);
        assert!(!result.pushed);
        assert_eq!(head(&fixture.clone), before);
    }

    #[test]
    fn diverged_history_is_rebased_without_a_merge_commit() {
        let fixture = fixture();
        commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
        sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
        commit_file(&fixture.clone, "local.gpg", "local", "Local");
        let result = sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);
        assert!(result.conflict.is_none());
        assert!(result.pushed);
        assert_eq!(result.pulled, 1);
        let repo = Repository::open(&fixture.clone).unwrap();
        let tip = repo.head().unwrap().peel_to_commit().unwrap();
        assert_eq!(tip.parent_count(), 1);
        assert_eq!(tip.summary(), Some("Local"));
        assert!(fixture.clone.join("remote.gpg").is_file());
        assert_eq!(remote_head(&fixture), tip.id());
        assert_eq!(result.summary.ahead, 0);
        assert_eq!(result.summary.behind, 0);
    }

    #[test]
    fn merge_strategy_creates_a_two_parent_commit() {
        let fixture = fixture();
        commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
        sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
        commit_file(&fixture.clone, "local.gpg", "local", "Local");
        let local = head(&fixture.clone);
        let result = sync(&fixture.clone, false, GitIntegrationStrategyDto::Merge);
        assert!(result.conflict.is_none());
        let repo = Repository::open(&fixture.clone).unwrap();
        let tip = repo.head().unwrap().peel_to_commit().unwrap();
        assert_eq!(tip.parent_count(), 2);
        assert_eq!(tip.parent_id(0).unwrap(), local);
        assert!(tip.summary().unwrap().starts_with("Merge origin/"));
        assert_eq!(remote_head(&fixture), tip.id());
    }

    #[test]
    fn conflicts_leave_the_branch_unchanged_and_keep_a_backup() {
        for strategy in [GitIntegrationStrategyDto::Rebase, GitIntegrationStrategyDto::Merge] {
            let fixture = fixture();
            commit_file(&fixture.source, ".gpg-id", "REMOTE\n", "Remote");
            sync(&fixture.source, false, strategy);
            commit_file(&fixture.clone, ".gpg-id", "LOCAL\n", "Local");
            let before = head(&fixture.clone);
            let result = sync(&fixture.clone, false, strategy);
            let conflict = result.conflict.expect("conflict");
            assert_eq!(conflict.paths, vec![".gpg-id".to_string()]);
            let backup = conflict.backup_branch.expect("backup");
            assert!(backup.starts_with(BACKUP_BRANCH_PREFIX));
            let repo = Repository::open(&fixture.clone).unwrap();
            assert_eq!(repo.state(), RepositoryState::Clean);
            assert_eq!(head(&fixture.clone), before);
            assert_eq!(
                repo.find_branch(&backup, BranchType::Local).unwrap().get().target().unwrap(),
                before
            );
            assert_eq!(fs::read_to_string(fixture.clone.join(".gpg-id")).unwrap(), "LOCAL\n");
            assert!(!result.pushed);

            lg_push_branch(&fixture.clone, &GitTransport::default(), &backup).unwrap();
            let bare = Repository::open_bare(&fixture.bare).unwrap();
            assert_eq!(bare.refname_to_id(&format!("refs/heads/{backup}")).unwrap(), before);
        }
    }

    #[test]
    fn first_push_sets_the_upstream() {
        let temp = tempfile::tempdir().unwrap();
        let bare = temp.path().join("remote.git");
        Repository::init_bare(&bare).unwrap();
        let root = temp.path().join("store");
        let repo = init_repo(&root);
        write(&root, ".gpg-id", "ABC\n");
        lg_commit_all(&repo, "Initial").unwrap();
        repo.remote("origin", bare.to_str().unwrap()).unwrap();
        let branch = repo.head().unwrap().shorthand().unwrap().to_string();

        let result = sync(&root, false, GitIntegrationStrategyDto::Rebase);
        assert!(result.pushed);
        let config = Repository::open(&root).unwrap().config().unwrap();
        assert_eq!(config.get_string(&format!("branch.{branch}.remote")).unwrap(), "origin");
        assert_eq!(
            config.get_string(&format!("branch.{branch}.merge")).unwrap(),
            format!("refs/heads/{branch}")
        );
        assert_eq!(result.summary.upstream.as_deref(), Some(format!("origin/{branch}").as_str()));
        assert_eq!(result.summary.ahead, 0);
    }

    #[test]
    fn missing_identity_is_typed_and_nothing_is_committed() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("store");
        let repo = init_repo(&root);
        repo.config().unwrap().set_str("user.name", "").unwrap();
        write(&root, ".gpg-id", "ABC\n");
        let error = lg_commit_all(&repo, "Initial").unwrap_err();
        assert!(matches!(error.category, BridgeFailureCategory::IdentityRequired));
        assert!(repo.head().is_err());
    }

    #[test]
    fn reset_backs_up_unpushed_and_uncommitted_work() {
        let fixture = fixture();
        commit_file(&fixture.clone, "local.gpg", "local", "Local");
        write(&fixture.clone, "pending.gpg", "pending");
        let result = lg_reset(&fixture.clone, &GitTransport::default(), "Before reset").unwrap();
        assert!(result.committed);
        let backup = result.backup_branch.expect("backup");
        assert_eq!(head(&fixture.clone), remote_head(&fixture));
        assert!(!fixture.clone.join("local.gpg").exists());
        assert!(!fixture.clone.join("pending.gpg").exists());
        let repo = Repository::open(&fixture.clone).unwrap();
        let backup_commit = repo.find_branch(&backup, BranchType::Local).unwrap().get().peel_to_commit().unwrap();
        assert!(backup_commit.tree().unwrap().get_name("pending.gpg").is_some());
        assert!(backup_commit.tree().unwrap().get_name("local.gpg").is_some());
    }

    #[test]
    fn reset_of_a_clean_up_to_date_branch_makes_no_backup() {
        let fixture = fixture();
        let result = lg_reset(&fixture.clone, &GitTransport::default(), "Before reset").unwrap();
        assert!(!result.committed);
        assert!(result.backup_branch.is_none());
    }

    #[test]
    fn log_lists_recent_commits_newest_first_and_handles_unborn() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("store");
        let repo = init_repo(&root);
        assert!(lg_log(&root, 50).unwrap().is_empty());
        for index in 0..3 {
            write(&root, "entry.gpg", &index.to_string());
            lg_commit_all(&repo, &format!("Commit {index}")).unwrap();
        }
        let entries = lg_log(&root, 2).unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].summary, "Commit 2");
        assert_eq!(entries[1].summary, "Commit 1");
        assert_eq!(entries[0].author, "Pars Test");
        assert!(entries[0].id.len() >= 7);
    }

    #[test]
    fn branch_switching_requires_a_clean_pushed_branch() {
        let fixture = fixture();
        {
            let source = Repository::open(&fixture.source).unwrap();
            let commit = source.head().unwrap().peel_to_commit().unwrap();
            source.branch("archive", &commit, false).unwrap();
            let reference = "refs/heads/archive";
            lg_push(&source, "origin", reference, reference, &GitTransport::default()).unwrap();
        }
        lg_fetch_summary(&fixture.clone, &GitTransport::default()).unwrap();
        let (remote, _, branches) = lg_remote_branches(&fixture.clone).unwrap();
        assert_eq!(remote.as_deref(), Some("origin"));
        assert!(branches.contains(&"archive".to_string()));

        commit_file(&fixture.clone, "local.gpg", "local", "Local");
        assert!(lg_switch_branch(&fixture.clone, "archive").is_err());
        sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);

        let summary = lg_switch_branch(&fixture.clone, "archive").unwrap();
        assert_eq!(summary.branch.as_deref(), Some("archive"));
        assert_eq!(summary.upstream.as_deref(), Some("origin/archive"));
        assert!(lg_switch_branch(&fixture.clone, "-bad").is_err());
    }

    #[test]
    fn identity_reads_and_writes_local_config() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("store");
        let repo = init_repo(&root);
        let identity = lg_identity(&root).unwrap().unwrap();
        assert_eq!(identity.name, "Pars Test");
        assert!(identity.local);
        lg_set_identity(&root, " Ada Lovelace ", "ada@example.invalid").unwrap();
        let local = repo.config().unwrap().open_level(ConfigLevel::Local).unwrap();
        assert_eq!(local.get_string("user.name").unwrap(), "Ada Lovelace");
        assert!(lg_set_identity(&root, "", "ada@example.invalid").is_err());
        assert!(lg_set_identity(&root, "Ada", "a <b>").is_err());
    }

    #[test]
    fn push_branch_only_accepts_backup_branches() {
        let fixture = fixture();
        let error = lg_push_branch(&fixture.clone, &GitTransport::default(), "main").unwrap_err();
        assert!(error.message.contains("backup"));
    }

    #[test]
    fn credentials_never_reach_results_or_files() {
        let fixture = fixture();
        write(&fixture.clone, "entry.gpg", "one");
        let transport = GitTransport {
            https_username: Some("ada"),
            https_token: Some("tok-secret-value"),
            ssh_passphrase: Some("pass-secret-value"),
            ..GitTransport::default()
        };
        let result = lg_sync(
            &fixture.clone,
            &transport,
            "Sync",
            true,
            GitIntegrationStrategyDto::Rebase,
        )
        .unwrap();
        let rendered = format!("{result:?}");
        assert!(!rendered.contains("tok-secret-value"));
        assert!(!rendered.contains("pass-secret-value"));

        let mut pending = vec![fixture._temp.path().to_path_buf()];
        while let Some(path) = pending.pop() {
            for entry in fs::read_dir(&path).unwrap().flatten() {
                let path = entry.path();
                if path.is_dir() {
                    pending.push(path);
                } else if let Ok(bytes) = fs::read(&path) {
                    let text = String::from_utf8_lossy(&bytes);
                    assert!(!text.contains("tok-secret-value"), "{}", path.display());
                    assert!(!text.contains("pass-secret-value"), "{}", path.display());
                }
            }
        }
    }

    #[test]
    fn https_callback_offers_credentials_once_and_types_rejection() {
        let transport = GitTransport {
            https_username: Some("ada"),
            https_token: Some("token-value"),
            ..GitTransport::default()
        };
        let (_callbacks, probe) =
            transport_callbacks(&transport, "https://example.invalid/pass.git").unwrap();
        let failure = probe.failure(git2::Error::from_str("boom"));
        assert!(matches!(failure.category, BridgeFailureCategory::GitError));
        probe.issue.set(AuthIssue::HttpsRequired);
        let failure = probe.failure(git2::Error::from_str("token-value rejected"));
        assert!(matches!(failure.category, BridgeFailureCategory::AuthenticationRequired));
        assert!(!failure.message.contains("token-value"));
    }

    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    mod system {
        use super::*;
        use std::process::Command;

        fn git(root: &Path, args: &[&str]) {
            let status = Command::new("git").args(args).current_dir(root).env("LC_ALL", "C").output().unwrap();
            assert!(status.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&status.stderr));
        }

        fn sys_fixture() -> Fixture {
            let fixture = fixture();
            for root in [&fixture.source, &fixture.clone] {
                git(root, &["config", "pull.rebase", "false"]);
            }
            fixture
        }

        fn sys_sync(root: &Path, commit_pending: bool, strategy: GitIntegrationStrategyDto) -> GitSyncResultDto {
            sys::sync(root, None, "Sync", commit_pending, strategy).unwrap()
        }

        #[test]
        fn desktop_summary_matches_porcelain() {
            let fixture = sys_fixture();
            write(&fixture.clone, "pending.gpg", "x");
            let summary = sys::summary(&fixture.clone).unwrap();
            assert_eq!(summary.changed, 1);
            assert!(summary.upstream.is_some());
        }

        #[test]
        fn desktop_sync_rebases_even_with_pull_rebase_false() {
            let fixture = sys_fixture();
            commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
            sys_sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
            commit_file(&fixture.clone, "local.gpg", "local", "Local");
            let result = sys_sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);
            assert!(result.conflict.is_none());
            assert!(result.pushed);
            let repo = Repository::open(&fixture.clone).unwrap();
            let tip = repo.head().unwrap().peel_to_commit().unwrap();
            assert_eq!(tip.parent_count(), 1);
            assert_eq!(remote_head(&fixture), tip.id());
        }

        #[test]
        fn desktop_merge_strategy_creates_a_merge_commit() {
            let fixture = sys_fixture();
            commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
            sys_sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
            commit_file(&fixture.clone, "local.gpg", "local", "Local");
            let result = sys_sync(&fixture.clone, false, GitIntegrationStrategyDto::Merge);
            assert!(result.conflict.is_none());
            let repo = Repository::open(&fixture.clone).unwrap();
            let tip = repo.head().unwrap().peel_to_commit().unwrap();
            assert_eq!(tip.parent_count(), 2);
        }

        #[test]
        fn desktop_conflict_aborts_and_keeps_a_backup() {
            for strategy in [GitIntegrationStrategyDto::Rebase, GitIntegrationStrategyDto::Merge] {
                let fixture = sys_fixture();
                commit_file(&fixture.source, ".gpg-id", "REMOTE\n", "Remote");
                sys_sync(&fixture.source, false, strategy);
                commit_file(&fixture.clone, ".gpg-id", "LOCAL\n", "Local");
                let before = head(&fixture.clone);
                let result = sys_sync(&fixture.clone, false, strategy);
                let conflict = result.conflict.expect("conflict");
                assert_eq!(conflict.paths, vec![".gpg-id".to_string()]);
                assert!(conflict.backup_branch.is_some());
                assert_eq!(result.summary.operation, GitStatusOperationDto::None);
                assert_eq!(head(&fixture.clone), before);
            }
        }

        #[test]
        fn desktop_pending_edit_is_committed_and_pushed() {
            let fixture = sys_fixture();
            write(&fixture.clone, "entry.gpg", "A & B");
            let result = sys::sync(&fixture.clone, None, "Edit A & B", true, GitIntegrationStrategyDto::Rebase).unwrap();
            assert!(result.committed);
            assert!(result.pushed);
            assert_eq!(remote_head(&fixture), head(&fixture.clone));
            let log = sys::log(&fixture.clone, 5).unwrap();
            assert_eq!(log[0].summary, "Edit A & B");
            assert_eq!(log.len(), 2);
        }

        #[test]
        fn desktop_blocks_dirty_divergence_and_resets_with_backup() {
            let fixture = sys_fixture();
            commit_file(&fixture.source, "remote.gpg", "remote", "Remote");
            sys_sync(&fixture.source, false, GitIntegrationStrategyDto::Rebase);
            commit_file(&fixture.clone, "local.gpg", "local", "Local");
            write(&fixture.clone, "pending.gpg", "pending");
            let result = sys_sync(&fixture.clone, false, GitIntegrationStrategyDto::Rebase);
            assert!(result.blocked_by_changes);

            let reset = sys::reset(&fixture.clone, None, "Before reset").unwrap();
            assert!(reset.committed);
            assert!(reset.backup_branch.is_some());
            assert_eq!(head(&fixture.clone), remote_head(&fixture));
        }

        #[test]
        fn desktop_identity_and_branches() {
            let fixture = sys_fixture();
            sys::set_identity(&fixture.clone, "Ada Lovelace", "ada@example.invalid").unwrap();
            let identity = sys::identity(&fixture.clone).unwrap().unwrap();
            assert_eq!(identity.name, "Ada Lovelace");
            assert!(identity.local);

            let (remote, current, branches) = sys::remote_branches(&fixture.clone).unwrap();
            assert_eq!(remote.as_deref(), Some("origin"));
            assert!(current.is_some());
            assert_eq!(branches.len(), 1);
        }
    }
}
