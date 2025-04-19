use std::fs;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

use anyhow::Result;
use log::debug;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_util::{
    backup_encrypted_file, get_dir_gpg_id_content, path_to_str, process_files_recursively,
};
use crate::{IOErr, IOErrType};

const FPR_FILENAME: &str = ".gpg-id";

pub struct InitConfig {
    pub pgp_executable: String,
    pub keys_fpr: Vec<String>,
}

pub fn init(config: &InitConfig, root_path: &PathBuf, target_path: &str) -> Result<()> {
    if !root_path.exists() {
        fs::create_dir_all(root_path)?;
    }

    let target_path = root_path.join(target_path);
    if !target_path.exists() {
        fs::create_dir_all(&target_path)?;
    }

    let gpg_id_path = target_path.join(FPR_FILENAME);

    let mut new_fprs = config.keys_fpr.clone();
    let first_init = !root_path.join(".gpg-id").exists();
    if !gpg_id_path.exists() {
        let mut file =
            OpenOptions::new().write(true).create(true).truncate(false).open(&gpg_id_path)?;
        let content = new_fprs.iter().enumerate().fold(String::new(), |mut acc, (i, line)| {
            if i == new_fprs.len() - 1 {
                acc.push_str(line);
            } else {
                acc.push_str(line);
                acc.push('\n');
            }
            acc
        });
        write!(&mut file, "{}", content)?;
    }

    if first_init {
        return Ok(());
    }

    // Try to read old fingerprints from the directory
    let mut old_fprs = get_dir_gpg_id_content(root_path, &target_path)?;
    old_fprs.sort();
    let cmp_old: Vec<&str> = old_fprs.iter().map(|str| str.as_str()).collect();
    new_fprs.sort();

    let cmp_new: Vec<&str> = new_fprs.iter().map(|s| s.as_str()).collect();
    if cmp_old == cmp_new {
        println!("New fingerprints are the same as the old ones, no need to update.");
        return Ok(());
    }

    debug!("Old fpr <{:?}>, replace with <{:?}>", old_fprs, new_fprs);

    // Create old client using old fingerprints
    let old_client = PGPClient::new(&config.pgp_executable, &cmp_old)?;

    // Create new client using new fingerprints
    let new_client = PGPClient::new(&config.pgp_executable, &cmp_new)?;

    process_files_recursively(&target_path, &|entry| {
        let filename = entry.file_name();
        let filepath = entry.path();
        if !filepath.is_file() {
            return Err(IOErr::new(IOErrType::ExpectFile, &filepath).into());
        }
        if filename != FPR_FILENAME {
            let content = old_client.decrypt_stdin(root_path, path_to_str(&filepath)?)?;
            let backup_path = backup_encrypted_file(&filepath)?;
            new_client.encrypt(content.expose_secret(), path_to_str(&filepath)?)?;
            fs::remove_file(backup_path)?;
            return Ok(());
        }
        Ok(())
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {

    #[test]
    fn init_empty_repo() {
        // unimplemented!("fuck me")
    }
}
