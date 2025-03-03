use anyhow::Error;
use pars_core::config::ParsConfig;
use pars_core::operation::insert::{insert_io, PasswdInsertConfig};
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_insert(
    config: &ParsConfig,
    base_dir: Option<&str>,
    pass_name: &str,
    echo: bool,
    multiline: bool,
    force: bool,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let target_pass = root.join(pass_name);
    let pgp_id = get_dir_gpg_id_content(&root, &target_pass)
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let pgp_client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &pgp_id.iter().map(|id| id.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let insert_cfg = PasswdInsertConfig { echo, multiline, force };
    let mut stdin = std::io::stdin().lock();
    let mut stdout = std::io::stdout().lock();
    let mut stderr = std::io::stderr().lock();

    insert_io(&pgp_client, &root, pass_name, &insert_cfg, &mut stdin, &mut stdout, &mut stderr)
        .map_err(|e| (ParsExitCode::Error.into(), e))?;
    Ok(())
}
