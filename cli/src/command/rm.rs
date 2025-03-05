use std::io::BufReader;

use anyhow::{Error, Result};
use pars_core::config::ParsConfig;
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
    let mut stdin = BufReader::new(std::io::stdin());
    let mut stdout = std::io::stdout();
    let mut stderr = std::io::stderr();

    remove_io(&root, pass_name, recursive, force, &mut stdin, &mut stdout, &mut stderr)
        .map_err(|e| (ParsExitCode::Error.into(), e))?;
    Ok(())
}
