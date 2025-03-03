use std::fs;
use std::io::{Read, Write};
use std::path::Path;

use anyhow::{Error, Result};
use secrecy::{ExposeSecret, SecretString};

use crate::pgp::PGPClient;
use crate::util::fs_util::{
    backup_encrypted_file, path_attack_check, path_to_str, restore_backup_file,
};

pub struct PasswdInsertConfig {
    pub echo: bool,
    pub multiline: bool,
    pub force: bool,
}

pub fn insert_io<I, O, E>(
    client: &PGPClient,
    root: &Path,
    pass_name: &str,
    config: &PasswdInsertConfig,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<()>
where
    I: Read + std::io::BufRead,
    O: Write,
    E: Write,
{
    let pass_path = root.join(pass_name);

    path_attack_check(root, &pass_path)?;
    if pass_path.exists() && !config.force {
        let err_msg =
            format!("An entry already exists for {}. Use -f to force overwrite.", pass_name);
        writeln!(stderr, "{}", err_msg)?;
        return Err(Error::msg(err_msg));
    }

    if let Some(parent) = pass_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let password = if config.multiline {
        let mut buffer = String::new();
        stdin.read_to_string(&mut buffer)?;
        SecretString::new(buffer.into())
    } else {
        let mut buffer = String::new();
        stdin.read_line(&mut buffer)?;
        SecretString::new(buffer.trim().to_string().into())
    };

    if config.echo {
        writeln!(stdout, "{}", password.expose_secret())?;
    }

    if pass_path.exists() {
        let backup = backup_encrypted_file(&pass_path)?;
        match client.encrypt(password.expose_secret(), path_to_str(&pass_path)?) {
            Ok(_) => {
                fs::remove_file(&backup)?;
            }
            Err(e) => {
                restore_backup_file(&backup)?;
                return Err(e);
            }
        }
    } else {
        client.encrypt(password.expose_secret(), path_to_str(&pass_path)?)?;
    }
    writeln!(stdout, "Password encrypted and saved.")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::io::BufReader;
    use std::path::PathBuf;
    use std::thread::{self, sleep};
    use std::time::Duration;

    use os_pipe::pipe;
    use pretty_assertions::assert_eq;
    use serial_test::serial;
    use tempfile::TempDir;

    use super::*;
    use crate::pgp::key_management::key_gen_batch;
    use crate::util::defer::cleanup;
    use crate::util::test_util::*;

    fn setup_test_environment() -> (String, String, PGPClient, TempDir, PathBuf) {
        let executable = get_test_executable();
        let email = get_test_email();
        let (tmp_dir, root) = gen_unique_temp_dir();

        key_gen_batch(&executable, &gpg_key_gen_example_batch()).unwrap();
        let test_client = PGPClient::new(executable.clone(), &vec![&email]).unwrap();
        test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();

        (executable, email, test_client, tmp_dir, root)
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn basic_insert() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let (mut stdin, mut stdin_w) = pipe().unwrap();
                let mut stdout = Vec::new();
                let mut stderr = Vec::new();

                thread::spawn(move || {
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"password\n").unwrap();
                });

                let config = PasswdInsertConfig { echo: false, multiline: false, force: false };

                insert_io(
                    &test_client,
                    &root,
                    "test1.gpg",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                let decrypted = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(decrypted.expose_secret(), "password");
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn multiline_insert() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let (mut stdin, mut stdin_w) = pipe().unwrap();
                let mut stdout = Vec::new();
                let mut stderr = Vec::new();

                thread::spawn(move || {
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"line1\nline2\nline3").unwrap();
                });

                let config = PasswdInsertConfig { echo: false, multiline: true, force: false };

                insert_io(
                    &test_client,
                    &root,
                    "test2.gpg",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                let decrypted = test_client.decrypt_stdin(&root, "test2.gpg").unwrap();
                assert_eq!(decrypted.expose_secret(), "line1\nline2\nline3");
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn force_overwrite() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let (mut stdin, mut stdin_w) = pipe().unwrap();
                let mut stdout = Vec::new();
                let mut stderr = Vec::new();

                // Create initial file
                test_client
                    .encrypt("old_password", root.join("test3.gpg").to_str().unwrap())
                    .unwrap();

                thread::spawn(move || {
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"new_password\n").unwrap();
                });

                let config = PasswdInsertConfig { echo: false, multiline: false, force: true };

                insert_io(
                    &test_client,
                    &root,
                    "test3.gpg",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                let decrypted = test_client.decrypt_stdin(&root, "test3.gpg").unwrap();
                assert_eq!(decrypted.expose_secret(), "new_password");
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn invalid_path() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let (mut stdin, _) = pipe().unwrap();
                let mut stdout = Vec::new();
                let mut stderr = Vec::new();

                let config = PasswdInsertConfig { echo: false, multiline: false, force: false };

                let result = insert_io(
                    &test_client,
                    &root,
                    "../outside.gpg",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                );

                assert!(result.is_err());
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }
}
