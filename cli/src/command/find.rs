use anyhow::{Error, Result};
use pars_core::config::ParsConfig;
use pars_core::operation::find::find_term;
use pars_core::util::tree::{FilterType, TreeConfig};

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_find(
    config: &ParsConfig,
    base_dir: Option<&str>,
    names: &[String],
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let terms = names.iter().map(|s| s.as_str()).collect();
    let tree_cfg = TreeConfig {
        root: &root,
        target: "",
        filter_type: FilterType::Include,
        filters: Vec::new(),
    };
    let res = find_term(&terms, &tree_cfg, &config.print_config.clone().into())
        .map_err(|e| (ParsExitCode::Error.into(), e))?;
    println!("{}", res);
    Ok(())
}
