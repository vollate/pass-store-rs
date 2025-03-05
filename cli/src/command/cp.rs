use std::io::BufReader;

use anyhow::{Error, Result};
use pars_core::config::ParsConfig;
use pars_core::operation::copy_or_rename::copy_rename_io;

use crate::constants::{ParsExitCode, SECRET_POSTFIX};
use crate::util::unwrap_root_path;

pub fn cmd_cp(
    config: &ParsConfig,
    base_dir: Option<&str>,
    force: bool,
    old_path: &str,
    new_path: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    let mut stdin = BufReader::new(std::io::stdin());
    let mut stdout = std::io::stdout();
    let mut stderr = std::io::stderr();

    if let Err(e) = copy_rename_io(
        true,
        &root,
        old_path,
        new_path,
        SECRET_POSTFIX,
        force,
        &mut stdin,
        &mut stdout,
        &mut stderr,
    ) {
        return Err((ParsExitCode::Error.into(), e));
    }

    Ok(())
}
