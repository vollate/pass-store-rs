use std::path::{Path, PathBuf};
use std::process::Command;
use std::{env, fs};

use anyhow::{anyhow, Result};
use secrecy::ExposeSecret;
use tempfile::TempDir;
use zeroize::Zeroize;

use crate::pgp::PGPClient;
use crate::util::defer::Defer;
use crate::util::fs_util::{
    backup_encrypted_file, get_dir_gpg_id_content, path_attack_check, path_to_str,
    restore_backup_file,
};
use crate::util::rand::rand_alphabet_string;
use crate::{IOErr, IOErrType};

pub fn edit(
    root: &Path,
    target: &str,
    extension: &str,
    editor: &str,
    pgp_executable: &str,
) -> Result<bool> {
    let target_path = root.join(format!("{}.{}", target, extension));
    path_attack_check(root, &target_path)?;

    if !target_path.exists() {
        return Err(IOErr::new(IOErrType::PathNotExist, &target_path).into());
    } else if !target_path.is_file() {
        return Err(IOErr::new(IOErrType::ExpectFile, &target_path).into());
    }

    // Get the appropriate key fingerprints for this path
    let keys_fpr = get_dir_gpg_id_content(root, &target_path)?;
    let client = PGPClient::new(
        pgp_executable,
        &keys_fpr.iter().map(|s| s.as_str()).collect::<Vec<&str>>(),
    )?;

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
    let temp_filename =
        format!(".{}-{}", rand_alphabet_string(10), temp_filename.to_string_lossy());
    let temp_filepath = tmp_dir.join(temp_filename);

    let mut content = client.decrypt_stdin(root, path_to_str(&target_path)?)?;
    fs::write(&temp_filepath, content.expose_secret())?;
    let _cleaner = Defer::new(|| {
        let _ = fs::remove_file(&temp_filepath);
    });
    content.zeroize();

    let editor_args = [path_to_str(&temp_filepath)?];
    let mut cmd = Command::new(editor).args(editor_args).spawn()?;
    let status = cmd.wait()?;
    if status.success() {
        let new_content = fs::read_to_string(&temp_filepath)?;
        let mut old_content = client.decrypt_stdin(root, path_to_str(&target_path)?)?;
        if old_content.expose_secret() == new_content {
            println!("Password unchanged");
            return Ok(false);
        }
        old_content.zeroize();

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
        println!("Edit password for {} in repo {} using {}.", target, root.display(), editor);
        Ok(true)
    } else {
        Err(anyhow!("Failed to edit file"))
    }
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_ne;
    use serial_test::serial;

    use super::*;
    use crate::pgp::key_management::key_gen_batch;
    use crate::util::defer::cleanup;
    use crate::util::test_util::{
        clean_up_test_key, create_dir_structure, gen_unique_temp_dir, get_test_email,
        get_test_executable, gpg_key_edit_example_batch, gpg_key_gen_example_batch, write_gpg_id,
    };

    fn create_fake_editor(root: &Path) -> PathBuf {
        #[cfg(unix)]
        let fake_editor_content = r#"#!/bin/bash
file="$1"
sed -i '1d' "$file"
"#;

        #[cfg(windows)]
        let fake_editor_content = r#"@echo off
set file=%1
powershell -Command "(Get-Content %file% | Select-Object -Skip 1) | Set-Content %file%"
"#;

        let fake_editor_path =
            root.join(if cfg!(unix) { "fake_editor.sh" } else { "fake_editor.bat" });
        fs::write(&fake_editor_path, fake_editor_content).expect("Failed to write fake editor");

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&fake_editor_path).unwrap().permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&fake_editor_path, perms).unwrap();
        }

        fake_editor_path
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn basic() {
        let executable = &get_test_executable();
        let email = &get_test_email();

        // structure:
        // root
        // ├── file1.gpg
        // └── dir
        //     └── file2.gpg
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[(Some("dir"), &[][..])];
        create_dir_structure(&root, structure);

        let file1_content = "Sending in an eagle\n\n!!! You must edit this to pass the test !!!";
        let file2_content = "Requesting orbital\n\n!!! Do not edit this to pass the test !!!";
        cleanup!(
            {
                key_gen_batch(&get_test_executable(), &gpg_key_gen_example_batch()).unwrap();
                let test_client = PGPClient::new(executable, &[email]).unwrap();
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
                write_gpg_id(&root, &test_client.get_keys_fpr());

                let fake_editor = create_fake_editor(&root);
                let res1 =
                    edit(&root, "file1", "gpg", path_to_str(&fake_editor).unwrap(), executable)
                        .unwrap();
                let res2 = edit(&root, "dir/file2", "gpg", "cat", executable).unwrap();
                assert!(res1);
                assert!(!res2);

                let file1_new_content = test_client.decrypt_stdin(&root, output).unwrap();
                let file2_new_content = test_client.decrypt_stdin(&root, "dir/file2.gpg").unwrap();

                assert_ne!(file1_new_content.expose_secret(), file1_content);
                assert_eq!(file2_new_content.expose_secret(), file2_content);
            },
            {
                clean_up_test_key(executable, &[email]).unwrap();
            }
        );
    }
}
