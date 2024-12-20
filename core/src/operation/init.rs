use std::error::Error;
use std::path::PathBuf;

use crate::util::fs_utils::get_home_dir;

pub fn init(root_path: &PathBuf, new_path: &str, recipient: &str) -> Result<(), Box<dyn Error>> {
    if !root_path.exists() {
        std::fs::create_dir_all(root_path)?;
    }
    let new_full_path = root_path.join(new_path);
    if !new_full_path.exists() {
        std::fs::create_dir_all(&new_full_path)?;
        std::fs::write(new_full_path.join(".gpg-id"), recipient)?;
        return Ok(());
    }
    todo!("check .gpg-id file and ask for overwrite");
    Ok(())
}
