use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_mv(
    config: &ParsConfig,
    base_dir: Option<&str>,
    force: bool,
    old_path: &str,
    new_path: &str,
) -> Result<(), (i32, Box<dyn Error>)> {
    // TODO: Implement renaming of a password or directory.
    unimplemented!();
}
