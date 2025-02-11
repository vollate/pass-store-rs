#![allow(dead_code)]
use std::error::Error;
use std::fmt::Display;
use std::path::Path;

mod util;

mod bundle;
mod clipboard;
mod config;
mod git;
mod operation;
mod pgp;

#[derive(Debug)]
enum IOErrType {
    PathNotExist,
    InvalidPath,
    InvalidName,
    CannotGetFileName,
    InvalidFileType,
    ExpectFile,
    ExpectDir,
}
#[derive(Debug)]
struct IOErr {
    err_type: IOErrType,
    path: Box<Path>,
}

impl IOErr {
    pub fn new(err_type: IOErrType, path: &Path) -> Self {
        Self { err_type, path: Box::from(path.to_path_buf()) }
    }
}

impl Display for IOErr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        use IOErrType::*;
        match self.err_type {
            PathNotExist => write!(f, "Path not exist: {:?}", self.path),
            CannotGetFileName => write!(f, "Cannot get file name: {:?}", self.path),
            InvalidPath => write!(f, "Invalid path: {:?}", self.path),
            InvalidName => write!(f, "Invalid name: {:?}", self.path),
            InvalidFileType => write!(f, "Invalid file type: {:?}", self.path),
            ExpectFile => write!(f, "Expect to be a file: {:?}", self.path),
            ExpectDir => write!(f, "Expect to be a directory: {:?}", self.path),
        }
    }
}

impl Error for IOErr {}
