use std::process::{Command, Stdio};

use anyhow::{anyhow, Error, Result};
use pars_core::config::cli::ParsConfig;

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_shell(
    config: &ParsConfig,
    base_dir: Option<&str>,
    args: &[String],
) -> Result<(), (i32, Error)> {
    if args.is_empty() {
        return Err((ParsExitCode::Error.into(), anyhow!("No command provided")));
    }

    let root = unwrap_root_path(base_dir, config);

    let command = &args[0];
    let command_args = &args[1..];

    let status = Command::new(command)
        .args(command_args)
        .current_dir(&root)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| (ParsExitCode::Error.into(), e.into()))?
        .wait()
        .map_err(|e| (ParsExitCode::Error.into(), e.into()))?;

    if status.success() {
        Ok(())
    } else {
        Err((
            ParsExitCode::Error.into(),
            anyhow!("Command failed with exit code {:?}", status.code()),
        ))
    }
}
