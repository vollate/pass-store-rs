use std::io::Write;
use std::process::Command;

use anyhow::{anyhow, Error, Result};
use log::warn;
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

use crate::constants::default_constants::WAYLAND_COPY_EXECUTABLE;
use crate::util::str::fit_to_unix;

pub(crate) fn copy_to_clip_board(mut secret: SecretString, timeout: Option<usize>) -> Result<()> {
    let mut cmd = Command::new(WAYLAND_COPY_EXECUTABLE);
    cmd.arg("-n");

    let mut child = cmd.stdin(std::process::Stdio::piped()).spawn()?;

    let child_stdin = child.stdin.as_mut().ok_or(anyhow!("Cannot get stdin for 'wl-copy'"))?;
    child_stdin.write_all(fit_to_unix(secret.expose_secret()).as_bytes())?;
    secret.zeroize();

    let exit_status = child.wait()?;
    if !exit_status.success() {
        return Err(anyhow!(format!("wl-copy exit failed: {}", exit_status)));
    }

    if let Some(secs) = timeout {
        let qdbus_executable: String = {
            let find_res: Result<String, Error> = {
                let output=Command::new("sh").arg("-c").arg(r#"echo $PATH | tr ':' '\n' | xargs -I {} find {} -maxdepth 1 -executable -regex '.*/qdbus[0-9]*$'"#).output()?;
                let output_str = String::from_utf8(output.stdout)?;
                let re: Vec<&str> = output_str.split('\n').collect();
                Ok(re.first().unwrap().to_string())
            };
            find_res.unwrap_or_else(|e| {
                warn!("Failed to get qdbus executable: {}, use default 'dbus'", e);
                "qdbus".to_string()
            })
        };
        let _=  Command::new("sh")
            .arg("-c")
            .arg(
                format!( "sleep {} && {} org.kde.klipper /klipper org.kde.klipper.klipper.clearClipboardHistory",secs,qdbus_executable),
            )
            .spawn();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    #[test]
    #[ignore = "Clipboard tests need desktop environment"]
    fn wayland_clipboard_test() {
        const TIMEOUT: usize = 1;
        let content = SecretString::new("Hello, pars".into());
        let res = copy_to_clip_board(content, Some(TIMEOUT));
        assert!(res.is_ok());

        let cmd = Command::new("wl-paste").output().unwrap();
        assert_eq!(cmd.stdout, b"Hello, pars\n");
        assert_eq!(cmd.status.success(), true);

        std::thread::sleep(std::time::Duration::from_secs(1 + TIMEOUT as u64));
        let cmd = Command::new("wl-paste").output().unwrap();
        assert_eq!(cmd.stdout, b"");
    }
}
