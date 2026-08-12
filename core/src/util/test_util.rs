use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::{env, fs};

use tempfile::env::temp_dir;
use tempfile::TempDir;

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

/// Deletes every secret+public key matching each email.
///
/// gpg refuses `--delete-secret-and-public-keys <email>` in batch mode ("can't do this in batch
/// mode ... unless you specify the key by fingerprint"), so each key is resolved to its primary
/// fingerprint first. The loop handles leftovers from earlier runs that share an email.
pub fn clean_up_test_key(
    executable: &str,
    emails: &[impl AsRef<str>],
) -> Result<(), Box<dyn std::error::Error>> {
    for email in emails {
        while let Ok((fingerprint, _, _)) = get_pgp_key_info(executable, email) {
            let delete_status = Command::new(executable)
                .args(["--batch", "--yes", "--delete-secret-and-public-keys", &fingerprint])
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()?;

            if !delete_status.success() {
                return Err("Failed to delete PGP key".into());
            }
        }
    }
    Ok(())
}

/// Batch script for an unattended RSA-2048 test key.
///
/// `passphrase` of `None` emits `%no-protection`, which is what tests that decrypt without a
/// pinentry need.
pub fn gpg_key_gen_batch(username: &str, email: &str, passphrase: Option<&str>) -> String {
    let protection = match passphrase {
        Some(passphrase) => format!("Passphrase: {passphrase}"),
        None => "%no-protection".to_string(),
    };
    format!(
        r#"%echo Generating a new key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: {username}
Name-Email: {email}
Expire-Date: 0
{protection}
%commit
%echo Key generation complete
"#
    )
}

pub fn gpg_key_gen_example_batch() -> String {
    gpg_key_gen_batch(&get_test_username(), &get_test_email(), Some(&get_test_password()))
}

/// RAII guard that deletes its key on drop, so a panicking test still cleans up after itself.
pub struct TestKeyGuard {
    executable: String,
    email: String,
}

impl TestKeyGuard {
    /// Generates an unprotected key for `email` and returns the guard that removes it.
    ///
    /// The guard is constructed *before* generation so a partially created key is still cleaned up
    /// if `key_gen_batch` itself fails.
    pub fn generate(executable: &str, username: &str, email: &str) -> Self {
        let guard = Self::adopt(executable, email);
        key_gen_batch(executable, &gpg_key_gen_batch(username, email, None)).unwrap();
        guard
    }

    /// Takes ownership of cleanup for a key this guard did not create.
    pub fn adopt(executable: &str, email: &str) -> Self {
        TestKeyGuard { executable: executable.to_string(), email: email.to_string() }
    }

    pub fn email(&self) -> &str {
        &self.email
    }
}

impl Drop for TestKeyGuard {
    fn drop(&mut self) {
        let _ = clean_up_test_key(&self.executable, &[&self.email]);
    }
}

pub fn gpg_key_edit_example_batch() -> String {
    r#"trust
5
save
"#
    .to_string()
}

pub fn gen_unique_temp_dir() -> (TempDir, PathBuf) {
    let base_dir = temp_dir().join("pass-rs-test");
    if !base_dir.exists() {
        let _ = fs::create_dir(&base_dir);
    }
    let dir = TempDir::new_in(base_dir).unwrap();
    let path = dir.path().to_path_buf();
    (dir, path)
}

pub fn create_dir_structure(base: &Path, structure: &[(Option<&str>, &[&str])]) {
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

pub fn write_gpg_id(path: &Path, gpg_id: &[&str]) {
    use std::io::Write;
    let mut file = fs::File::create(path.join(".gpg-id")).unwrap();
    for id in gpg_id {
        writeln!(file, "{id}").unwrap();
    }
}

/// PGP key material for import tests, in every supported encoding.
///
/// Generated at test time rather than checked in as binary fixtures: a committed blob would be
/// unreviewable in a diff and would pin one rPGP serialization forever.
pub struct PgpKeyMaterialFixture {
    pub fingerprint: String,
    pub identity: String,
    pub armored_public: Vec<u8>,
    pub armored_private: Vec<u8>,
    pub binary_public: Vec<u8>,
    pub binary_private: Vec<u8>,
}

impl PgpKeyMaterialFixture {
    /// Generates a key through the pure-Rust backend, optionally passphrase-protected.
    pub fn generate(passphrase: Option<&str>) -> Self {
        Self::generate_for("Fixture Example", "fixture@example.com", passphrase)
    }

    pub fn generate_for(name: &str, email: &str, passphrase: Option<&str>) -> Self {
        use secrecy::SecretString;

        use crate::config::cli::PgpBackendKind;
        use crate::pgp::backend::{KeyGenerationRequest, PgpBackend, PgpBackendConfig};
        use crate::pgp::import::pgp_key_material_to_binary;
        use crate::pgp::rpgp_backend::RpgpBackend;

        // A throwaway keyring: the fixture only needs the exported material, not a live backend.
        let keyring = tempfile::tempdir().expect("fixture keyring");
        let backend = RpgpBackend::from_config(&PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            keyring_home: Some(keyring.path().display().to_string()),
            ..Default::default()
        })
        .expect("fixture backend");

        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: name.to_string(),
                email: email.to_string(),
                passphrase: passphrase.map(SecretString::from),
            })
            .expect("generate fixture key");
        let fingerprint = generated.fingerprint;
        let identity =
            backend.inspect_fingerprint(&fingerprint).expect("inspect fixture key").identity;

        let armored_public = backend
            .export_public_key(&fingerprint)
            .expect("export public")
            .armored_text
            .into_bytes();
        let armored_private = backend
            .export_private_key(&fingerprint, None)
            .expect("export private")
            .armored_text
            .into_bytes();
        let binary_public =
            pgp_key_material_to_binary(&armored_public).expect("binary public fixture");
        let binary_private =
            pgp_key_material_to_binary(&armored_private).expect("binary private fixture");

        Self {
            fingerprint,
            identity,
            armored_public,
            armored_private,
            binary_public,
            binary_private,
        }
    }

    pub fn armored_public_text(&self) -> String {
        String::from_utf8(self.armored_public.clone()).expect("armored public key is utf8")
    }

    pub fn armored_private_text(&self) -> String {
        String::from_utf8(self.armored_private.clone()).expect("armored private key is utf8")
    }

    /// Writes one encoding to a file, for exercising the file import path.
    pub fn write_to(&self, path: &Path, material: &[u8]) {
        fs::write(path, material).expect("write key fixture");
    }
}

// Only the in-crate unit tests print through this; keep it out of the `test-util` feature build.
#[cfg(test)]
macro_rules! log_test {
    ($($arg:tt)*) => {
        #[cfg(test)]
        {
            println!($($arg)*);
        }
    };
}
#[cfg(test)]
pub(crate) use log_test;

use crate::pgp::key_management::key_gen_batch;
use crate::pgp::utils::get_pgp_key_info;
