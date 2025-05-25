use anyhow::{Error, Result};
use log::debug;
use pars_core::config::cli::ParsConfig;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::git::{add_and_commit, init_repo};
use pars_core::operation::init::{init, InitConfig};
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::path_to_str;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_init(
    config: &ParsConfig,
    base_dir: Option<&str>,
    path: Option<&str>,
    pgp_ids: &[String],
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    // Create a temporary PGPClient just to get the user information for display purposes
    let pgp_client = PGPClient::new(config.executable_config.pgp_executable.clone(), pgp_ids)
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    println!(
        "Init password store for {:?} {:?} at '{}'",
        pgp_client.get_usernames(),
        pgp_client.get_email(),
        path_to_str(&root).map_err(|e| (ParsExitCode::Error.into(), e))?,
    );

    // Create InitConfig for the init function
    let init_config = InitConfig {
        pgp_executable: config.executable_config.pgp_executable.clone(),
        keys_fpr: pgp_ids.to_vec(),
    };

    init(&init_config, &root, path).map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    if !root.join(".git").exists() {
        init_repo(&config.executable_config.git_executable, &root)
            .map_err(|e| (ParsExitCode::GitError.into(), e))?;
    }

    let commit = GitCommit::new(
        &root,
        CommitType::Init(pgp_client.get_keys_fpr().iter().map(|f| f.to_string()).collect()),
    );
    debug!("cmd_init: commit {commit}");
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
