use std::error::Error;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::{env, fs};

use secrecy::ExposeSecret;
use tempfile::TempDir;
use zeroize::Zeroize;

use crate::pgp::PGPClient;
use crate::util::defer::Defer;
use crate::util::fs_utils::{backup_encrypted_file, path_to_str, restore_backup_file};
use crate::util::rand::rand_aplhabet_string;
use crate::{IOErr, IOErrType};

pub fn edit(
    client: &PGPClient,
    root: &Path,
    target: &str,
    editor: &str,
) -> Result<(), Box<dyn Error>> {
    let target_path = root.join(target);
    if !target_path.exists() {
        return Err(IOErr::new(crate::IOErrType::PathNotExist, &target_path).into());
    } else if !target_path.is_file() {
        return Err(IOErr::new(crate::IOErrType::ExpectFile, &target_path).into());
    }

    let tmp_dir: PathBuf = {
        let temp_base = {
            #[cfg(unix)]
            {
                let shm_dir = PathBuf::from("/dev/shm");
                if !shm_dir.exists() {
                    env::temp_dir()
                } else {
                    shm_dir
                }
            }
            #[cfg(not(unix))]
            {
                env::temp_dir()
            }
        };
        TempDir::new_in(temp_base)?.into_path()
    };

    let temp_filename = target_path.with_extension("txt");
    let temp_filename = temp_filename
        .file_name()
        .ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, &target_path))?;
    let temp_filename = format!("{}-{}", rand_aplhabet_string(10), temp_filename.to_string_lossy());
    let temp_filepath = tmp_dir.join(temp_filename);

    let mut content = client.decrypt_stdin(path_to_str(&target_path)?)?;
    fs::write(&temp_filepath, content.expose_secret())?;
    let _cleaner = Defer::new(|| {
        let _ = fs::remove_file(&temp_filepath);
    });
    content.zeroize();

    let mut cmd = Command::new(editor).arg(path_to_str(&temp_filepath)?).spawn()?;
    let status = cmd.wait()?;
    if status.success() {
        let new_content = fs::read_to_string(&temp_filepath)?;
        let backup_file = backup_encrypted_file(&target_path)?;
        match client.encrypt(&new_content, path_to_str(&target_path)?) {
            Ok(_) => {
                fs::remove_file(&backup_file)?;
            }
            Err(e) => {
                restore_backup_file(&backup_file)?;
                return Err(e);
            }
        }
        Ok(())
    } else {
        Err("Failed to edit file".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::test_utils::{
        clean_up_test_key, cleanup_test_dir, create_dir_structure, gen_unique_temp_dir,
        get_test_email, get_test_executable, get_test_username, gpg_key_edit_example_batch,
        gpg_key_gen_example_batch,
    };

    #[test]
    #[ignore = "need run interactively"]
    fn test_edit() {
        let executable = &get_test_executable();
        let email = &get_test_email();

        // structure:
        // root
        // ├── file1.gpg
        // └── dir
        //     └── file2.gpg
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[(Some("dir"), &[][..])];
        create_dir_structure(&root, structure);

        let file1_content = "Sending in an eagle";
        let file2_content = "Requesting orbital";
        cleanup!(
            {
                let mut test_client = PGPClient::new(
                    executable.to_string(),
                    None,
                    Some(get_test_username()),
                    Some(email.to_string()),
                );
                test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
                test_client.update_info().unwrap();
                test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
                let new_dir = root.join("file1.gpg");
                let output = path_to_str(&new_dir).unwrap();
                println!("{}", output);
                test_client.encrypt(file1_content, output).unwrap();
                test_client
                    .encrypt(
                        file2_content,
                        path_to_str(&root.join("dir").join("file2.gpg")).unwrap(),
                    )
                    .unwrap();
                edit(&test_client, &root, "file1.gpg", "vim").unwrap();
                edit(&test_client, &root, "dir/file2.gpg", "vim").unwrap();

                let file1_new_content = test_client.decrypt_stdin(output).unwrap();
                let file2_new_content = test_client
                    .decrypt_stdin(path_to_str(&root.join("dir").join("file2.gpg")).unwrap())
                    .unwrap();

                println!("file1.gpg new content:\n{}", file1_new_content.expose_secret());
                println!("dir/file2.gpg new content:\n{}", file2_new_content.expose_secret());
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }
}
