use std::io::{BufRead, Read, Write};
use std::path::{Path, PathBuf};
use std::{fs, path};

use anyhow::Result;
use log::debug;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_util::{
    better_rename, copy_dir_recursive, get_dir_gpg_id_content, path_attack_check, path_to_str,
};
use crate::{IOErr, IOErrType};

// Currently, we do not support cross repo rename/copy
fn handle_overwrite_delete<I, O, E>(
    path_to_overwrite: &Path,
    force: bool,
    stdin: &mut I,
    stdout: &mut O,
    _stderr: &mut E,
) -> Result<bool>
where
    I: Read + BufRead,
    O: Write,
    E: Write,
{
    if !force {
        stdout.write_fmt(format_args!(
            "File {} already exists, overwrite? [y/N]: ",
            path_to_overwrite.to_string_lossy()
        ))?;
        stdout.flush()?;
        let mut input = String::new();
        stdin.read_line(&mut input)?;
        if !input.trim().to_lowercase().starts_with('y') {
            stdout.write_all("Canceled\n".as_bytes())?;
            return Ok(false);
        }
    }
    if path_to_overwrite.is_file() {
        fs::remove_file(path_to_overwrite)?;
    } else if path_to_overwrite.is_dir() {
        fs::remove_dir_all(path_to_overwrite)?;
    }
    Ok(true)
}

/// Copy or rename a file or directory, ask for confirmation if the target already exists(unless force)
/// # Arguments
/// * `copy` - Whether to copy or rename
/// * `from` - The path of the file or directory to copy or rename
/// * `to` - The path to copy or rename to
/// * `extension` - The extension to append to the file name if the target is a file
/// * `force` - Whether to overwrite the target if it already exists
/// * `in_s` - The input stream
/// * `out_s` - The output stream
/// * `err_s` - The error stream
fn copy_rename_file<I, O, E>(
    copy: bool,
    from: &Path,
    to: &Path,
    extension: &str,
    force: bool,
    in_s: &mut I,
    out_s: &mut O,
    err_s: &mut E,
) -> Result<()>
where
    I: Read + BufRead,
    O: Write,
    E: Write,
{
    let file_name =
        from.file_name().ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, from))?;

    // assume to is a directory
    if to.exists() {
        return if to.is_dir() {
            let sub_file = to.join(file_name);
            if sub_file.exists() && !handle_overwrite_delete(&sub_file, force, in_s, out_s, err_s)?
            {
                return Ok(());
            }
            if copy {
                fs::copy(from, sub_file)?;
            } else {
                better_rename(from.with_extension(extension), sub_file)?;
            }
            Ok(())
        } else {
            Err(IOErr::new(IOErrType::PathNotExist, to).into())
        };
    }

    // assume to is a file, append extension to it
    let to = PathBuf::from(format!("{}.{}", path_to_str(to)?, extension));
    if to.exists() {
        if to.is_file() {
            if !handle_overwrite_delete(&to, force, in_s, out_s, err_s)? {
                return Ok(());
            }
        } else {
            return Err(IOErr::new(IOErrType::PathNotExist, &to).into());
        }
    }
    if copy {
        fs::copy(from, to)?;
    } else {
        better_rename(from.with_extension(extension), to)?;
    }
    Ok(())
}

