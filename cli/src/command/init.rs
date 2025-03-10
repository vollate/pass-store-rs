use anyhow::{Error, Result};
use pars_core::config::ParsConfig;
use pars_core::operation::init::init;
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::path_to_str;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_init(
    config: &ParsConfig,
    base_dir: Option<&str>,
    path: Option<&str>,
    pgp_id: &[String],
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let pgp_client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &pgp_id.iter().map(|id| id.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    println!(
        "Init password store for {:?} {:?} at '{}'",
        pgp_client.get_usernames(),
        pgp_client.get_email(),
        path_to_str(&root).map_err(|e| (ParsExitCode::Error.into(), e))?,
    );

    init(&pgp_client, &root, path.unwrap_or_default())
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    eprintln!("TODO!!!: need to init git repository");
    Ok(())
}
