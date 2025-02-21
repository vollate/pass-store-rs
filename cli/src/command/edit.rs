use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_edit(
    config: &ParsConfig,
    base_dir: Option<&str>,
    pass_name: &str,
) -> Result<(), (i32, Box<dyn Error>)> {
    // TODO: Implement editing of an existing password using the default text editor.
    unimplemented!();
}
