use std::io::BufReader;

use anyhow::{Error, Result};
use log::debug;
use pars_core::config::ParsConfig;
use pars_core::git::add_and_commit;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::operation::remove::remove_io;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_rm(
    config: &ParsConfig,
    base_dir: Option<&str>,
    recursive: bool,
    force: bool,
    pass_name: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    remove_io(
        &root,
        pass_name,
        recursive,
        force,
        &mut BufReader::new(std::io::stdin()),
        &mut std::io::stdout(),
        &mut std::io::stderr(),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?;

    let commit = GitCommit::new(&root, CommitType::Delete(pass_name.to_string()));
    debug!("cmd_rm: commit {}", commit);
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
