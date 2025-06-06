use anyhow::{Error, Result};
use pars_core::config::cli::ParsConfig;
use pars_core::operation::git::git_io;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_git(
    config: &ParsConfig,
    base_dir: Option<&str>,
    args: &[String],
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    git_io(
        &config.executable_config.git_executable,
        &root,
        &args.iter().map(|s| s.as_str()).collect::<Vec<&str>>(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;
    Ok(())
}
