use std::error::Error;
use std::fs;
use std::io::{Read, Write};
use std::path::Path;

use passwords::PasswordGenerator;
use secrecy::{ExposeSecret, SecretString};

use crate::pgp::PGPClient;
use crate::util::fs_utils::{
    backup_encrypted_file, path_attack_check, path_to_str, restore_backup_file,
};

pub struct PasswdGenerateConfig {
    no_symbols: bool,
    in_place: bool,
    force: bool,
    length: usize,
}
fn prompt_overwrite<R: Read, W: Write>(
    stdin: &mut R,
    stderr: &mut W,
    pass_name: &str,
) -> Result<bool, Box<dyn Error>> {
    write!(stderr, "An entry already exists for {}. Overwrite? [y/N]: ", pass_name)?;
    let mut input = String::new();
    stdin.read_to_string(&mut input)?;
    Ok(input.trim().eq_ignore_ascii_case("y"))
}
pub fn generate_io<I, O, E>(
    client: &PGPClient,
    root: &Path,
    pass_name: &str,
    config: &PasswdGenerateConfig,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<SecretString, Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    let pass_path = root.join(pass_name);

    path_attack_check(&root, &pass_path, pass_name, stderr)?;

    if config.in_place && config.force {
        let err_msg = "Cannot use both [--in-place] and [--force]";
        writeln!(stderr, "{}", err_msg)?;
        return Err(err_msg.into());
    }
    if pass_path.exists() && !config.force && !config.in_place {
        if !prompt_overwrite(stdin, stderr, pass_name)? {
            writeln!(stdout, "Operation cancelled.")?;
            return Ok(SecretString::new("".to_string().into()));
        }
    }

    let pg = PasswordGenerator::new()
        .length(config.length)
        .numbers(true)
        .lowercase_letters(true)
        .uppercase_letters(true)
        .symbols(!config.no_symbols)
        .spaces(false)
        .exclude_similar_characters(true)
        .strict(true);

    let password = SecretString::new(pg.generate_one()?.into());

    if config.in_place && pass_path.exists() {
        let existing = client.decrypt_stdin(&root, path_to_str(&pass_path)?)?;
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
    }

    writeln!(stdout, "Generated password for {} saved", pass_name)?;

    Ok(password)
}

#[cfg(test)]
mod tests {

    use std::io::{stderr, stdout};
    use std::thread;

    use os_pipe::pipe;
    use pretty_assertions::assert_eq;
    use serial_test::serial;

    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::test_utils::*;

    fn setup_test_client() -> PGPClient {
        let mut test_client = PGPClient::new(
            get_test_executable(),
            None,
            Some(get_test_username()),
            Some(get_test_email()),
        );
        test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        test_client.update_info().unwrap();
        test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        test_client
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_basic_password_generation() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let test_client = setup_test_client();
                let (mut stdin, stdin_w) = pipe().unwrap();
                let mut stdout = stdout().lock();

                let mut stderr = stderr().lock();

                let mut config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: false,
                    force: false,
                    length: 16,
                };

                let password = generate_io(
                    &test_client,
                    &root,
                    "test1.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                assert_eq!(password.expose_secret().len(), 16);
                assert!(root.join("test1.gpg").exists());
                let secret = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(secret.expose_secret(), password.expose_secret());

                // Now test interactive overwrite
                config.length = 114;
                thread::spawn(move || {
                    let mut stdin = stdin_w;
                    stdin.write_all(b"n").unwrap();
                });
                let original_passwd = password;
                let password = generate_io(
                    &test_client,
                    &root,
                    "test1.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                let secret = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(password.expose_secret(), "");
                assert_eq!(secret.expose_secret(), original_passwd.expose_secret());

                let (mut stdin, stdin_w) = pipe().unwrap();
                thread::spawn(move || {
                    let mut stdin = stdin_w;
                    stdin.write_all(b"y").unwrap();
                });
                let password = generate_io(
                    &test_client,
                    &root,
                    "test1.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();
                let secret = test_client.decrypt_stdin(&root, "test1.gpg").unwrap();
                assert_eq!(secret.expose_secret(), password.expose_secret());
                assert_eq!(password.expose_secret().len(), 114);
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_inplace_generation() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let test_client = setup_test_client();
                let (mut stdin, _) = pipe().unwrap();
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

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
                    length: 12,
                };

                let password = generate_io(
                    &test_client,
                    &root,
                    "test2.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                let content = test_client.decrypt_stdin(&root, "test2.gpg").unwrap();
                let lines: Vec<&str> = content.expose_secret().lines().collect();
                assert_eq!(lines[0], password.expose_secret());
                assert_eq!(password.expose_secret().len(), 12);
                assert_eq!(lines[1], "password");
                assert_eq!(lines[2], "for super earth");
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_force_overwrite() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let test_client = setup_test_client();
                let (mut stdin, _) = pipe().unwrap();
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                test_client
                    .encrypt("old_password", path_to_str(&root.join("test3.gpg")).unwrap())
                    .unwrap();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: false,
                    force: true,
                    length: 8,
                };

                let password = generate_io(
                    &test_client,
                    &root,
                    "test3.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                assert_eq!(password.expose_secret().len(), 8);
                let content = test_client.decrypt_stdin(&root, "test3.gpg").unwrap();
                assert_eq!(content.expose_secret(), password.expose_secret());
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_no_symbols() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let test_client = setup_test_client();
                let (mut stdin, _) = pipe().unwrap();
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let config = PasswdGenerateConfig {
                    no_symbols: true,
                    in_place: false,
                    force: false,
                    length: 10,
                };

                let password = generate_io(
                    &test_client,
                    &root,
                    "test4.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                )
                .unwrap();

                assert!(!password.expose_secret().contains(|c: char| !c.is_alphanumeric()));
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_invalid_path() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let test_client = setup_test_client();
                let (mut stdin, _) = pipe().unwrap();
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: false,
                    force: false,
                    length: 16,
                };

                let result = generate_io(
                    &test_client,
                    &root,
                    "../outside.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                );

                assert!(result.is_err());
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_invalid_flag_combination() {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        cleanup!(
            {
                let test_client = setup_test_client();
                let (mut stdin, _) = pipe().unwrap();
                let mut stdout = stdout().lock();
                let mut stderr = stderr().lock();

                let config = PasswdGenerateConfig {
                    no_symbols: false,
                    in_place: true,
                    force: true,
                    length: 16,
                };

                let result = generate_io(
                    &test_client,
                    &root,
                    "test5.gpg",
                    &config,
                    &mut stdin,
                    &mut stdout,
                    &mut stderr,
                );

                assert!(result.is_err());
            },
            {
                cleanup_test_dir(&root);
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }
}
