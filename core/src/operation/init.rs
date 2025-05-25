use std::fs;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::Path;

use anyhow::{anyhow, Result};
use log::debug;
use secrecy::ExposeSecret;
use walkdir::WalkDir;

use crate::constants::default_constants::FPR_FILENAME;
use crate::pgp::PGPClient;
use crate::util::fs_util::{
    backup_encrypted_file, get_dir_gpg_id_content, path_attack_check, path_to_str,
};

pub struct InitConfig {
    pub pgp_executable: String,
    pub keys_fpr: Vec<String>,
}

fn write_new_fpr_file(path: &Path, fprs: &[impl AsRef<str>]) -> Result<()> {
    let mut file = OpenOptions::new().write(true).create(true).truncate(true).open(path)?;
    let content = fprs.iter().enumerate().fold(String::new(), |mut acc, (i, line)| {
        if i == fprs.len() - 1 {
            acc.push_str(line.as_ref());
        } else {
            acc.push_str(line.as_ref());
            acc.push('\n');
        }
        acc
    });
    write!(&mut file, "{content}")?;
    Ok(())
}

pub fn init(config: &InitConfig, root: &Path, target_path: Option<&str>) -> Result<()> {
    let target = root.join(target_path.unwrap_or_default());
    path_attack_check(root, &target)?;

    let first_init = !root.join(".gpg-id").exists();
    if first_init && target_path.is_some() {
        return  Err(anyhow!(
            "The repository {:?} has not been initialized yet. you can not specificy a subdirectory",
            path_to_str(root)?
        ));
    }

    if !root.exists() {
        println!("Creating directory '{}'", path_to_str(root)?);
        fs::create_dir_all(root)?;
    }

    if first_init {
        let gpg_id_path = root.join(FPR_FILENAME);
        write_new_fpr_file(&gpg_id_path, &config.keys_fpr)?;
        return Ok(());
    }

    if !target.exists() {
        println!("Creating directory '{}'", path_to_str(root)?);
        fs::create_dir_all(&target)?;
    }

    // Try to read old fingerprints from the directory
    let mut old_fprs = get_dir_gpg_id_content(root, &target)?;
    old_fprs.sort();
    let mut new_fprs = config.keys_fpr.clone();
    new_fprs.sort();

    if old_fprs == new_fprs {
        println!("New fingerprints are the same as the old ones, no need to update.");
        return Ok(());
    }

    debug!("Old fpr <{old_fprs:?}>, replace with <{new_fprs:?}>");

    // Create old client using old fingerprints
    let old_client = PGPClient::new(&config.pgp_executable, &old_fprs)?;

    // Create new client using new fingerprints
    let new_client = PGPClient::new(&config.pgp_executable, &new_fprs)?;

    for entry in WalkDir::new(&target) {
        let entry = entry?;
        if !entry.file_type().is_file() {
            continue;
        }

        let filepath = entry.path();
        let filename = filepath.file_name();

        if let Some(filename) = filename {
            if filename != FPR_FILENAME {
                let content: secrecy::SecretBox<str> =
                    old_client.decrypt_stdin(root, path_to_str(filepath)?)?;
                let backup_path = backup_encrypted_file(filepath)?;
                new_client.encrypt(content.expose_secret(), path_to_str(filepath)?)?;
                fs::remove_file(backup_path)?;
            }
        }
    }

    write_new_fpr_file(&target.join(FPR_FILENAME), &config.keys_fpr)?;

    Ok(())
}

#[cfg(test)]
mod tests {

    #[test]
    fn init_empty_repo() {
        // unimplemented!("fuck me")
    }
}
