use std::error::Error;
use std::fs;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

use log::debug;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_util::{backup_encrypted_file, path_to_str, process_files_recursively};
use crate::{IOErr, IOErrType};

const FPR_FILENAME: &str = ".gpg-id";

pub fn init(
    client: &PGPClient,
    root_path: &PathBuf,
    target_path: &str,
) -> Result<(), Box<dyn Error>> {
    if !root_path.exists() {
        fs::create_dir_all(root_path)?;
    }
    let new_fprs = client.get_key_fprs();

    let target_path = root_path.join(target_path);
    if !target_path.exists() {
        fs::create_dir_all(&target_path)?;
    }

    let gpg_id_path = target_path.join(FPR_FILENAME);
    if !gpg_id_path.exists() {
        let file = OpenOptions::new().write(true).create(true).open(&gpg_id_path)?;
        let content = new_fprs.iter().enumerate().fold(String::new(), |mut acc, (i, line)| {
            if i == new_fprs.len() - 1 {
                acc.push_str(line);
            } else {
                acc.push_str(line);
                acc.push('\n');
            }
            acc
        });
        write!(&file, "{}", content)?;
        return Ok(());
    }

    let old_id_content = fs::read_to_string(&gpg_id_path)?;
    let old_fprs: Vec<&str> = old_id_content
        .split('\n')
        .map(|line| line.trim())
        .filter(|line| !line.is_empty())
        .collect();

    if old_fprs == new_fprs {
        println!("New fingrainters are the same as the old one, no need to update.");
        return Ok(());
    }

    debug!("Old fpr <{:?}>, replace with <{:?}>", old_fprs, new_fprs);
    process_files_recursively(&target_path, &|entry| {
        let filename = entry.file_name();
        let filepath = entry.path();
        if !filepath.is_file() {
            return Err(IOErr::new(IOErrType::ExpectFile, &filepath).into());
        }
        if filename != FPR_FILENAME {
            let content = client.decrypt_stdin(root_path, path_to_str(&filepath)?)?;
            let backup_path = backup_encrypted_file(&filepath)?;
            client.encrypt(content.expose_secret(), path_to_str(&filepath)?)?;
            fs::remove_file(backup_path)?;
            return Ok(());
        }
        Ok(())
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {}
