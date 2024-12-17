use std::error::Error;
use std::io::Write;
use std::process::{Command, Stdio};

pub fn gpg_key_gen_stdin(executable: &str) -> Result<(), Box<dyn std::error::Error>> {
    let status = Command::new(executable)
        .arg("--gen-key")
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()?;

    if status.success() {
        return Ok(());
    } else {
        return Err(format!("Failed to generate GPG key: {:?}", status).into());
    }
}

pub fn gpg_key_gen_batch(
    executable: &str,
    batch_content: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let gpg_args = ["--batch", "--gen-key"];

    let mut cmd = Command::new(executable)
        .args(&gpg_args)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()?;
    if let Some(mut input) = cmd.stdin.take() {
        input.write_all(batch_content.as_bytes())?;
        input.flush()?;
    } else {
        return Err("Failed to open stdin for GPG key generation".into());
    }
    let status = cmd.wait()?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("Failed to generate GPG key: {:?}", status).into())
    }
}

#[cfg(test)]
mod tests {

    use serial_test::serial;

    use super::*;
    use crate::util::test_utils::{
        clean_up_test_key, get_test_email, get_test_executable, get_test_password,
        gpg_key_gen_example_batch_input,
    };

    #[test]
    #[ignore = "cannot run automatically"]
    fn test_gpg_key_gen_stdin() {
        let executable = get_test_executable();
        gpg_key_gen_stdin(&executable).unwrap();
    }

    #[test]
    #[serial]
    fn test_gpg_key_gen_call_back() {
        let executable = get_test_executable();
        gpg_key_gen_batch(&executable, &gpg_key_gen_example_batch_input().unwrap()).unwrap();
        clean_up_test_key(&executable, &get_test_email()).unwrap();
    }
}
