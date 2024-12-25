use std::error::Error;
use std::fs;
use std::path::PathBuf;

use secrecy::ExposeSecret;

use crate::gpg::utils::{check_recipient_type, user_email_to_fingerprint, RecipientType};
use crate::gpg::GPGClient;
use crate::util::fs_utils::{backup_encrypted_file, process_files_recursively};
use crate::IOErr;

const FPR_FILENAME: &str = ".gpg-id";
pub fn init(
    client: &GPGClient,
    root_path: &PathBuf,
    target_path: &str,
    recipient: &str,
) -> Result<(), Box<dyn Error>> {
    if !root_path.exists() {
        fs::create_dir_all(root_path)?;
    }
    let fpr = {
        if RecipientType::Fingerprint != check_recipient_type(recipient)? {
            user_email_to_fingerprint(client.get_executable(), recipient)?
        } else {
            recipient.to_string()
        }
    };

    let target_path = root_path.join(target_path);
    if !target_path.exists() {
        fs::create_dir_all(&target_path)?;
    }
    let target_gpg_id = target_path.join(FPR_FILENAME);
    if !target_gpg_id.exists() {
        fs::write(target_gpg_id, fpr)?;
        return Ok(());
    }
    let old_fpr = fs::read_to_string(&target_path)?;
    if old_fpr == fpr {
        return Ok(());
    }

    process_files_recursively(&target_path, &|entry| {
        let filename = entry.file_name();
        let filepath = entry.path();
        if !filepath.is_file() {
            return Err(IOErr::ExpectFile.into());
        }
        if filename == FPR_FILENAME {
            let content =
                client.decrypt_stdin(filename.to_str().ok_or_else(|| IOErr::InvalidPath)?)?;
            let backup_path = backup_encrypted_file(&filepath)?;
            client.encrypt(
                content.expose_secret(),
                filepath.to_str().ok_or_else(|| IOErr::InvalidPath)?,
            )?;
            fs::remove_file(backup_path)?;
            return Ok(());
        }
        Ok(())
    })?;

    //TODO: auto commit change or init git repo(if the .password-store is newly created)
    Ok(())
}

#[cfg(test)]
mod tests {}
