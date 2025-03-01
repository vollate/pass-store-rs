use std::error::Error;

use pars_core::config::ParsConfig;
use pars_core::operation::show::show;

use crate::util::unwrap_root_path;

pub fn cmd_show(
    config: &ParsConfig,
    base_dir: Option<&str>,
    clip: Option<usize>,
    qrcode: Option<usize>,
    pass_name: &str,
) -> Result<(), (i32, Box<dyn Error>)> {
    let root = unwrap_root_path(base_dir, config);
    Ok(())
}
