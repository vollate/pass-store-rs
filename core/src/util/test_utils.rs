use std::env;
use std::process::{Command, Stdio};

pub fn get_test_email() -> String {
    env::var("PASS_RS_TEST_EMAIL").unwrap_or("foo@rs.pass".to_string())
}

pub fn get_test_executable() -> String {
    env::var("PASS_RS_TEST_EXECUTABLE").unwrap_or("gpg".to_string())
}

pub fn get_test_password() -> String {
    env::var("PASS_RS_TEST_PASSWORD").unwrap_or("password".to_string())
}

pub fn clean_up_test_key(executable: &str, email: &str) -> Result<(), Box<dyn std::error::Error>> {
    let output =
        Command::new(executable).arg("--list-keys").arg("--with-colons").arg(email).output()?;

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
            .args(&["--batch", "--yes", "--delete-secret-and-public-keys", &fingerprint])
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

pub fn gpg_key_gen_example_batch_input() -> Result<String, Box<dyn std::error::Error>> {
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
