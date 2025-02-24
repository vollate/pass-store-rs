pub mod crypto;
pub mod key_management;
pub mod utils;

use std::error::Error;
use std::fmt::{Display, Formatter};

pub struct PGPKey {
    key_fpr: String,
    username: String,
    email: String,
}
pub struct PGPClient {
    executable: String,
    keys: Vec<PGPKey>,
}

#[derive(Debug)]
pub enum PGPErr {
    NoneFingerprint,
    NoneUsername,
    NoneEmail,
    CannotTakeStdin,
    CannotTakeStdout,
    CannotTakeStderr,
}

impl Display for PGPErr {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        use PGPErr::*;

        match self {
            NoneFingerprint => write!(f, "Key fingerprint is None"),
            NoneUsername => write!(f, "Username is None"),
            NoneEmail => write!(f, "Email is None"),
            CannotTakeStdin => write!(f, "Cannot take child's stdin"),
            CannotTakeStdout => write!(f, "Cannot take child's stdout"),
            CannotTakeStderr => write!(f, "Cannot take child's stderr"),
        }
    }
}

impl Error for PGPErr {}
