use std::error::Error;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

use crate::gpg::{GPGClient, GPGErr};

impl GPGClient {
    pub fn gpg_key_gen_stdin(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let status = Command::new(&self.executable)
            .arg("--gen-key")
            .stdin(Stdio::piped())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()?;

        if status.success() {
            self.update_info()?;
            return Ok(());
        } else {
            return Err(format!("Failed to generate GPG key, code {:?}", status).into());
        }
    }

    pub fn gpg_key_edit_stdin(&self, batch_content: &str) -> Result<(), Box<dyn Error>> {
        let gpg_args =
            ["--edit-key", self.key_fpr.as_ref().ok_or_else(|| GPGErr::NoneFingerprint)?];

        let mut cmd = Command::new(&self.executable)
            .args(&gpg_args)
            .stdin(Stdio::piped())
            .stdout(Stdio::inherit())
            .stderr(Stdio::piped())
            .spawn()?;
        if let Some(mut input) = cmd.stdin.take() {
            input.write_all(batch_content.as_bytes())?;
            input.flush()?;
        } else {
            return Err("Failed to open stdin for GPG key edit".into());
        }
        let status = cmd.wait()?;
        if status.success() {
            Ok(())
        } else {
            let err_msg = match cmd.stderr.take() {
                Some(mut stderr) => {
                    let mut buf = String::new();
                    stderr.read_to_string(&mut buf)?;
                    buf
                }
                None => "Failed to read stderr".to_string(),
            };
            Err(format!("Failed to edit GPG key, code: {:?}\nError: {}", status, err_msg).into())
        }
    }
    pub fn gpg_key_gen_batch(&mut self, batch_content: &str) -> Result<(), Box<dyn Error>> {
        let gpg_args = ["--batch", "--gen-key"];

        let mut cmd = Command::new(&self.executable)
            .args(&gpg_args)
            .stdin(Stdio::piped())
            .stdout(Stdio::inherit())
            .stderr(Stdio::piped())
            .spawn()?;
        if let Some(mut input) = cmd.stdin.take() {
            input.write_all(batch_content.as_bytes())?;
            input.flush()?;
        } else {
            return Err("Failed to open stdin for GPG key generation".into());
        }
        let status = cmd.wait()?;
        if status.success() {
            self.update_info()?;
            Ok(())
        } else {
            let err_msg = match cmd.stderr.take() {
                Some(mut stderr) => {
                    let mut buf = String::new();
                    stderr.read_to_string(&mut buf)?;
                    buf
                }
                None => "Failed to read stderr".to_string(),
            };
            Err(format!("Failed to generate GPG key, code: {:?}\nError: {}", status, err_msg)
                .into())
        }
    }
    pub fn gpg_key_edit_batch(&self, batch_content: &str) -> Result<(), Box<dyn Error>> {
        let gpg_args = [
            "--batch",
            "--command-fd",
            "0",
            "--status-fd",
            "1",
            "--edit-key",
            self.key_fpr.as_ref().ok_or_else(|| GPGErr::NoneFingerprint)?,
        ];

        let mut cmd = Command::new(&self.executable)
            .args(&gpg_args)
            .stdin(Stdio::piped())
            .stdout(Stdio::inherit())
            .stderr(Stdio::piped())
            .spawn()?;
        if let Some(mut input) = cmd.stdin.take() {
            input.write_all(batch_content.as_bytes())?;
        } else {
            return Err("Failed to open stdin for GPG key edit".into());
        }
        let status = cmd.wait()?;
        if status.success() {
            Ok(())
        } else {
            let err_msg = match cmd.stderr.take() {
                Some(mut stderr) => {
                    let mut buf = String::new();
                    stderr.read_to_string(&mut buf)?;
                    buf
                }
                None => "Failed to read stderr".to_string(),
            };
            Err(format!("Failed to edit GPG key, code: {:?}\nError: {}", status, err_msg).into())
        }
    }
}
#[cfg(test)]
mod tests {
    use serial_test::serial;

    use super::*;
    use crate::util::test_utils::{
        clean_up_test_key, get_test_email, get_test_executable, get_test_password,
        gpg_key_edit_example_batch, gpg_key_gen_example_batch,
    };

    #[test]
    #[serial]
    #[ignore = "cannot run automatically"]
    fn test_gpg_key_gen_stdin() {
        let executable = get_test_executable();
        let mut gpg_client = GPGClient::new(executable, None, None);
        gpg_client.gpg_key_gen_stdin().unwrap();
    }

    #[test]
    #[serial]
    fn test_gpg_key_gen_batch() {
        let executable = get_test_executable();
        let mut gpg_client = GPGClient::new(executable, None, Some(get_test_email()));
        gpg_client.gpg_key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        clean_up_test_key(gpg_client.get_executable(), &get_test_email()).unwrap();
    }

    #[test]
    #[serial]
    fn test_gpg_key_edit_batch() {
        let executable = get_test_executable();
        let mut gpg_client = GPGClient::new(executable, None, Some(get_test_email()));
        gpg_client.gpg_key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        gpg_client.gpg_key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        clean_up_test_key(gpg_client.get_executable(), &get_test_email()).unwrap();
    }
}
