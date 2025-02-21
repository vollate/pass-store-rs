use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_git(
    config: &ParsConfig,
    base_dir: Option<&str>,
    args: &Vec<String>,
) -> Result<(), (i32, Box<dyn Error>)> {
    // TODO: Implement forwarding git commands to the password store's git repository.
    unimplemented!();
}
