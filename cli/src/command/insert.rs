use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_insert(
    config: &ParsConfig,

    base_dir: Option<String>,
    pass_name: &str,
    echo: bool,
    multiline: bool,
    force: bool,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement inserting a new password.
    //       Use echo or multiline input modes and handle the force flag.
    unimplemented!();
}
