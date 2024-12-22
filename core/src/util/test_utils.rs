use std::env;
use std::process::{Command, Stdio};

pub fn get_test_username() -> String {
    env::var("PASS_RS_TEST_USERNAME").unwrap_or_else(|_| "rs-pass-test".into())
}
pub fn get_test_email() -> String {
    env::var("PASS_RS_TEST_EMAIL").unwrap_or("foo@rs.pass".to_string())
}

pub fn get_test_executable() -> String {
    env::var("PASS_RS_TEST_EXECUTABLE").unwrap_or("gpg".to_string())
}

pub fn get_test_password() -> String {
    env::var("PASS_RS_TEST_PASSWORD").unwrap_or("password".to_string())
}

use rand::{thread_rng, Rng};

use crate::gpg::utils::user_email_to_fingerprint;
pub fn clean_up_test_key(executable: &str, email: &str) -> Result<(), Box<dyn std::error::Error>> {
    loop {
        if let Ok(fingerprint) = user_email_to_fingerprint(executable, email) {
            let delete_status = Command::new(executable)
                .args(&["--batch", "--yes", "--delete-secret-and-public-keys", &fingerprint])
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()?;

            if !delete_status.success() {
                return Err("Failed to delete GPG key".into());
            }
        } else {
            return Ok(());
        }
    }
}

pub fn gpg_key_gen_example_batch() -> String {
    format!(
        r#"%echo Generating a new key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: {}
Name-Email: {}
Expire-Date: 0
Passphrase: {}
%commit
%echo Key generation complete
"#,
        get_test_username(),
        get_test_email(),
        get_test_password()
    )
}

pub fn gpg_key_edit_example_batch() -> String {
    r#"trust
5
save
"#
    .to_string()
}

pub fn gen_unique_temp_dir() -> std::path::PathBuf {
    loop {
        let path =
            std::env::temp_dir().join("pass_rs_test").join(thread_rng().gen::<u64>().to_string());
        if !path.exists() {
            return path;
        }
    }
}
