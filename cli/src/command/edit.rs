use std::env;

use anyhow::Error;
use pars_core::config::ParsConfig;
use pars_core::git::{add_and_commit, commit};
use pars_core::operation::edit::edit;
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;

use crate::constants::{ParsExitCode, SECRET_EXTENSION};
use crate::util::unwrap_root_path;

pub fn cmd_edit(
    config: &ParsConfig,
    base_dir: Option<&str>,
    target_pass: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let target_path = root.join(format!("{}.{}", target_pass, SECRET_EXTENSION));
    let key_fprs = get_dir_gpg_id_content(&root, &target_path)
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &key_fprs.iter().map(|s| s.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let editor =
        env::var("PARS_EDITOR").unwrap_or(config.executable_config.editor_executable.clone());

    let need_commit = edit(&client, &root, target_pass, SECRET_EXTENSION, &editor)
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
