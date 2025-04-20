use std::env;

use anyhow::Error;
use pars_core::config::cli::ParsConfig;
use pars_core::git::{add_and_commit, commit};
use pars_core::operation::edit::edit;

use crate::constants::{ParsExitCode, SECRET_EXTENSION};
use crate::util::unwrap_root_path;

pub fn cmd_edit(
    config: &ParsConfig,
    base_dir: Option<&str>,
    target_pass: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let editor =
        env::var("PARS_EDITOR").unwrap_or(config.executable_config.editor_executable.clone());

    let need_commit = edit(
        &root,
        target_pass,
        SECRET_EXTENSION,
        &editor,
        &config.executable_config.pgp_executable,
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    if need_commit {
        let commit =
            commit::GitCommit::new(&root, commit::CommitType::Update(target_pass.to_string()));
        add_and_commit(
            &config.executable_config.git_executable,
            &root,
            commit.get_commit_msg().as_str(),
        )
        .map_err(|e| (ParsExitCode::GitError.into(), e))?;
    }

    Ok(())
}
