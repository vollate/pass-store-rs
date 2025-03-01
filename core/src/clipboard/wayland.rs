use std::error::Error;
use std::io::Write;
use std::process::Command;

use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

pub(crate) fn copy_to_clip_board(
    mut secret: SecretString,
    timeout: Option<usize>,
) -> Result<(), Box<dyn Error>> {
    let mut cmd = Command::new("wl-copy");
    cmd.arg("-n");

    let mut child = cmd.stdin(std::process::Stdio::piped()).spawn()?;

    let child_stdin = child.stdin.as_mut().ok_or("Cannot get stdin for 'wl-copy'")?;
    child_stdin.write_all(secret.expose_secret().as_bytes())?;
    secret.zeroize();

    let exit_status = child.wait()?;
    if !exit_status.success() {
        return Err(format!("wl-copy exit failed: {}", exit_status).into());
    }

    //TODO: handle gnome
    if let Some(secs) = timeout {
        Command::new("sh")
            .arg("-c")
            .arg(
               format!( "sleep {} && qdbus org.kde.klipper /klipper org.kde.klipper.klipper.clearClipboardHistory",secs),
            )
            .spawn()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    #[test]
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
