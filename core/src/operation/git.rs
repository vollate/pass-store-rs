use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{Error, Result};

pub fn git_io(executable: &str, work_dir: &Path, args: &[&str]) -> Result<()> {
    let status = Command::new(executable)
        .args(args)
        .current_dir(work_dir)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()?
        .wait()?;

    if status.success() {
        Ok(())
    } else {
        Err(Error::msg(format!("Failed to run git command, code {:?}", status)))
    }
}
