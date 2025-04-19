use std::fs;
use std::io::{BufRead, Read, Write};
use std::path::Path;

use anyhow::{anyhow, Result};
use passwords::PasswordGenerator;
use secrecy::{ExposeSecret, SecretString};

use crate::pgp::PGPClient;
use crate::util::fs_util;
use crate::util::fs_util::{
    backup_encrypted_file, create_or_overwrite, get_dir_gpg_id_content, path_attack_check,
    path_to_str, restore_backup_file,
};

pub struct PasswdGenerateConfig {
    pub no_symbols: bool,
    pub in_place: bool,
    pub force: bool,
    pub pass_length: usize,
    pub extension: String,
    pub pgp_executable: String,
}

pub fn generate_io<I, O, E>(
    root: &Path,
    pass_name: &str,
    gen_cfg: &PasswdGenerateConfig,
    in_s: &mut I,
    out_s: &mut O,
    err_s: &mut E,
) -> Result<SecretString>
where
    I: Read + BufRead,
    O: Write,
    E: Write,
{
    let pass_path = root.join(format!("{}.{}", pass_name, gen_cfg.extension));

    path_attack_check(root, &pass_path)?;

    if gen_cfg.in_place && gen_cfg.force {
        let err_msg = "Cannot use both [--in-place] and [--force]";
        writeln!(err_s, "{}", err_msg)?;
        return Err(anyhow!(err_msg));
    }

    if pass_path.exists()
        && !gen_cfg.force
        && !gen_cfg.in_place
        && !fs_util::prompt_overwrite(in_s, err_s, pass_name)?
    {
        writeln!(out_s, "Operation cancelled.")?;
        return Ok(SecretString::new("".to_string().into()));
    }

    let pg = PasswordGenerator::new()
        .length(gen_cfg.pass_length)
        .numbers(true)
        .lowercase_letters(true)
        .uppercase_letters(true)
        .symbols(!gen_cfg.no_symbols)
        .spaces(false)
        .exclude_similar_characters(true)
        .strict(true);

    let password = SecretString::new(pg.generate_one().map_err(|e| anyhow!(e))?.into());

    // Get the appropriate key fingerprints for this path
    let keys_fpr = get_dir_gpg_id_content(root, &pass_path)?;
    let client = PGPClient::new(
        &gen_cfg.pgp_executable,
        &keys_fpr.iter().map(|s| s.as_str()).collect::<Vec<&str>>(),
    )?;

    if gen_cfg.in_place && pass_path.exists() {
        let existing = client.decrypt_stdin(root, path_to_str(&pass_path)?)?;
        let mut content = existing.expose_secret().lines().collect::<Vec<_>>();

        if !content.is_empty() {
            content[0] = password.expose_secret();

            let backup = backup_encrypted_file(&pass_path)?;
            match client.encrypt(&content.join("\n"), path_to_str(&pass_path)?) {
                Ok(_) => {
                    fs::remove_file(&backup)?;
                }
                Err(e) => {
                    restore_backup_file(&backup)?;
                    return Err(e);
                }
            }
        }
    } else {
        if let Some(parent) = pass_path.parent() {
            fs::create_dir_all(parent)?;
        }

        create_or_overwrite(&client, &pass_path, &password)?;
    }

    writeln!(out_s, "Generated password for '{}' saved", pass_name)?;

    Ok(password)
}

#[cfg(test)]
mod tests {

    use std::io::{stderr, stdout, BufReader};
    use std::thread;

    use os_pipe::pipe;
    use pretty_assertions::assert_eq;
    use serial_test::serial;

    use super::*;
    use crate::pgp::key_management::key_gen_batch;
    use crate::util::defer::cleanup;
    use crate::util::test_util::*;

    fn setup_test_client(root: &Path) -> PGPClient {
        key_gen_batch(&get_test_executable(), &gpg_key_gen_example_batch()).unwrap();
        let test_client = PGPClient::new(get_test_executable(), &vec![&get_test_email()]).unwrap();
        test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        write_gpg_id(root, &test_client.get_keys_fpr());
        test_client
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn basic_password_generation() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let (stdin, stdin_w) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();
                let test_client = setup_test_client(&root);

                let mut config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: false,
                    force: false,
                    pass_length: 16,
                    extension: "gpg".to_string(),
                    pgp_executable: executable.clone(),
                };

