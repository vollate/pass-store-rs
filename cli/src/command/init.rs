use std::error::Error;

use pars_core::config::ParsConfig;
use pars_core::operation::init::init;
use pars_core::pgp::PGPClient;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_init(
    config: &ParsConfig,
    base_dir: Option<&str>,
    path: Option<&str>,
    pgp_id: &str,
) -> Result<(), (i32, Box<dyn Error>)> {
    let root = unwrap_root_path(base_dir, config);
    let mut pgp_client =
        PGPClient::new(config.path_config.pgp_executable.clone(), Some(pgp_id.into()), None, None);

    if let Err(e) = pgp_client.update_info() {
        return Err((ParsExitCode::PGPError.into(), e));
    }

    if let Err(e) = init(&pgp_client, &root, path.unwrap_or_default()) {
        return Err((ParsExitCode::PGPError.into(), e));
    }
    Ok(())
}
