use std::io::BufReader;

use anyhow::{Error, Result};
use log::debug;
use pars_core::config::ParsConfig;
use pars_core::git::add_and_commit;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::operation::copy_or_rename::copy_rename_io;

use crate::constants::{ParsExitCode, SECRET_EXTENSION};
use crate::util::unwrap_root_path;

pub fn cmd_mv(
    config: &ParsConfig,
    base_dir: Option<&str>,
    force: bool,
    old_path: &str,
    new_path: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    copy_rename_io(
        false,
        &root,
        old_path,
        new_path,
        SECRET_EXTENSION,
        force,
        &mut BufReader::new(std::io::stdin()),
        &mut std::io::stdout(),
        &mut std::io::stderr(),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?;

    let commit =
        GitCommit::new(&root, CommitType::Rename((old_path.to_string(), new_path.to_string())));
    debug!("cmd_mv: commit {}", commit);
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
