use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_ls(
    config: &ParsConfig,
    base_dir: Option<&str>,
    subfolder: Option<&str>,
) -> Result<(), (i32, Box<dyn Error>)> {
    // TODO: Implement listing password entries in the specified subfolder.
    unimplemented!();
}
