use std::error::Error;
use std::path::Path;
use std::process::{Command, Stdio};

pub fn git_io(executable: &str, work_dir: &Path, args: &[&str]) -> Result<(), Box<dyn Error>> {
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
        Err(format!("Failed to run git command, code {:?}", status).into())
    }
}
