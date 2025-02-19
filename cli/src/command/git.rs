use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_git(
    config: &ParsConfig,
    base_dir: Option<String>,
    args: &Vec<String>,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement forwarding git commands to the password store's git repository.
    unimplemented!();
}
