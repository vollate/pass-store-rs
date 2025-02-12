use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::{env, fs};

pub fn get_test_username() -> String {
    env::var("PASS_RS_TEST_USERNAME").unwrap_or("rs-pass-test".into())
}

pub fn get_test_email() -> String {
    env::var("PASS_RS_TEST_EMAIL").unwrap_or("foo@rs.pass".into())
}

pub fn get_test_executable() -> String {
    env::var("PASS_RS_TEST_EXECUTABLE").unwrap_or("gpg".into())
}

pub fn get_test_password() -> String {
    env::var("PASS_RS_TEST_PASSWORD").unwrap_or("password".into())
}

use std::path::Path;

use tempfile::env::temp_dir;
use tempfile::TempDir;

use crate::pgp::utils::user_email_to_fingerprint;
pub fn clean_up_test_key(executable: &str, email: &str) -> Result<(), Box<dyn std::error::Error>> {
    loop {
        if let Ok(fingerprint) = user_email_to_fingerprint(executable, email) {
            let delete_status = Command::new(executable)
                .args(["--batch", "--yes", "--delete-secret-and-public-keys", &fingerprint])
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()?;

            if !delete_status.success() {
                return Err("Failed to delete PGP key".into());
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

pub(crate) fn gen_unique_temp_dir() -> (TempDir, PathBuf) {
    let base_dir = temp_dir().join("pass-rs-test");
    if !base_dir.exists() {
        let _ = fs::create_dir(&base_dir);
    }
    let dir = TempDir::new_in(base_dir).unwrap();
    let path = dir.path().to_path_buf();
    (dir, path)
}

pub(crate) fn create_dir_structure(base: &Path, structure: &[(Option<&str>, &[&str])]) {
    for (dir, files) in structure {
        let dir_path = match dir {
            Some(sub_dir) => base.join(sub_dir),
            None => base.to_path_buf(),
        };
        if !dir_path.exists() {
            fs::create_dir_all(&dir_path).unwrap();
        }
        for file in *files {
            fs::File::create(dir_path.join(file)).unwrap();
        }
    }
}

pub(crate) fn cleanup_test_dir(base: &Path) {
    let _ = fs::remove_dir_all(base);
}

macro_rules! log_test {
    ($($arg:tt)*) => {
        #[cfg(test)]
        {
            println!($($arg)*);
        }
    };
}
pub(crate) use log_test;
