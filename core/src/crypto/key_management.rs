use std::error::Error;
use std::io::Write;
use std::process::{Command, Stdio};
pub fn gpg_key_generate(
    executable: &str,
    input_func: impl FnOnce() -> Result<String, Box<dyn Error>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let status = Command::new(executable)
        .arg("--gen-key")
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()?;

    if status.success() {
        return Ok(());
    }

    let gpg_args = ["--batch", "--gen-key"];

    let mut cmd = Command::new(executable)
        .args(&gpg_args)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()?;

    if let Some(mut stdin) = cmd.stdin.take() {
        let batch_content = input_func()?;
        stdin.write_all(batch_content.as_bytes())?;
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
    use crate::util::test_utils::get_test_password;
    use crate::util::test_utils::{get_test_email, get_test_executable};

    use super::*;
    use std::env;
    use std::fs::write;
    use std::io::stdin;
    use std::process::Command;

    fn example_batch_input() -> Result<String, Box<dyn std::error::Error>> {
        Ok(format!(
            r#"
%echo Generating a new key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Test User
Name-Email: {}
Expire-Date: 0
Passphrase: {}
%commit
%echo Key generation complete
"#,
            get_test_email(),
            get_test_password()
        ))
    }

    use std::process::Stdio;

    pub fn clean_up_test_key(
        executable: &str,
        email: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let output = Command::new(executable)
            .arg("--list-keys")
            .arg("--with-colons")
            .arg(email)
            .output()?;

        if !output.status.success() {
            return Ok(());
        }

        let output_str = String::from_utf8(output.stdout)?;
        let mut fingerprints = Vec::new();
        let mut found_target = false;

        for line in output_str.lines() {
            if line.starts_with("uid") && line.contains(email) {
                found_target = true;
            } else if line.starts_with("fpr") && found_target {
                if let Some(fingerprint) = line.split(':').nth(9) {
                    fingerprints.push(fingerprint.to_string());
                }
                found_target = false;
            }
        }

        for fingerprint in fingerprints {
            let delete_status = Command::new(executable)
                .args(&[
                    "--batch",
                    "--yes",
                    "--delete-secret-and-public-keys",
                    &fingerprint,
                ])
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()?;

            if !delete_status.success() {
                return Err("Failed to delete GPG key".into());
            }
        }

        Ok(())
    }

    #[test]
    fn test_gpg_key_generation() {
        let executable = get_test_executable();
        gpg_key_generate(&executable, example_batch_input).unwrap();
        clean_up_test_key(&executable, &get_test_email()).unwrap();
    }
}
