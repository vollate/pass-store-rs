use std::io::BufReader;

use anyhow::{Error, Result};
use log::debug;
use pars_core::config::cli::ParsConfig;
use pars_core::git::add_and_commit;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::operation::copy_or_rename::{copy_rename_io, CopyRenameConfig};
use pars_core::operation::generate::IOStreams;

use crate::constants::{ParsExitCode, SECRET_EXTENSION};
use crate::util::unwrap_root_path;

pub fn cmd_cp(
    config: &ParsConfig,
    base_dir: Option<&str>,
    force: bool,
    old_path: &str,
    new_path: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    let copy_config =
        CopyRenameConfig { copy: true, force, file_extension: SECRET_EXTENSION.to_string() };

    let mut stdin = BufReader::new(std::io::stdin());
    let mut stdout = std::io::stdout();
    let mut stderr = std::io::stderr();
    let io_streams = IOStreams { in_s: &mut stdin, out_s: &mut stdout, err_s: &mut stderr };

    copy_rename_io(copy_config, &root, old_path, new_path, io_streams)
        .map_err(|e| (ParsExitCode::Error.into(), e))?;

    let commit =
        GitCommit::new(&root, CommitType::Copy((old_path.to_string(), new_path.to_string())));
    debug!("cmd_cp: commit {commit}");
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
