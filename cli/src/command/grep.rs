use anyhow::{Error, Result};
use pars_core::config::ParsConfig;
use pars_core::operation::grep::{grep, GrepPrintConfig};

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_grep(
    config: &ParsConfig,
    base_dir: Option<&str>,
    search_string: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    // Pass the pgp_executable directly to the grep function
    // instead of creating a single PGPClient instance
    let res = grep(
        &config.executable_config.pgp_executable,
        &root,
        search_string,
        &Into::<GrepPrintConfig>::into(&config.print_config),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?;

    res.iter().for_each(|s| println!("{}", s));
    Ok(())
}
