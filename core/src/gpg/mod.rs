pub mod crypto;
pub mod key_management;

use std::error::Error;
use std::fmt::{Display, Formatter, Pointer};

use crate::util::gpg_utils::{email_to_fingerprints, fingerprint_to_email};

pub struct GPGClient {
    executable: String,
    key_fpr: Option<String>,
    email: Option<String>,
}
impl GPGClient {
    pub fn new(executable: String, key_fpr: Option<String>, email: Option<String>) -> Self {
        let mut gpg_client = GPGClient { executable, key_fpr, email };
        let _ = gpg_client.update_info();
        gpg_client
    }
    pub fn get_executable(&self) -> &str {
        &self.executable
    }

    pub fn set_email(&mut self, email: String) -> Result<(), Box<dyn Error>> {
        self.email = Some(email);
        self.update_info()
    }
    fn update_info(&mut self) -> Result<(), Box<dyn Error>> {
        match (&self.key_fpr, &self.email) {
            (Some(_), Some(_)) => {}
            (Some(k), None) => {
                self.email = Some(fingerprint_to_email(&self.executable, k)?);
            }
            (None, Some(m)) => {
                self.key_fpr = Some(
                    email_to_fingerprints(&self.executable, m)?.pop().expect("Failed to get email"),
                );
            }
            (None, None) => {
                return Err("Either key_fpr or email need to be set".into());
            }
        }
        Ok(())
    }
}

#[derive(Debug)]
enum GPGErr {
    NoneFingerprint,
    CannotTakeStdin,
    CannotTakeStdout,
    CannotTakeStderr,
}

impl Display for GPGErr {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        use GPGErr::*;

        match self {
            NoneFingerprint => write!(f, "Key fingerprint is None"),
            CannotTakeStdin => write!(f, "Cannot take child's stdin"),
            CannotTakeStdout => write!(f, "Cannot take child's stdout"),
            CannotTakeStderr => write!(f, "Cannot take child's stderr"),
        }
    }
}

impl Error for GPGErr {}
