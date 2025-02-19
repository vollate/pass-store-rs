use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_ls(
    config: &ParsConfig,
    base_dir: Option<String>,
    subfolder: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement listing password entries in the specified subfolder.
    unimplemented!();
}