/// Copy or rename a directory
/// # Arguments
/// * `copy` - Whether to copy or rename
/// * `from` - The path of the directory to copy or rename
/// * `to` - The path to copy or rename to
/// * `force` - Whether to overwrite the target if it already exists
/// * `in_s` - The input stream
/// * `out_s` - The output stream
/// * `err_s` - The error stream
fn copy_rename_dir<I, O, E>(
    copy: bool,
    from: &Path,
    to: &Path,
    force: bool,
    in_s: &mut I,
    out_s: &mut O,
    err_s: &mut E,
) -> Result<()>
where
    I: Read + BufRead,
    O: Write,
    E: Write,
{
    let file_name =
        from.file_name().ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, from))?;

    if to.exists() {
        if to.is_dir() {
            let sub_dir = to.join(file_name);
            if sub_dir.exists() && !handle_overwrite_delete(&sub_dir, force, in_s, out_s, err_s)? {
                return Ok(());
            }
            if copy {
                copy_dir_recursive(from, sub_dir)?;
            } else {
                better_rename(from, sub_dir)?;
            }
        } else if to.is_file() {
            if !handle_overwrite_delete(to, force, in_s, out_s, err_s)? {
                return Ok(());
            }
            if copy {
                copy_dir_recursive(from, to)?;
            } else {
                better_rename(from, to)?;
            }
        } else {
            return Err(IOErr::new(IOErrType::InvalidFileType, to).into());
        }
    } else if copy {
        copy_dir_recursive(from, to)?;
    } else {
        better_rename(from, to)?;
    }
    Ok(())
}

pub fn copy_rename_io<I, O, E>(
    copy: bool,
    root: &Path,
    from: &str,
    to: &str,
    file_extension: &str,
    force: bool,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<()>
where
    I: Read + BufRead,
    O: Write,
    E: Write,
{
    let mut from_path = root.join(from);
    let to_path = root.join(to);
    path_attack_check(root, &from_path)?;
    path_attack_check(root, &to_path)?;

    if !from_path.exists() {
        let try_path = PathBuf::from(format!("{}.{}", path_to_str(&from_path)?, file_extension));
        if !try_path.exists() {
            return Err(IOErr::new(IOErrType::PathNotExist, &from_path).into());
        }
        from_path = try_path;
    }
    debug!("copy_rename_io: from_path: {}, to_path: {}", from_path.display(), to_path.display());

    let to_is_dir = to.ends_with(path::MAIN_SEPARATOR);
    if to_is_dir && (!to_path.exists() || !to_path.is_dir()) {
        writeln!(
            stderr,
            "Cannot {} '{}' to '{}': No such directory",
            if copy { "copy" } else { "rename" },
            from,
            to
        )?;
        return Err(IOErr::new(IOErrType::PathNotExist, &to_path).into());
    }

    // Check if we're dealing with GPG-encrypted files and need to re-encrypt
    let needs_reencryption =
        if from_path.is_file() && from_path.extension().is_some_and(|ext| ext == file_extension) {
            let from_dir = from_path.parent().unwrap_or(root);
            let to_dir = if to_path.exists() && to_path.is_dir() {
                &to_path
            } else {
                to_path.parent().unwrap_or(root)
            };

            // Compare GPG keys between source and destination directories
            match (get_dir_gpg_id_content(root, from_dir), get_dir_gpg_id_content(root, to_dir)) {
                (Ok(from_keys), Ok(to_keys)) => {
                    let mut from_keys_sorted = from_keys.clone();
                    let mut to_keys_sorted = to_keys.clone();
                    from_keys_sorted.sort();
                    to_keys_sorted.sort();

                    // If keys are different, we need to re-encrypt
                    from_keys_sorted != to_keys_sorted
                }
                _ => false, // If we can't get keys, default to not re-encrypting
            }
        } else {
            false
        };

    if needs_reencryption {
        debug!("Different GPG IDs detected, re-encryption required");

        // If it's a file that needs re-encryption
        if from_path.is_file() {
            // Get the target directory for determining GPG keys
            let target_dir = if to_path.exists() && to_path.is_dir() {
                to_path.clone()
            } else {
                to_path.parent().unwrap_or(root).to_path_buf()
            };

            // Get target filename
            let target_file = if to_path.exists() && to_path.is_dir() {
                let filename = from_path
                    .file_name()
                    .ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, &from_path))?;
                to_path.join(filename)
            } else {
                PathBuf::from(format!("{}.{}", path_to_str(&to_path)?, file_extension))
            };

            // Check for overwrite
            if target_file.exists()
                && !handle_overwrite_delete(&target_file, force, stdin, stdout, stderr)?
            {
                return Ok(());
            }

            // Set up clients for decryption and re-encryption
            let from_dir = from_path.parent().unwrap_or(root);
            let from_keys = get_dir_gpg_id_content(root, from_dir)?;
            let to_keys = get_dir_gpg_id_content(root, &target_dir)?;

            // Create client for decryption with source keys
            let source_client = match PGPClient::new("gpg", &from_keys) {
                Ok(client) => client,
                Err(e) => {
                    writeln!(stderr, "Error creating PGP client for decryption: {}", e)?;
                    return Err(e);
                }
            };

            // Create client for encryption with destination keys
            let target_client = match PGPClient::new("gpg", &to_keys) {
                Ok(client) => client,
                Err(e) => {
                    writeln!(stderr, "Error creating PGP client for encryption: {}", e)?;
                    return Err(e);
                }
            };

            // Decrypt the file
            let content = match source_client.decrypt_stdin(root, path_to_str(&from_path)?) {
                Ok(content) => content,
                Err(e) => {
                    writeln!(stderr, "Error decrypting file: {}", e)?;
                    return Err(e);
                }
            };

            // Encrypt with the destination keys
            match target_client.encrypt(content.expose_secret(), path_to_str(&target_file)?) {
                Ok(_) => {
                    if !copy {
                        // If this was a move operation, delete the original file
                        if let Err(e) = fs::remove_file(&from_path) {
                            writeln!(
                                stderr,
                                "Warning: Failed to delete original file after move: {}",
                                e
                            )?;
                        }
                    }
                    return Ok(());
                }
                Err(e) => {
                    writeln!(stderr, "Error re-encrypting file: {}", e)?;
                    return Err(e);
                }
            }
        }
    }

    // Default behavior for cases not needing re-encryption
    if from_path.is_file() {
        copy_rename_file(copy, &from_path, &to_path, file_extension, force, stdin, stdout, stderr)
    } else if from_path.is_dir() {
        copy_rename_dir(copy, &from_path, &to_path, force, stdin, stdout, stderr)
    } else {
        Err(IOErr::new(IOErrType::InvalidFileType, &from_path).into())
    }
}

