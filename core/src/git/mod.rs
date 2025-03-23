pub mod commit;

use std::path::Path;

use anyhow::Result;

use crate::operation::git::git_io;

pub fn init_repo(git_exe: &str, repo_base: &Path) -> Result<()> {
    git_io(git_exe, repo_base, &["init"])
}

pub fn add_and_commit(git_exe: &str, repo_base: &Path, commit_msg: &str) -> Result<()> {
    git_io(git_exe, repo_base, &["add", "-A"])?;
    git_io(git_exe, repo_base, &["commit", "-m", commit_msg])
}
