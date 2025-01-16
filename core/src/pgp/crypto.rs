use std::error::Error;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

use super::{PGPClient, PGPErr};
impl PGPClient {
    pub fn encrypt(
        &self,
        plaintext: &str,
        output_path: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let mut child = Command::new(&self.executable)
            .args(&[
                "--batch",
                "--encrypt",
                "--recipient",
                self.get_key_fpr().ok_or_else(|| PGPErr::NoneFingerprint)?,
                "--output",
                output_path,
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(plaintext.as_bytes())?;
        }

        let status = child.wait()?;
        if status.success() {
            println!("File encrypted successfully: {}", output_path); //TODO: remove
            Ok(())
        } else {
            Err("PGP encryption failed".into())
        }
    }

    pub fn decrypt_stdin(&self, file_path: &str) -> Result<SecretString, Box<dyn Error>> {
        let output = Command::new(&self.executable)
            .args(&[
                "--decrypt",
                "--recipient",
                self.key_fpr.as_ref().ok_or_else(|| PGPErr::NoneFingerprint)?,
                file_path,
            ])
            .output()?;

        if output.status.success() {
            Ok(String::from_utf8(output.stdout)?.into())
        } else {
            let error_message = String::from_utf8_lossy(&output.stderr);
            Err(format!("PGP decryption failed: {}", error_message).into())
        }
    }

    pub fn decrypt_with_password(
        &self,
        file_path: &str,
        mut passwd: SecretString,
    ) -> Result<SecretString, Box<dyn Error>> {
        let mut cmd = Command::new(&self.executable)
            //TODO: match each version
            .args(&[
                "--batch",         // this is required after 2.0
                "--pinentry-mode", //this is required after 2.1
                "loopback",
                "--decrypt",
                "--passphrase-fd",
                "0",
                "--recipient",
                self.key_fpr.as_ref().ok_or_else(|| PGPErr::NoneFingerprint)?,
                file_path,
            ])
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
            Err(format!("PGP decryption failed: {}", error_message).into())
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
    use crate::util::test_utils::{
        clean_up_test_key, defer_cleanup, get_test_email, get_test_executable, get_test_password,
        get_test_username, gpg_key_edit_example_batch, gpg_key_gen_example_batch,
    };
    #[test]
    #[serial]

    fn test_encrypt_with_key() {
        let executable = &get_test_executable();
        let email = &get_test_email();
        let plaintext = "Hello, world!\nThis is a test message.";
        let output_dest = "encrypt.gpg";
        defer_cleanup!(
            {
                let mut test_client = PGPClient::new(
                    executable.to_string(),
                    None,
                    Some(get_test_username()),
                    Some(email.to_string()),
                );
                test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
                test_client.update_info().unwrap();

                test_client.encrypt(plaintext, output_dest).unwrap();

                if !Path::new(output_dest).exists() {
                    panic!("Encrypted file not found");
                }
                let _ = fs::remove_file(output_dest);
            },
            {
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_decrypt_file_interact() {
        let executable = &get_test_executable();
        let email = &get_test_email();
        let plaintext = "Hello, world!\nThis is a test message.\n";
        let output_dest = "decrypt.gpg";
        let _ = fs::remove_file(output_dest);
        defer_cleanup!(
            {
                let mut test_client = PGPClient::new(
                    executable.to_string(),
                    None,
                    Some(get_test_username()),
                    Some(email.to_string()),
                );
                test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
                test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
                test_client.update_info().unwrap();

                test_client.encrypt(plaintext, output_dest).unwrap();
                let decrypted = test_client.decrypt_stdin(output_dest).unwrap();
                assert_eq!(decrypted.expose_secret(), plaintext);
                fs::remove_file(output_dest).unwrap();
            },
            {
                clean_up_test_key(executable, email).unwrap();
            }
        )
    }
    #[test]
    #[serial]
    fn test_decrypt_file() {
        let plaintext = "Hello, world!\nThis is a test message.\n";
        let output_dest = "decrypt.gpg";

        let _ = fs::remove_file(output_dest);

        defer_cleanup!(
            {
                let mut test_client = PGPClient::new(
                    get_test_executable(),
                    None,
                    Some(get_test_username()),
                    Some(get_test_email()),
                );
                test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
                test_client.update_info().unwrap();
                test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
                test_client.encrypt(plaintext, output_dest).unwrap();
                let decrypted = test_client
                    .decrypt_with_password(output_dest, get_test_password().into())
                    .unwrap();
                assert_eq!(decrypted.expose_secret(), plaintext);

                fs::remove_file(output_dest).unwrap();
            },
            {
                clean_up_test_key(&get_test_executable(), &get_test_email()).unwrap();
            }
        )
    }
}
