use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_generate(
    config: &ParsConfig,
    base_dir: Option<String>,
    no_symbols: bool,
    clip: bool,
    in_place: bool,
    force: bool,
    pass_name: &str,
    pass_length: Option<u32>,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement generating a new password (with optional length and no-symbols)
    //       and insert it into the password store.
    unimplemented!();
}
