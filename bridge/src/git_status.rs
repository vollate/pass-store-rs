//! Typed Git status summary shared by mobile (libgit2) and desktop (porcelain v2).
// The porcelain parser only runs on desktop, but tests cover it on every host.
#![cfg_attr(any(target_os = "android", target_os = "ios"), allow(dead_code))]

use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use git2::{BranchType, Repository, RepositoryState, Status, StatusOptions};

use crate::api::{BridgeFailure, GitStatusOperationDto, GitStatusSummaryDto};

pub fn summarize_repository(root: &Path) -> Result<GitStatusSummaryDto, BridgeFailure> {
    let repo = Repository::open(root).map_err(crate::api::git_failure)?;
    let operation = operation_from_state(repo.state());
    let last_fetched_at = last_fetched_at(root);

    let head = repo.head().ok();
    let branch = head.as_ref().and_then(|reference| {
        if reference.is_branch() {
            reference.shorthand().map(str::to_string)
        } else {
            None
        }
    });

    let mut upstream = None;
    let mut ahead = 0_u32;
    let mut behind = 0_u32;
    if let Some(branch_name) = branch.as_deref() {
        if let Ok(local_branch) = repo.find_branch(branch_name, BranchType::Local) {
            if let Ok(upstream_branch) = local_branch.upstream() {
                upstream = upstream_branch
                    .name()
                    .ok()
                    .flatten()
                    .map(|name| name.trim_start_matches("refs/remotes/").to_string());
                if let (Some(local_oid), Some(upstream_oid)) =
                    (local_branch.get().target(), upstream_branch.get().target())
                {
                    let (a, b) = repo
                        .graph_ahead_behind(local_oid, upstream_oid)
                        .map_err(crate::api::git_failure)?;
                    ahead = u32::try_from(a).unwrap_or(u32::MAX);
                    behind = u32::try_from(b).unwrap_or(u32::MAX);
                }
            }
        }
    }

    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .renames_head_to_index(true)
        .include_unmodified(false);
    let statuses = repo.statuses(Some(&mut options)).map_err(crate::api::git_failure)?;
    let mut changed = 0_u32;
    let mut conflicted = 0_u32;
    for entry in statuses.iter() {
        let status = entry.status();
        if status.is_conflicted() {
            conflicted = conflicted.saturating_add(1);
        } else if !status.is_empty() && status != Status::CURRENT {
            changed = changed.saturating_add(1);
        }
    }

    Ok(GitStatusSummaryDto {
        branch,
        upstream,
        ahead,
        behind,
        changed,
        conflicted,
        operation,
        last_fetched_at,
    })
}

pub fn parse_porcelain_v2(stdout: &[u8], git_dir: &Path) -> Result<GitStatusSummaryDto, BridgeFailure> {
    let mut branch = None;
    let mut upstream = None;
    let mut ahead = 0_u32;
    let mut behind = 0_u32;
    let mut changed = 0_u32;
    let mut conflicted = 0_u32;

    for record in stdout.split(|&byte| byte == 0) {
        if record.is_empty() {
            continue;
        }
        let line = String::from_utf8_lossy(record);
        if let Some(rest) = line.strip_prefix("# branch.head ") {
            if rest != "(detached)" {
                branch = Some(rest.to_string());
            }
            continue;
        }
        if let Some(rest) = line.strip_prefix("# branch.upstream ") {
            upstream = Some(rest.to_string());
            continue;
        }
        if let Some(rest) = line.strip_prefix("# branch.ab ") {
            // Format: +<ahead> -<behind>
            let mut parts = rest.split_whitespace();
            if let Some(ahead_token) = parts.next() {
                ahead = parse_signed_count(ahead_token.trim_start_matches('+'));
            }
            if let Some(behind_token) = parts.next() {
                behind = parse_signed_count(behind_token.trim_start_matches('-'));
            }
            continue;
        }
        if line.starts_with('#') {
            continue;
        }
        match line.as_bytes().first() {
            Some(b'u') => conflicted = conflicted.saturating_add(1),
            Some(b'1' | b'2' | b'?') => changed = changed.saturating_add(1),
            _ => {}
        }
    }

    Ok(GitStatusSummaryDto {
        branch,
        upstream,
        ahead,
        behind,
        changed,
        conflicted,
        operation: operation_from_git_dir(git_dir),
        last_fetched_at: last_fetched_at_from_git_dir(git_dir),
    })
}

fn parse_signed_count(value: &str) -> u32 {
    value.parse::<i64>().ok().map(|n| n.unsigned_abs() as u32).unwrap_or(0)
}

fn operation_from_state(state: RepositoryState) -> GitStatusOperationDto {
    match state {
        RepositoryState::Clean => GitStatusOperationDto::None,
        RepositoryState::Merge => GitStatusOperationDto::Merging,
        RepositoryState::Rebase
        | RepositoryState::RebaseInteractive
        | RepositoryState::RebaseMerge => GitStatusOperationDto::Rebasing,
        _ => GitStatusOperationDto::Other,
    }
}