                let password =
                    generate_io(&root, "test1", &config, &mut stdin, &mut stdout, &mut stderr)
                        .unwrap();

                assert_eq!(password.expose_secret().len(), 16);
                assert!(root.join("test1.gpg").exists());
                let secret = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(secret.expose_secret(), password.expose_secret());

                // Now test interactive overwrite
                config.pass_length = 114;
                thread::spawn(move || {
                    let mut stdin = stdin_w;
                    stdin.write_all(b"n").unwrap();
                });
                let original_passwd = password;
                let password =
                    generate_io(&root, "test1", &config, &mut stdin, &mut stdout, &mut stderr)
                        .unwrap();
                let secret = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(password.expose_secret(), "");
                assert_eq!(secret.expose_secret(), original_passwd.expose_secret());

                let (stdin, stdin_w) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                thread::spawn(move || {
                    let mut stdin = stdin_w;
                    stdin.write_all(b"y").unwrap();
                });
                let password =
                    generate_io(&root, "test1", &config, &mut stdin, &mut stdout, &mut stderr)
                        .unwrap();
                let secret = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(secret.expose_secret(), password.expose_secret());
                assert_eq!(password.expose_secret().len(), 114);
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn inplace_generation() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let (stdin, _) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let test_client = setup_test_client(&root);
                test_client
                    .encrypt(
                        "existing\npassword\nfor super earth",
                        path_to_str(&root.join("test2.gpg")).unwrap(),
                    )
                    .unwrap();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: true,
                    force: false,
                    pass_length: 12,
                    extension: "gpg".to_string(),
                    pgp_executable: executable.clone(),
                };

                let password =
                    generate_io(&root, "test2", &config, &mut stdin, &mut stdout, &mut stderr)
                        .unwrap();

                let content = test_client.decrypt_stdin(&root, "test2.gpg").unwrap();
                let lines: Vec<&str> = content.expose_secret().lines().collect();
                assert_eq!(lines[0], password.expose_secret());
                assert_eq!(password.expose_secret().len(), 12);
                assert_eq!(lines[1], "password");
                assert_eq!(lines[2], "for super earth");
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
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let (stdin, _) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let test_client = setup_test_client(&root);
                test_client
                    .encrypt("old_password", path_to_str(&root.join("test3.gpg")).unwrap())
                    .unwrap();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: false,
                    force: true,
                    pass_length: 8,
                    extension: "gpg".to_string(),
                    pgp_executable: executable.clone(),
                };

                let password =
                    generate_io(&root, "test3", &config, &mut stdin, &mut stdout, &mut stderr)
                        .unwrap();

                assert_eq!(password.expose_secret().len(), 8);
                let content = test_client.decrypt_stdin(&root, "test3.gpg").unwrap();
                assert_eq!(content.expose_secret(), password.expose_secret());
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn no_symbols() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let (stdin, _) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();
                let test_client = setup_test_client(&root);

                let config = PasswdGenerateConfig {
                    no_symbols: true,
                    in_place: false,
                    force: false,
                    pass_length: 10,
                    extension: "gpg".to_string(),
                    pgp_executable: executable.clone(),
                };

                let password =
                    generate_io(&root, "test4", &config, &mut stdin, &mut stdout, &mut stderr)
                        .unwrap();
                assert!(!password.expose_secret().contains(|c: char| !c.is_alphanumeric()));
                let content = test_client.decrypt_stdin(&root, "test4.gpg").unwrap();
                assert_eq!(content.expose_secret(), password.expose_secret());
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
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let (stdin, _) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: false,
                    force: false,
                    pass_length: 16,
                    extension: "gpg".to_string(),
                    pgp_executable: executable.clone(),
                };

                let result =
                    generate_io(&root, "../outside", &config, &mut stdin, &mut stdout, &mut stderr);

                assert!(result.is_err());
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn invalid_flag() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let (stdin, _) = pipe().unwrap();
                let mut stdin = BufReader::new(stdin);
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: true,
                    force: true,
                    pass_length: 16,
                    extension: "gpg".to_string(),
                    pgp_executable: executable.clone(),
                };

                let result =
                    generate_io(&root, "test5", &config, &mut stdin, &mut stdout, &mut stderr);

                assert!(result.is_err());
            },
            {
                clean_up_test_key(&executable, &vec![&email]).unwrap();
            }
        );
    }
}
