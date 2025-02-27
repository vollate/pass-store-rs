use std::error::Error;
use std::fs;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

use log::debug;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_util::{
    backup_encrypted_file, get_dir_gpg_id_content, path_to_str, process_files_recursively,
};
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

    let target_path = root_path.join(target_path);
    if !target_path.exists() {
        fs::create_dir_all(&target_path)?;
    }

    let gpg_id_path = target_path.join(FPR_FILENAME);

    let mut new_fprs = client.get_key_fprs();
    let first_init = !root_path.join(".gpg-id").exists();
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
    }

    if first_init {
        return Ok(());
    }

    let mut old_fprs = get_dir_gpg_id_content(root_path, &target_path)?;
    old_fprs.sort();
    let cmp_old: Vec<&str> = old_fprs.iter().map(|str| str.as_str()).collect();
    new_fprs.sort();
    if cmp_old == new_fprs {
        println!("New finger print are the same as the old one, no need to update.");
        return Ok(());
    }

    debug!("Old fpr <{:?}>, replace with <{:?}>", old_fprs, new_fprs);
    let old_client = PGPClient::new(client.get_executable(), &cmp_old)?;
    process_files_recursively(&target_path, &|entry| {
        let filename = entry.file_name();
        let filepath = entry.path();
        if !filepath.is_file() {
            return Err(IOErr::new(IOErrType::ExpectFile, &filepath).into());
        }
        if filename != FPR_FILENAME {
            let content = old_client.decrypt_stdin(root_path, path_to_str(&filepath)?)?;
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
mod tests {

    #[test]
    fn init_empty_repo() {
        unimplemented!("fuck me")
    }
}
