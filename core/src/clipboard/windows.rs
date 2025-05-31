use std::process::{Command, Stdio};

use anyhow::{anyhow, Result};
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

use crate::util::str::fit_to_powershell;

const POWERSHELL_ARGS: [&str; 2] = ["-NoProfile", "-Command"];

pub(crate) fn copy_to_clip_board(mut secret: SecretString, timeout: &Option<usize>) -> Result<()> {
    let mut child = Command::new("powershell")
        .args(POWERSHELL_ARGS)
        .arg(format!(r#"Set-Clipboard -Value "{}""#, fit_to_powershell(secret.expose_secret())))
        .spawn()?;
    secret.zeroize();

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
    #[ignore = "unstable in CI environment"]
    fn windows_clipboard_test() {
        const EXAMPLE_CLIPBOARD_CONTENT: [&str; 7] = [
            r#"*asterisk*"#,
            r#"`backtick`"#,
            r#"$dollar$"#,
            r#"'single_quote'"#,
            r#""double_quote""#,
            r#"\backslash\"#,
            r#"~!@#$%^&*()_+-={}[]|:;<>?,./"#,
        ];

        for secret in EXAMPLE_CLIPBOARD_CONTENT {
            const TIMEOUT: usize = 1;
            let content = SecretString::new(secret.into());
            let res = copy_to_clip_board(content, &Some(TIMEOUT));
            assert!(res.is_ok());

            let cmd =
                Command::new("powershell").arg("-Command").arg("Get-Clipboard").output().unwrap();
            let out_str = String::from_utf8_lossy(&cmd.stdout).to_string();
            assert_eq!(out_str.lines().next().unwrap(), secret);
            assert_eq!(cmd.status.success(), true);

            thread::sleep(Duration::from_secs(1 + TIMEOUT as u64));
            let cmd =
                Command::new("powershell").arg("-Command").arg("Get-Clipboard").output().unwrap();
            assert_eq!(cmd.stdout, b"");
        }
    }
}
