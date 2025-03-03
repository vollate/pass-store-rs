use anyhow::{Error, Result};
use pars_core::config::ParsConfig;

use crate::util::unwrap_root_path;

pub fn cmd_grep(
    config: &ParsConfig,
    base_dir: Option<&str>,
    grep_options: &[String],
    search_string: &String,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);

    Ok(())
}
