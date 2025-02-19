use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_rm(
    config: &ParsConfig,
    base_dir: Option<String>,
    recursive: bool,
    force: bool,
    pass_name: &str,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement removal of the specified password (or directory if recursive).
    unimplemented!();
}
