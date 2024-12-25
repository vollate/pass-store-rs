use std::any::Any;
use std::error::Error;
use std::path::PathBuf;

use regex::Regex;
use secrecy::ExposeSecret;

use crate::gpg::GPGClient;
use crate::util::tree::tree_with_filter;
use crate::IOErr;

pub fn ls_interact(
    client: &GPGClient,
    root_path: &PathBuf,
    enable_colored: bool,
    target_path: &str,
) -> Result<String, Box<dyn Error>> {
    let mut full_path = root_path.join(target_path);
    loop {
        if full_path.is_dir() {
            return Ok(tree_with_filter(&full_path, &Vec::new(), 0, enable_colored)?);
        } else if full_path.is_file() {
            let data =
                client.decrypt_stdin(full_path.to_str().ok_or_else(|| IOErr::InvalidPath)?)?;
            return Ok(data.expose_secret().to_string());
        } else if full_path.is_symlink() {
            full_path = full_path.read_link()?;
        } else {
            return Err(IOErr::InvalidFileType.into());
        }
    }
}
