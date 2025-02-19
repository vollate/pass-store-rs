use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_grep(
    config: &ParsConfig,
    base_dir: Option<String>,
    grep_options: &[String],
    search_string: &String,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement searching through decrypted password files using grep options.
    unimplemented!();
}