#[cfg(test)]
mod tests {
    use std::io::{self, BufReader};
    use std::thread::{self, sleep};

    use os_pipe::pipe;
    use pretty_assertions::assert_eq;
    use serial_test::serial;

    use super::*;
    use crate::pgp::key_management::key_gen_batch;
    use crate::util::defer::cleanup;
    use crate::util::test_util::{
        clean_up_test_key, create_dir_structure, gen_unique_temp_dir, get_test_email,
        get_test_executable, gpg_key_edit_example_batch, gpg_key_gen_example_batch, write_gpg_id,
    };

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn rename_test() {
        // Original structure:
        // root
        // ├── a.gpg
        // ├── d_dir/
        // ├── e_dir/
        // └── b.gpg
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(None, &["a.gpg", "b.gpg"][..]), (Some("d_dir"), &[][..]), (Some("e_dir"), &[][..])];
        create_dir_structure(&root, structure);

        cleanup!(
            {
                let (stdin, mut stdin_w) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = io::stdout().lock();
                let mut stderr = io::stderr().lock();

                // Rename a.gpg to c.gpg
                copy_rename_io(
                    false,
                    &root,
                    "a",
                    "c",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(false, root.join("a.gpg").exists());
                assert_eq!(true, root.join("c.gpg").exists());

                // Rename b.gpg to c.gpg, without force, input "n" interactively
                thread::spawn(move || {
                    sleep(std::time::Duration::from_millis(100));
                    stdin_w.write_all(b"n\n").unwrap();
                });
                copy_rename_io(
                    false,
                    &root,
                    "b",
                    "c",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(true, root.join("b.gpg").exists());

                // Rename b.gpg to c.gpg, with force
                copy_rename_io(
                    false,
                    &root,
                    "b",
                    "c",
                    "gpg",
                    true,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(false, root.join("b.gpg").exists());
                assert_eq!(true, root.join("c.gpg").exists());

                // Now, try to rename file into a dir(end with path separator)
                copy_rename_io(
                    false,
                    &root,
                    "c",
                    &format!("d_dir{}", path::MAIN_SEPARATOR_STR),
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(false, root.join("c.gpg").exists());
                assert_eq!(true, root.join("d_dir").join("c.gpg").exists());

                // Try to rename d_dir to e_dir, should be e_dir/d_dir
                copy_rename_io(
                    false,
                    &root,
                    "d_dir",
                    "e_dir",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(false, root.join("d_dir").exists());
                assert_eq!(true, root.join("e_dir").join("d_dir").exists());
            },
            {}
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn copy_test() {
        // Original structure:
        // root
        // ├── a.gpg
        // ├── d_dir/
        // ├── e_dir/
        // └── b.gpg
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(None, &["a.gpg", "b.gpg"][..]), (Some("d_dir"), &[][..]), (Some("e_dir"), &[][..])];
        create_dir_structure(&root, structure);

        cleanup!(
            {
                let (stdin, mut stdin_w) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = io::stdout().lock();
                let mut stderr = io::stderr().lock();

                // Copy a.gpg to c.gpg
                fs::write(root.join("a.gpg"), "foo_a").unwrap();
                assert_eq!(false, root.join("c.gpg").exists());
                copy_rename_io(
                    true,
                    &root,
                    "a",
                    "c",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(true, root.join("a.gpg").exists());
                assert_eq!(true, root.join("c.gpg").exists());
                assert_eq!("foo_a", fs::read_to_string(root.join("c.gpg")).unwrap());

                // Copy b.gpg to c.gpg, without force, input "n" interactively
                fs::write(root.join("b.gpg"), "foo_b").unwrap();
                thread::spawn(move || {
                    sleep(std::time::Duration::from_millis(100));
                    stdin_w.write_all(b"n\n").unwrap();
                });

                copy_rename_io(
                    true,
                    &root,
                    "b",
                    "c",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_ne!("foo_b", fs::read_to_string(root.join("c.gpg")).unwrap());

                // Copy b.gpg to c.gpg, with force, overwrite the content of c.gpg
                copy_rename_io(
                    true,
                    &root,
                    "b",
                    "c",
                    "gpg",
                    true,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!("foo_b", fs::read_to_string(root.join("c.gpg")).unwrap());

                // Now, try to copy file into a dir(end with path separator)
                fs::write(root.join("c.gpg"), "foo_c").unwrap();
                copy_rename_io(
                    true,
                    &root,
                    "c",
                    &format!("d_dir{}", path::MAIN_SEPARATOR_STR),
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(true, root.join("c.gpg").exists());
                assert_eq!("foo_c", fs::read_to_string(root.join("c.gpg")).unwrap());

                // Try to copy d_dir to e_dir, should be e_dir/d_dir
                copy_rename_io(
                    true,
                    &root,
                    "d_dir",
                    "e_dir",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(true, root.join("d_dir").exists());
                assert_eq!(true, root.join("e_dir").join("d_dir").exists());
            },
            {}
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    // Try to access parent directory, should be blocked
    fn path_attack_protection_test() {
        // Simple structure:
        // root
        // └── a.gpg
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[(None, &["a.gpg"][..])];
        create_dir_structure(&root, structure);

        cleanup!(
            {
                let mut stdin = io::stdin().lock();
                let mut stdout = io::stdout().lock();
                let mut stderr = io::stderr().lock();
                if copy_rename_io(
                    false,
                    &root,
                    "../../a",
                    "c",
                    "gpg",
                    true,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .is_ok()
                {
                    panic!(
                        "Should not be able to access parent directory: {}/../../a",
                        root.display()
                    );
                }

                if copy_rename_io(
                    true,
                    &root,
                    "a",
                    "../../c",
                    "gpg",
                    true,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .is_ok()
                {
                    panic!(
                        "Should not be able to access parent directory: {}/../../c",
                        root.display()
                    );
                }
            },
            {}
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn re_encrypt_case_test() {
        // Set up directory structure:
        // root
        // ├── .gpg-id (with key1)
        // ├── file1.gpg (encrypted with key1)
        // └── subdir/
        //     └── .gpg-id (with key2)
        let executable = get_test_executable();
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[(None, &[][..]), (Some("subdir"), &[][..])];
        create_dir_structure(&root, structure);

        // Create first client with first key
        key_gen_batch(&executable, &gpg_key_gen_example_batch()).unwrap();
        let email1 = get_test_email();
        let client1 = PGPClient::new(executable.clone(), &[&email1]).unwrap();
        client1.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        let key1_fpr = client1.get_keys_fpr();

        // Create a second key for the subdirectory
        // We create a new email by appending a suffix to make it unique
        let email2 = format!("sub-{}", email1);
        let second_key_batch = format!(
            r#"%echo Generating a second key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Test User Sub
Name-Email: {}
Expire-Date: 0
Passphrase: password
%commit
%echo Key generation complete
"#,
            email2
        );

        key_gen_batch(&executable, &second_key_batch).unwrap();
        let client2 = PGPClient::new(executable.clone(), &[&email2]).unwrap();
        client2.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        let key2_fpr = client2.get_keys_fpr();

        // Write different .gpg-id files to root and subdirectory
        write_gpg_id(&root, &key1_fpr);
        write_gpg_id(&root.join("subdir"), &key2_fpr);

        // Set up standard I/O for the copy operation
        let (stdin, _stdin_w) = pipe().unwrap();
        let mut stdin = BufReader::new(stdin);
        let mut stdout = io::stdout().lock();
        let mut stderr = io::stderr().lock();

        cleanup!(
            {
                // Create a test file in the root directory encrypted with key1
                let test_content = "This is a secret message";
                client1.encrypt(test_content, root.join("file1.gpg").to_str().unwrap()).unwrap();

                // Copy the file to the subdirectory
                copy_rename_io(
                    true,
                    &root,
                    "file1",
                    "subdir/file1",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                // Verify both files exist (since it's a copy)
                assert!(root.join("file1.gpg").exists());
                assert!(root.join("subdir").join("file1.gpg").exists());

                // Verify the file in the subdirectory can be decrypted with client2
                let decrypted = client2.decrypt_stdin(&root, "subdir/file1.gpg").unwrap();
                assert_eq!(decrypted.expose_secret(), test_content);

                // Now test moving a file (which should also trigger re-encryption)
                // Create another file in the root
                let test_content2 = "Another secret message for moving";
                client1.encrypt(test_content2, root.join("file2.gpg").to_str().unwrap()).unwrap();

                // Move the file to the subdirectory
                copy_rename_io(
                    false, // false = move instead of copy
                    &root,
                    "file2",
                    "subdir/file2",
                    "gpg",
                    false,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                // Verify the original file is gone (since it's a move)
                assert!(!root.join("file2.gpg").exists());
                assert!(root.join("subdir").join("file2.gpg").exists());

                // Verify the moved file can be decrypted with client2
                let decrypted = client2.decrypt_stdin(&root, "subdir/file2.gpg").unwrap();
                assert_eq!(decrypted.expose_secret(), test_content2);
            },
            {
                // Clean up both keys
                let emails = vec![email1.as_str(), email2.as_str()];
                clean_up_test_key(&executable, &emails).unwrap();
            }
        );
    }
}
