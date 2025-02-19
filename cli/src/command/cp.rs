use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_cp(
    config: &ParsConfig,
    base_dir: Option<String>,
    force: bool,
    old_path: &str,
    new_path: &str,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement copying of a password or directory.
    unimplemented!();
}
