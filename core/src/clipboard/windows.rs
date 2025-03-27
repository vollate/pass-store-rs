use std::process::{Command, Stdio};

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

const POWERSHELL_ARGS: [&str; 2] = ["-NoProfile", "-Command"];

pub(crate) fn copy_to_clip_board(mut secret: SecretString, timeout: Option<usize>) -> Result<()> {
    let encoded = STANDARD.encode(secret.expose_secret().as_bytes());
    secret.zeroize();
    let mut cmd = Command::new("powershell");
    let mut child = cmd
        .args(POWERSHELL_ARGS)
        .arg(format!(
            "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{}')) | Set-Clipboard",
            encoded
        ))
        .spawn()?;

    let exit_status = child.wait()?;
    if !exit_status.success() {
        return Err(anyhow!(format!("Windows Set-Clipboard exit failed: {}", exit_status)));
    }

    if let Some(secs) = timeout {
        let cmd =
            format!("Start-Sleep -Seconds {} ; [Windows.ApplicationModel.DataTransfer.Clipboard, Windows, ContentType = WindowsRuntime]::ClearHistory()", secs);
        let _ = Command::new("powershell")
            .args(POWERSHELL_ARGS)
            .arg(&cmd)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::thread;
    use std::time::Duration;

    use pretty_assertions::assert_eq;

    use super::*;

    #[test]
    fn windows_clipboard_test() {
        thread::sleep(Duration::from_secs(3));

        const TIMEOUT: usize = 1;
        let content = SecretString::new("Hello, pars".into());
        let res = copy_to_clip_board(content, Some(TIMEOUT));
        assert!(res.is_ok());

        let cmd = Command::new("powershell").arg("-Command").arg("Get-Clipboard").output().unwrap();
        assert_eq!(cmd.stdout, b"Hello, pars\r\n");
        assert_eq!(cmd.status.success(), true);

        thread::sleep(Duration::from_secs(3 + TIMEOUT as u64));
        let cmd = Command::new("powershell").arg("-Command").arg("Get-Clipboard").output().unwrap();
        assert_eq!(cmd.stdout, b"");
    }
}
