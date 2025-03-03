use std::env;

use anyhow::Error;
use pars_core::config::ParsConfig;
use pars_core::operation::edit::edit;
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_edit(
    config: &ParsConfig,
    base_dir: Option<&str>,
    target_pass: &str,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let target_path = root.join(target_pass);
    let key_fprs = get_dir_gpg_id_content(&root, &target_path)
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &key_fprs.iter().map(|s| s.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let editor =
        env::var("PARS_EDITOR").unwrap_or(config.executable_config.editor_executable.clone());
    edit(&client, &root, target_pass, &editor).map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    eprintln!("GIT op!!!!");
    Ok(())
}
