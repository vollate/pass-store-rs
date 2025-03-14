use anyhow::{Error, Result};
use pars_core::config::ParsConfig;
use pars_core::operation::grep::{grep, GrepPrintConfig};
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_grep(
    config: &ParsConfig,
    base_dir: Option<&str>,
    search_string: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let key_fprs =
        get_dir_gpg_id_content(&root, &root).map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let pgp_client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &key_fprs.iter().map(|s| s.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    let res = grep(
        &pgp_client,
        &root,
        search_string,
        &Into::<GrepPrintConfig>::into(&config.print_config),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?;
    res.iter().for_each(|s| println!("{}", s));
    Ok(())
}
