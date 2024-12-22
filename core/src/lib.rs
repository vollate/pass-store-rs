use std::error::Error;
use std::fmt::Display;
use crate::gpg::GPGErr;

mod bundle;
mod git;
mod gpg;
mod operation;
mod util;

#[derive(Debug)]
enum IOErr {
    InvalidPath,
    InvalidFileType,
    ExpectFile,
    ExpectDir,
}

impl Display for IOErr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        use IOErr::*;
        match self {
            InvalidPath => write!(f, "Invalid path"),
            InvalidFileType => write!(f, "Invalid file type"),
            ExpectFile => write!(f, "Expect path to be a file"),
            ExpectDir => write!(f, "Expect path to be a directory"),
        }
    }
}

impl Error for IOErr {}