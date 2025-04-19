use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{anyhow, Result};
use log::debug;
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

use super::{PGPClient, PGPErr};
impl PGPClient {
    pub fn encrypt(&self, plaintext: &str, output_path: &str) -> Result<()> {
        let fprs = self.get_keys_fpr();
        let prefix = vec!["--batch", "--encrypt"];
        let mut args = Vec::with_capacity(prefix.len() + fprs.len() * 2 + 2);
        args.extend(prefix);
        fprs.into_iter().for_each(|fpr| {
            args.push("--recipient");
            args.push(fpr);
        });
        args.push("--output");
        args.push(output_path);
        let mut child = Command::new(&self.executable)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(plaintext.as_bytes())?;
        }

        let status = child.wait()?;
        if status.success() {
            debug!("File encrypted successfully: {}", output_path);
            Ok(())
        } else {
            let mut buffer = String::new();
            let err_msg = match child.stderr.take() {
                Some(mut err) => {
                    let _ = err.read_to_string(&mut buffer);
                    buffer
                }
                None => String::new(),
            };
            Err(anyhow!(format!("PGP encryption failed: {}", err_msg)))
        }
    }

    pub fn decrypt_stdin(&self, work_dir: &Path, file_path: &str) -> Result<SecretString> {
        let mut args = Vec::with_capacity(1 + 2 * self.keys.len() + 1);
        args.push("--decrypt");
        for key in &self.keys {
            args.push("--recipient");
            args.push(&key.key_fpr);
        }
        args.push(file_path);
        let output = Command::new(&self.executable).current_dir(work_dir).args(&args).output()?;

        if output.status.success() {
            Ok(String::from_utf8(output.stdout)?.into())
        } else {
            let error_message = String::from_utf8_lossy(&output.stderr);
            Err(anyhow!(format!("PGP decryption failed: {}", error_message)))
        }
    }

    pub fn decrypt_with_password(
        &self,
        file_path: &str,
        mut passwd: SecretString,
    ) -> Result<SecretString> {
        //TODO: match each version
        let prefix = vec![
            "--batch",         // this is required after gnupg 2.0
            "--pinentry-mode", //this is required after gnupg 2.1
            "loopback",
            "--decrypt",
            "--passphrase-fd",
            "0",
        ];
        let mut args = Vec::with_capacity(prefix.len() + 2 * self.keys.len() + 1);
        args.extend(prefix);
        for key in &self.keys {
            args.push("--recipient");
            args.push(&key.key_fpr);
        }
        args.push(file_path);
        let mut cmd = Command::new(&self.executable)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        if let Some(mut input) = cmd.stdin.take() {
            input.write_all(passwd.expose_secret().as_bytes())?;
            input.flush()?;
            passwd.zeroize();
        } else {
            return Err(PGPErr::CannotTakeStdin.into());
        }
        let output = cmd.wait_with_output()?;

        if output.status.success() {
            Ok(String::from_utf8(output.stdout)?.into())
        } else {
            let error_message = String::from_utf8_lossy(&output.stderr);
            Err(anyhow!(format!("PGP decryption failed: {}", error_message)))
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;

    use pretty_assertions::assert_eq;
    use serial_test::serial;

    use super::*;
    use crate::pgp::key_management::key_gen_batch;
    use crate::util::defer::cleanup;
    use crate::util::test_util::{
        clean_up_test_key, get_test_email, get_test_executable, get_test_password,
        gpg_key_edit_example_batch, gpg_key_gen_example_batch,
    };

    #[test]
    #[serial]
    fn encrypt_with_key() {
        let executable = &get_test_executable();
        let email = &get_test_email();
        let plaintext = "Hello, world!\nThis is a test message.";
        let output_dest = "encrypt.gpg";
        cleanup!(
            {
                key_gen_batch(executable, &gpg_key_gen_example_batch()).unwrap();
                let test_client = PGPClient::new(executable, &vec![email]).unwrap();
                test_client.encrypt(plaintext, output_dest).unwrap();

                if !Path::new(output_dest).exists() {
                    panic!("Encrypted file not found");
                }
            },
            {
                let _ = fs::remove_file(output_dest);
                clean_up_test_key(executable, &vec![email]).unwrap();
            }
        );
    }

    // #[test]
    // #[serial]
    // #[ignore = "need run interactively"]
    // fn decrypt_file_interact() {
    //     let executable = &get_test_executable();
    //     let email = &get_test_email();
    //     let plaintext = "Hello, world!\nThis is a test message.\n";
    //     let (_tmp_dir, root) = gen_unique_temp_dir();
    //     let output_dest = "decrypt.gpg";
    //
    //     cleanup!(
    //         {
    //             let mut test_client = PGPClient::new(
    //                 executable.to_string(),
    //                 None,
    //                 Some(get_test_username()),
    //                 Some(email.to_string()),
    //             );
    //             test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
    //             test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
    //             test_client.update_info().unwrap();
    //
    //             test_client.encrypt(plaintext, output_dest).unwrap();
    //             let decrypted = test_client.decrypt_stdin(&root, output_dest).unwrap();
    //             assert_eq!(decrypted.expose_secret(), plaintext);
    //             fs::remove_file(output_dest).unwrap();
    //         },
    //         {
    //             clean_up_test_key(executable, email).unwrap();
    //         }
    //     )
    // }

    #[test]
    #[serial]
    fn decrypt_file() {
        let plaintext = "Hello, world!\nThis is a test message.\n";
        let output_dest = "decrypt.gpg";

        let _ = fs::remove_file(output_dest);

        cleanup!(
            {
                key_gen_batch(&get_test_executable(), &gpg_key_gen_example_batch()).unwrap();
                let test_client =
                    PGPClient::new(get_test_executable(), &vec![&get_test_email()]).unwrap();
                test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
                test_client.encrypt(plaintext, output_dest).unwrap();
                let decrypted = test_client
                    .decrypt_with_password(output_dest, get_test_password().into())
                    .unwrap();
                assert_eq!(decrypted.expose_secret(), plaintext);
            },
            {
                fs::remove_file(output_dest).unwrap();
                clean_up_test_key(&get_test_executable(), &vec![&get_test_email()]).unwrap();
            }
        )
    }
}
