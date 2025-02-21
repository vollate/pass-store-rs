use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_find(
    config: &ParsConfig,
    base_dir: Option<&str>,
    names: &Vec<String>,
) -> Result<(), (i32, Box<dyn Error>)> {
    // TODO: Implement finding password entries matching the given names.
    unimplemented!();
}
