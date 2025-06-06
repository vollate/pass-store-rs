use std::io::BufReader;

use anyhow::Error;
use log::debug;
use pars_core::config::cli::ParsConfig;
use pars_core::git::add_and_commit;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::operation::insert::{insert_io, PasswdInsertConfig};

use crate::constants::{ParsExitCode, SECRET_EXTENSION};
use crate::util::unwrap_root_path;

pub fn cmd_insert(
    config: &ParsConfig,
    base_dir: Option<&str>,
    pass_name: &str,
    echo: bool,
    multiline: bool,
    force: bool,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    let insert_cfg = PasswdInsertConfig {
        echo,
        multiline,
        force,
        extension: SECRET_EXTENSION.to_string(),
        pgp_executable: config.executable_config.pgp_executable.clone(),
    };

    if !insert_io(
        &root,
        pass_name,
        &insert_cfg,
        &mut BufReader::new(std::io::stdin()),
        &mut std::io::stdout(),
        &mut std::io::stderr(),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?
    {
        // Failed to insert, cancel git commit
        return Ok(());
    }

    let commit = GitCommit::new(&root, CommitType::Insert(pass_name.to_string()));
    debug!("cmd_insert: commit {commit}");
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
