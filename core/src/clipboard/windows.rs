use std::process::Command;

use anyhow::{anyhow, Result};
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

pub(crate) fn copy_to_clip_board(mut secret: SecretString, timeout: Option<usize>) -> Result<()> {
    let mut cmd = Command::new("powershell");
    let mut child = cmd
        .arg("-Command")
        .arg("Set-Clipboard")
        .arg(format!("\"{}\"", secret.expose_secret()))
        .spawn()?;
    secret.zeroize();

    let exit_status = child.wait()?;
    if !exit_status.success() {
        return Err(anyhow!(format!("wl-copy exit failed: {}", exit_status)));
    }

    if let Some(secs) = timeout {
        let cmd =
            format!("Start-Sleep -Seconds {} ; [Windows.ApplicationModel.DataTransfer.Clipboard, Windows, ContentType = WindowsRuntime]::ClearHistory()", secs);
        Command::new("powershell").arg("-Command").arg(&cmd).spawn()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;

    #[test]
    fn windows_clipboard_test() {
        const TIMEOUT: usize = 1;
        let content = SecretString::new("Hello, pars".into());
        let res = copy_to_clip_board(content, Some(TIMEOUT));
        assert!(res.is_ok());

        let cmd = Command::new("pwsh").arg("-Command").arg("Get-Clipboard").output().unwrap();
        assert_eq!(cmd.stdout, b"Hello, pars\r\n");
        assert_eq!(cmd.status.success(), true);

        std::thread::sleep(std::time::Duration::from_secs(1 + TIMEOUT as u64));
        let cmd = Command::new("pwsh").arg("-Command").arg("Get-Clipboard").output().unwrap();
        assert_eq!(cmd.stdout, b"\r\n");
    }
}
