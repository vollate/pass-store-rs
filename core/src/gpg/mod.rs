pub mod crypto;
pub mod key_management;
pub mod utils;

use std::error::Error;
use std::fmt::{Display, Formatter};

pub struct GPGClient {
    executable: String,
    // master key
    key_fpr: Option<String>,
    username: Option<String>,
    email: Option<String>,
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
