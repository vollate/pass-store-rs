use std::process::{Command, Stdio};

use anyhow::{anyhow, Result};
use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

pub(crate) fn copy_to_clip_board(mut secret: SecretString, timeout: Option<usize>) -> Result<()> {
    let mut child = Command::new("pbcopy").stdin(Stdio::piped()).spawn()?;

    if let Some(stdin) = child.stdin.as_mut() {
        use std::io::Write;
        stdin.write_all(secret.expose_secret().as_bytes())?;
    }
    secret.zeroize();

    let exit_status = child.wait()?;
    if !exit_status.success() {
        return Err(anyhow!("macOS pbcopy command failed: {}", exit_status));
    }

    if let Some(secs) = timeout {
        let cmd = format!("sleep {}; osascript -e 'set the clipboard to \"\"'", secs);
        let _ = Command::new("sh")
            .arg("-c")
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
    use serial_test::serial;

    use super::*;

    #[test]
    #[serial]
    fn macos_clipboard_test() {
        thread::sleep(Duration::from_secs(3));

        const TIMEOUT: usize = 1;
        let content = SecretString::new("Hello, macOS".into());
        let res = copy_to_clip_board(content, Some(TIMEOUT));
        assert!(res.is_ok());

        let cmd = Command::new("pbpaste").output().unwrap();
        assert_eq!(cmd.stdout, b"Hello, macOS\n");
        assert_eq!(cmd.status.success(), true);

        thread::sleep(Duration::from_secs(3 + TIMEOUT as u64));
        let cmd = Command::new("pbpaste").output().unwrap();
        assert_eq!(cmd.stdout, b"");
    }
}
