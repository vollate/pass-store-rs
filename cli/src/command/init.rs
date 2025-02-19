use std::error::Error;

use pars_core::config::ParsConfig;

pub fn cmd_init(
    config: &ParsConfig,
    base_dir: Option<String>,
    path: Option<&str>,
    gpg_ids: &Vec<String>,
) -> Result<(), Box<dyn Error>> {
    // TODO: Implement password store initialization using the provided GPG ids.
    unimplemented!();
}
