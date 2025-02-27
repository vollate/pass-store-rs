use std::error::Error;
use std::io::Write;
use std::process::{Command, Stdio};

use crate::pgp::utils::wait_child_process;
use crate::pgp::PGPClient;

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
        return Err("Failed to open stdin for PGP key generation".into());
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
        Err(format!("Failed to generate PGP key, code {:?}", status).into())
    }
}

pub fn key_gen_stdin(pgp_exe: &str) -> Result<(), Box<dyn std::error::Error>> {
    let gpg_args = ["--gen-key"];
    run_gpg_inherited_child(pgp_exe, &gpg_args)
}

pub fn key_edit_stdin(pgp_exe: &str, key_fpr: &str) -> Result<(), Box<dyn Error>> {
    let gpg_args = ["--edit-key", key_fpr];
    run_gpg_inherited_child(pgp_exe, &gpg_args)
}
pub fn key_gen_batch(pgp_exe: &str, batch_input: &str) -> Result<(), Box<dyn Error>> {
    let gpg_args = ["--batch", "--gen-key"];
    run_gpg_batched_child(pgp_exe, &gpg_args, batch_input)
}

impl PGPClient {
    pub fn key_edit_batch(&self, batch_input: &str) -> Result<(), Box<dyn Error>> {
        for key in &self.keys {
            let gpg_args =
                ["--batch", "--command-fd", "0", "--status-fd", "1", "--edit-key", &key.key_fpr];
            run_gpg_batched_child(&self.executable, &gpg_args, batch_input)?;
        }
        Ok(())
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
    use crate::util::test_util::{
        clean_up_test_key, get_test_email, get_test_executable, gpg_key_edit_example_batch,
        gpg_key_gen_example_batch,
    };

    // #[test]
    // #[serial]
    // #[ignore = "need run interactively"]
    // fn test_gpg_key_gen_stdin() {
    //     let executable = get_test_executable();
    //     let mut pgp_client = PGPClient::new(executable, None, None, None);
    //     pgp_client.key_gen_stdin().unwrap();
    // }

    #[test]
    #[serial]
    fn pgp_key_gen_batch() {
        let executable = get_test_executable();
        key_gen_batch(&executable, &gpg_key_gen_example_batch()).unwrap();
        let pgp_client = PGPClient::new(executable, &vec![&get_test_email()]).unwrap();
        clean_up_test_key(pgp_client.get_executable(), &vec![&get_test_email()]).unwrap();
    }

    #[test]
    #[serial]
    fn pgp_key_edit_batch() {
        let executable = get_test_executable();
        let email = get_test_email();
        key_gen_batch(&executable, &gpg_key_gen_example_batch()).unwrap();
        let pgp_client = PGPClient::new(executable, &vec![&email]).unwrap();
        pgp_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
        clean_up_test_key(pgp_client.get_executable(), &vec![&email]).unwrap();
    }
}
