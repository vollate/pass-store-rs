use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_grep(
    config: &ParsConfig,
    base_dir: Option<&str>,
    grep_options: &[String],
    search_string: &String,
) -> Result<(), (i32, Box<dyn Error>)> {
    // TODO: Implement searching through decrypted password files using grep options.
    unimplemented!();
}
