use std::error::Error;

use pars_core::config::ParsConfig;
use pars_core::operation::init::init;
use pars_core::pgp::{PGPClient, PGPErr};
use pars_core::util::fs_util::path_to_str;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_init(
    config: &ParsConfig,
    base_dir: Option<&str>,
    path: Option<&str>,
    pgp_id: &str,
) -> Result<(), (i32, Box<dyn Error>)> {
    let root = unwrap_root_path(base_dir, config);
    //TODO(Vollate): support email+username
    let mut pgp_client =
        PGPClient::new(config.path_config.pgp_executable.clone(), Some(pgp_id.into()), None, None);

    if let Err(e) = pgp_client.update_info() {
        return Err((ParsExitCode::PGPError.into(), e));
    }

    println!(
        "Init password store for {} {} at '{}'",
        pgp_client
            .get_username()
            .ok_or((ParsExitCode::PGPError.into(), PGPErr::NoneUsername.into()))?,
        pgp_client.get_email().ok_or((ParsExitCode::PGPError.into(), PGPErr::NoneEmail.into()))?,
        path_to_str(&root).map_err(|e| (ParsExitCode::InvalidEncoding.into(), e))?,
    );

    if let Err(e) = init(&pgp_client, &root, path.unwrap_or_default()) {
        return Err((ParsExitCode::PGPError.into(), e));
    }

    Ok(())
}
