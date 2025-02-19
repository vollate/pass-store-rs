use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_edit(
    config: &ParsConfig,
    base_dir: Option<String>,
    pass_name: &str,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement editing of an existing password using the default text editor.
    unimplemented!();
}
