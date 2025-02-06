use std::error::Error;
use std::fs;
use std::path::PathBuf;

use secrecy::ExposeSecret;

use crate::pgp::utils::{check_recipient_type, user_email_to_fingerprint, RecipientType};
use crate::pgp::PGPClient;
use crate::util::fs_utils::{backup_encrypted_file, path_to_str, process_files_recursively};
use crate::{IOErr, IOErrType};

const FPR_FILENAME: &str = ".gpg-id";

pub fn init(
    client: &PGPClient,
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
            return Err(IOErr::new(IOErrType::ExpectFile, &filepath).into());
        }
        if filename == FPR_FILENAME {
            let content = client.decrypt_stdin(&root_path, path_to_str(&filepath)?)?;
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
