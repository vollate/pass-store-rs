use std::error::Error;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

use crate::gpg::utils::wait_child_process;
use crate::gpg::{GPGClient, GPGErr};

fn run_gpg_batched_child(
    executable: &str,
    args: &[&str],
    batch_input: &str,
) -> Result<(), Box<dyn Error>> {
    let mut cmd = Command::new(executable)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()?;
    if let Some(mut input) = cmd.stdin.take() {
        input.write_all(batch_input.as_bytes())?;
        input.flush()?;
    } else {
        return Err("Failed to open stdin for GPG key generation".into());
    }
    wait_child_process(&mut cmd)
}

fn run_gpg_inherited_child(executable: &str, args: &[&str]) -> Result<(), Box<dyn Error>> {
    let status = Command::new(executable)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("Failed to generate GPG key, code {:?}", status).into())
    }
}

impl GPGClient {
    pub fn key_gen_stdin(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let gpg_args = ["--gen-key"];
        run_gpg_inherited_child(&self.executable, &gpg_args)
    }

    pub fn key_edit_stdin(&self) -> Result<(), Box<dyn Error>> {
        let gpg_args =
            ["--edit-key", self.key_fpr.as_ref().ok_or_else(|| GPGErr::NoneFingerprint)?];
        run_gpg_inherited_child(&self.executable, &gpg_args)
    }

    pub fn key_gen_batch(&mut self, batch_input: &str) -> Result<(), Box<dyn Error>> {
        let gpg_args = ["--batch", "--gen-key"];
        run_gpg_batched_child(&self.executable, &gpg_args, batch_input)
    }

    pub fn key_edit_batch(&self, batch_input: &str) -> Result<(), Box<dyn Error>> {
        let gpg_args = [
            "--batch",
            "--command-fd",
            "0",
            "--status-fd",
            "1",
            "--edit-key",
            self.key_fpr.as_ref().ok_or_else(|| GPGErr::NoneFingerprint)?,
        ];
        run_gpg_batched_child(&self.executable, &gpg_args, batch_input)
    }

    pub fn list_key_fingerprints(&self) -> Result<Vec<String>, Box<dyn Error>> {
        todo!("impl this")
    }

    pub fn list_all_user_emails(&self) -> Result<Vec<String>, Box<dyn Error>> {
        todo!("impl this")
    }
}
#[cfg(test)]
mod tests {

    use serial_test::serial;

    use super::*;
    use crate::util::test_utils::{
        clean_up_test_key, get_test_email, get_test_executable, get_test_username,
        gpg_key_edit_example_batch, gpg_key_gen_example_batch,
    };

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_gpg_key_gen_stdin() {
        let executable = get_test_executable();
        let mut gpg_client = GPGClient::new(executable, None, None, None);
        gpg_client.key_gen_stdin().unwrap();
    }

    #[test]
    #[serial]
    fn test_gpg_key_gen_batch() {
        let executable = get_test_executable();
        let mut gpg_client =
            GPGClient::new(executable, None, Some(get_test_username()), Some(get_test_email()));
        gpg_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        clean_up_test_key(gpg_client.get_executable(), &get_test_email()).unwrap();
    }

    #[test]
    #[serial]
    fn test_gpg_key_edit_batch() {
        let executable = get_test_executable();
        let mut gpg_client =
            GPGClient::new(executable, None, Some(get_test_username()), Some(get_test_email()));
        gpg_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        gpg_client.update_info().unwrap();
        gpg_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        clean_up_test_key(gpg_client.get_executable(), &get_test_email()).unwrap();
    }
}
