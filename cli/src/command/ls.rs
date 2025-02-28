use std::error::Error;

use pars_core::config::ParsConfig;
use pars_core::operation::ls::ls_io;
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;
use pars_core::util::tree::{FilterType, TreeConfig};

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_ls(
    config: &ParsConfig,
    base_dir: Option<&str>,
    subfolder: Option<&str>,
) -> Result<(), (i32, Box<dyn Error>)> {
    let root = unwrap_root_path(base_dir, config);
    let target_path = root.join(subfolder.unwrap_or_default());
    let tree_cfg = TreeConfig {
        root: &root,
        target: subfolder.unwrap_or_default(),
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    let key_fprs = get_dir_gpg_id_content(&root, &target_path)
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let pgp_client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &key_fprs.iter().map(|s| s.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    let res = ls_io(&pgp_client, &tree_cfg, &config.print_config.clone().into())
        .map_err(|e| (ParsExitCode::Error.into(), e))?;

    println!("{}", res);
    Ok(())
}
