use std::error::Error;

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
) -> Result<(), (i32, Box<dyn Error>)> {
    let root = unwrap_root_path(base_dir, config);
    let mut stdin = std::io::stdin().lock();
    let mut stdout = std::io::stdout().lock();
    let mut stderr = std::io::stderr().lock();

    remove_io(&root, pass_name, recursive, force, &mut stdin, &mut stdout, &mut stderr)
        .map_err(|e| (ParsExitCode::Error.into(), e))?;
    Ok(())
}
