use std::error::Error;
use std::path::Path;

use regex::Regex;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_utils::path_to_str;
use crate::util::tree::{tree_with_filter, TreeColorConfig};
use crate::{IOErr, IOErrType};

pub fn ls_interact(
    client: &PGPClient,
    root_path: &Path,
    target_path: &str,
    ignore_list: &Vec<Regex>,
    color_config: Option<TreeColorConfig>,
) -> Result<String, Box<dyn Error>> {
    let mut full_path = root_path.join(target_path);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        Ok(tree_with_filter(&full_path, ignore_list, color_config.is_some())?)
    } else if full_path.is_file() {
        let data = client.decrypt_stdin(path_to_str(&full_path)?)?;
        return Ok(data.expose_secret().to_string());
    } else {
        return Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into());
    }
}

pub fn ls_dir(
    root_path: &Path,
    target_path: &Path,
    ignore_list: &Vec<Regex>,
    color_config: Option<TreeColorConfig>,
) -> Result<String, Box<dyn Error>> {
    let mut full_path = root_path.join(target_path);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        Ok(tree_with_filter(&full_path, ignore_list, color_config.is_some())?)
    } else {
        return Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into());
    }
}

#[cfg(test)]
mod tests {}
