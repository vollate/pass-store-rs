use std::fmt::{self, Display, Formatter};
use std::path::Path;

pub enum CommitType {
    Init(Vec<String>),
    Generate(String),
    Update(String),
    Delete(String),
    Copy((String, String)),
    Rename((String, String)),
}

pub struct GitCommit<'a> {
    repo_base: &'a Path,
    commit_type: CommitType,
}

impl<'a> GitCommit<'a> {
    pub fn new(repo_base: &'a Path, commit_type: CommitType) -> Self {
        Self { repo_base, commit_type }
    }

    pub fn get_commit_msg(&self) -> String {
        match &self.commit_type {
            CommitType::Init(keys) => {
                let mut msg =
                    format!("Init password with {}", keys.first().unwrap_or(&"".to_string()));
                for key in keys[1..].iter() {
                    msg.push_str(&format!(", {}", key));
                }
                msg
            }
            CommitType::Generate(path) => format!("Generate password for {}", path),
            CommitType::Update(path) => format!("Update password for {}", path),
            CommitType::Delete(path) => format!("Delete password for {}", path),
            CommitType::Copy((src, dst)) => format!("Copy {} to {}", src, dst),
            CommitType::Rename((src, dst)) => format!("Rename {} to {}", src, dst),
        }
    }
}

impl Display for GitCommit<'_> {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        write!(f, "{} for repo {}", self.get_commit_msg(), self.repo_base.display())
    }
}
