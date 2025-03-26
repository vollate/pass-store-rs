use std::fs::create_dir_all;
use std::io::{BufRead, Read, Write};
use std::path::Path;

use anyhow::Result;
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

use crate::pgp::PGPClient;
use crate::util::fs_util::{create_or_overwrite, path_attack_check, prompt_overwrite};
use crate::{IOErr, IOErrType};

pub struct PasswdInsertConfig {
    pub echo: bool,
    pub multiline: bool,
    pub force: bool,
    pub extension: String,
}

pub fn insert_io<I, O, E>(
    client: &PGPClient,
    root: &Path,
    pass_name: &str,
    insert_cfg: &PasswdInsertConfig,
    in_s: &mut I,
    out_s: &mut O,
    err_s: &mut E,
) -> Result<bool>
where
    I: Read + BufRead,
    O: Write,
    E: Write,
{
    let pass_path = root.join(format!("{}.{}", pass_name, insert_cfg.extension));
    path_attack_check(root, &pass_path)?;

    // Handle the case parent folder not exist
    if let Some(parent) = pass_path.parent() {
        if !parent.exists() {
            create_dir_all(parent)?;
        }
    } else {
        return Err(IOErr::new(IOErrType::InvalidPath, &pass_path).into());
    }

    if pass_path.exists() && !insert_cfg.force && !prompt_overwrite(in_s, err_s, pass_name)? {
        return Ok(false);
    }

    if let Some(parent) = pass_path.parent() {
        if !parent.exists() {
            create_dir_all(parent)?;
        }
    }

    write!(out_s, "Enter password for '{}': ", pass_name)?;
    out_s.flush()?;

    let password = if insert_cfg.multiline {
        let mut buffer = String::new();
        in_s.read_to_string(&mut buffer)?;
        SecretString::new(buffer.into())
    } else {
        let mut buffer = String::new();
        in_s.read_line(&mut buffer)?;
        write!(out_s, "Confirm password for '{}': ", pass_name)?;
        out_s.flush()?;
        let mut confirm_buffer = String::new();
        in_s.read_line(&mut confirm_buffer)?;
        if buffer != confirm_buffer {
            writeln!(out_s, "Passwords do not match.")?;
            return Ok(false);
        }
        confirm_buffer.zeroize();
        SecretString::new(buffer.trim().to_string().into())
    };

    if insert_cfg.echo {
        writeln!(out_s, "{}", password.expose_secret())?;
    }

    create_or_overwrite(client, &pass_path, &password)?;
    writeln!(out_s, "Password encrypted and saved.")?;
    Ok(true)
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
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"password\n").unwrap();
                });

                let config = PasswdInsertConfig {
                    echo: false,
                    multiline: false,
                    force: false,
                    extension: "gpg".to_string(),
                };

                let res = insert_io(
                    &test_client,
                    &root,
                    "test1",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(res, true);

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
    fn wrong_insert() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let (mut stdin, mut stdin_w) = pipe().unwrap();
                let mut stdout = Vec::new();
                let mut stderr = Vec::new();

                thread::spawn(move || {
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"password\n").unwrap();
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"pd\n").unwrap();
                });

                let config = PasswdInsertConfig {
                    echo: false,
                    multiline: false,
                    force: false,
                    extension: "gpg".to_string(),
                };

                let res = insert_io(
                    &test_client,
                    &root,
                    "test1",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(res, false);
                assert_eq!(Path::new("test1.pgp").exists(), false);
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

                let config = PasswdInsertConfig {
                    echo: false,
                    multiline: true,
                    force: false,
                    extension: "gpg".into(),
                };

                let res = insert_io(
                    &test_client,
                    &root,
                    "test2",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                assert_eq!(res, true);

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
                    stdin_w.write_all(b"N\n").unwrap();
                });

                let mut config = PasswdInsertConfig {
                    echo: false,
                    multiline: false,
                    force: false,
                    extension: "gpg".to_string(),
                };

                let res = insert_io(
                    &test_client,
                    &root,
                    "test3",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                // This insert should fail because prompt failed.
                assert_eq!(res, false);

                let (mut stdin, mut stdin_w) = pipe().unwrap();
                thread::spawn(move || {
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"not\n").unwrap();
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"not\n").unwrap();
                });
                config.force = true;
                let res = insert_io(
                    &test_client,
                    &root,
                    "test3",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                // This time insert should succeed.
                assert_eq!(res, true);

                // Now try to prompt
                config.force = false;
                let (mut stdin, mut stdin_w) = pipe().unwrap();
                thread::spawn(move || {
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"y\n").unwrap();
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"new_password\n").unwrap();
                    sleep(Duration::from_millis(100));
                    stdin_w.write_all(b"new_password\n").unwrap();
                });
                let res = insert_io(
                    &test_client,
                    &root,
                    "test3",
                    &config,
                    &mut BufReader::new(&mut stdin),
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                // This time insert should succeed.
                assert_eq!(res, true);
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

                let config = PasswdInsertConfig {
                    echo: false,
                    multiline: false,
                    force: false,
                    extension: "gpg".to_string(),
                };

                let result = insert_io(
                    &test_client,
                    &root,
                    "../outside",
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