fn operation_from_git_dir(git_dir: &Path) -> GitStatusOperationDto {
    if git_dir.join("rebase-merge").is_dir() || git_dir.join("rebase-apply").is_dir() {
        GitStatusOperationDto::Rebasing
    } else if git_dir.join("MERGE_HEAD").is_file() {
        GitStatusOperationDto::Merging
    } else if git_dir.join("CHERRY_PICK_HEAD").is_file()
        || git_dir.join("REVERT_HEAD").is_file()
        || git_dir.join("BISECT_LOG").is_file()
    {
        GitStatusOperationDto::Other
    } else {
        GitStatusOperationDto::None
    }
}

fn last_fetched_at(root: &Path) -> Option<i64> {
    let git_dir = root.join(".git");
    if git_dir.is_file() {
        // gitfile pointing at a real git dir — open via libgit2 path is preferred;
        // for FETCH_HEAD fall back to reading through Repository.
        if let Ok(repo) = Repository::open(root) {
            return last_fetched_at_from_git_dir(repo.path());
        }
    }
    last_fetched_at_from_git_dir(&git_dir)
}

fn last_fetched_at_from_git_dir(git_dir: &Path) -> Option<i64> {
    let metadata = fs::metadata(git_dir.join("FETCH_HEAD")).ok()?;
    let modified = metadata.modified().ok()?;
    Some(
        modified
            .duration_since(UNIX_EPOCH)
            .ok()
            .or_else(|| SystemTime::now().duration_since(UNIX_EPOCH).ok())?
            .as_secs() as i64,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use git2::{IndexAddOption, Signature};
    use std::fs;
    use tempfile::tempdir;

    fn init_repo(root: &Path) -> Repository {
        let repo = Repository::init(root).expect("init");
        let mut config = repo.config().expect("config");
        config.set_str("user.name", "Pars Test").unwrap();
        config.set_str("user.email", "pars@example.invalid").unwrap();
        repo
    }

    fn commit_all(repo: &Repository, message: &str) {
        let mut index = repo.index().unwrap();
        index.add_all(["*"].iter(), IndexAddOption::DEFAULT, None).unwrap();
        index.write().unwrap();
        let tree_oid = index.write_tree().unwrap();
        let tree = repo.find_tree(tree_oid).unwrap();
        let signature = Signature::now("Pars Test", "pars@example.invalid").unwrap();
        let parent = repo
            .head()
            .ok()
            .and_then(|head| head.target())
            .and_then(|oid| repo.find_commit(oid).ok());
        match parent.as_ref() {
            Some(parent) => {
                repo.commit(Some("HEAD"), &signature, &signature, message, &tree, &[parent])
                    .unwrap();
            }
            None => {
                repo.commit(Some("HEAD"), &signature, &signature, message, &tree, &[])
                    .unwrap();
            }
        }
    }

    #[test]
    fn clean_repository_summary() {
        let temp = tempdir().unwrap();
        let root = temp.path().join("store");
        fs::create_dir_all(&root).unwrap();
        let repo = init_repo(&root);
        fs::write(root.join(".gpg-id"), "ABC\n").unwrap();
        commit_all(&repo, "Initial");

        let summary = summarize_repository(&root).unwrap();
        assert!(summary.branch.is_some());
        assert_eq!(summary.upstream, None);
        assert_eq!(summary.ahead, 0);
        assert_eq!(summary.behind, 0);
        assert_eq!(summary.changed, 0);
        assert_eq!(summary.conflicted, 0);
        assert!(matches!(summary.operation, GitStatusOperationDto::None));
    }

    #[test]
    fn dirty_repository_counts_changed() {
        let temp = tempdir().unwrap();
        let root = temp.path().join("store");
        fs::create_dir_all(&root).unwrap();
        let repo = init_repo(&root);
        fs::write(root.join(".gpg-id"), "ABC\n").unwrap();
        commit_all(&repo, "Initial");
        fs::write(root.join("entry.gpg"), b"ciphertext").unwrap();

        let summary = summarize_repository(&root).unwrap();
        assert_eq!(summary.changed, 1);
        assert_eq!(summary.conflicted, 0);
    }

    #[test]
    fn unborn_repository_has_no_branch_commit() {
        let temp = tempdir().unwrap();
        let root = temp.path().join("store");
        fs::create_dir_all(&root).unwrap();
        init_repo(&root);

        let summary = summarize_repository(&root).unwrap();
        // Unborn HEAD may still report the default branch name depending on template;
        // there are zero commits and no changes.
        assert_eq!(summary.changed, 0);
        assert_eq!(summary.ahead, 0);
        assert_eq!(summary.behind, 0);
    }

    #[test]
    fn ahead_behind_and_diverged_against_upstream() {
        let temp = tempdir().unwrap();
        let bare_path = temp.path().join("remote.git");
        Repository::init_bare(&bare_path).unwrap();

        let source = temp.path().join("source");
        fs::create_dir_all(&source).unwrap();
        let source_repo = init_repo(&source);
        fs::write(source.join(".gpg-id"), "ABC\n").unwrap();
        commit_all(&source_repo, "Initial");
        let branch_name = source_repo.head().unwrap().shorthand().unwrap().to_string();
        let head_ref = format!("refs/heads/{branch_name}");
        source_repo.remote("origin", bare_path.to_str().unwrap()).unwrap();
        {
            let mut remote = source_repo.find_remote("origin").unwrap();
            remote
                .push(&[format!("{head_ref}:{head_ref}")], None)
                .unwrap();
        }
        let mut config = source_repo.config().unwrap();
        config.set_str(&format!("branch.{branch_name}.remote"), "origin").unwrap();
        config.set_str(&format!("branch.{branch_name}.merge"), &head_ref).unwrap();

        let clone_path = temp.path().join("clone");
        let clone = Repository::clone(bare_path.to_str().unwrap(), &clone_path).unwrap();
        let clone_branch = clone.head().unwrap().shorthand().unwrap().to_string();
        let mut clone_config = clone.config().unwrap();
        clone_config.set_str(&format!("branch.{clone_branch}.remote"), "origin").unwrap();
        clone_config
            .set_str(&format!("branch.{clone_branch}.merge"), &head_ref)
            .unwrap();

        fs::write(source.join("a.gpg"), b"a").unwrap();
        commit_all(&source_repo, "Ahead");
        {
            let mut remote = source_repo.find_remote("origin").unwrap();
            remote
                .push(&[format!("{head_ref}:{head_ref}")], None)
                .unwrap();
        }

        fs::write(clone_path.join("b.gpg"), b"b").unwrap();
        commit_all(&clone, "Local only");

        // Clone is ahead 1 (local) and behind 1 (remote) after fetch.
        {
            let mut remote = clone.find_remote("origin").unwrap();
            remote.fetch(&[&branch_name], None, None).unwrap();
        }
        let summary = summarize_repository(&clone_path).unwrap();
        assert_eq!(summary.ahead, 1);
        assert_eq!(summary.behind, 1);
        assert_eq!(summary.changed, 0);
        assert!(summary.upstream.as_deref().is_some_and(|u| u.contains(&branch_name)));
    }

    #[test]
    fn porcelain_v2_parser_reads_branch_ab_and_entries() {
        let temp = tempdir().unwrap();
        let git_dir = temp.path().join(".git");
        fs::create_dir_all(&git_dir).unwrap();
        let stdout = b"# branch.head main\0# branch.upstream origin/main\0# branch.ab +1 -2\0\
1 .M N... 100644 100644 100644 0000000000000000000000000000000000000000 1111111111111111111111111111111111111111 entry.gpg\0\
? untracked.gpg\0\
u UU N... 100644 100644 100644 100644 0000000000000000000000000000000000000000 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 conflict.gpg\0";
        let summary = parse_porcelain_v2(stdout, &git_dir).unwrap();
        assert_eq!(summary.branch.as_deref(), Some("main"));
        assert_eq!(summary.upstream.as_deref(), Some("origin/main"));
        assert_eq!(summary.ahead, 1);
        assert_eq!(summary.behind, 2);
        assert_eq!(summary.changed, 2);
        assert_eq!(summary.conflicted, 1);
        assert!(matches!(summary.operation, GitStatusOperationDto::None));
    }

    #[test]
    fn porcelain_v2_detects_rebase_from_git_dir() {
        let temp = tempdir().unwrap();
        let git_dir = temp.path().join(".git");
        fs::create_dir_all(git_dir.join("rebase-merge")).unwrap();
        let summary = parse_porcelain_v2(b"# branch.head main\0", &git_dir).unwrap();
        assert!(matches!(summary.operation, GitStatusOperationDto::Rebasing));
    }

    #[test]
    fn porcelain_v2_detects_merge_from_git_dir() {
        let temp = tempdir().unwrap();
        let git_dir = temp.path().join(".git");
        fs::create_dir_all(&git_dir).unwrap();
        fs::write(git_dir.join("MERGE_HEAD"), "abc\n").unwrap();
        let summary = parse_porcelain_v2(b"# branch.head main\0", &git_dir).unwrap();
        assert!(matches!(summary.operation, GitStatusOperationDto::Merging));
    }

    #[test]
    fn porcelain_v2_detached_head_omits_branch() {
        let temp = tempdir().unwrap();
        let git_dir = temp.path().join(".git");
        fs::create_dir_all(&git_dir).unwrap();
        let summary = parse_porcelain_v2(b"# branch.head (detached)\0", &git_dir).unwrap();
        assert_eq!(summary.branch, None);
    }
}
