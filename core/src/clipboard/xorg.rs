use std::error::Error;
use std::io::Write;
use std::process::Command;

use secrecy::{ExposeSecret, SecretString};
use zeroize::Zeroize;

pub(crate) fn copy_to_clip_board(
    mut secret: SecretString,
    timeout: Option<usize>,
) -> Result<(), Box<dyn Error>> {
    let mut child = Command::new("xclip")
        .arg("-selection")
        .arg("clipboard")
        .stdin(std::process::Stdio::piped())
        .spawn()?;

    let child_stdin = child.stdin.as_mut().ok_or("Cannot get stdin for 'xclip'")?;
    child_stdin.write_all(secret.expose_secret().as_bytes())?;
    secret.zeroize();

    let exit_status = child.wait()?;
    if !exit_status.success() {
        return Err(format!("xclip exit failed: {}", exit_status).into());
    }

    if let Some(secs) = timeout {
        let cmd = format!("sleep {} && echo -n '' | xclip -selection clipboard", secs);
        Command::new("sh").arg("-c").arg(cmd).spawn()?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    #[test]
    fn xorg_clipboard_test() {
        const TIMEOUT: usize = 1;
        let content = SecretString::new("Hello, pars".into());
        let res = copy_to_clip_board(content, Some(TIMEOUT));
        assert!(res.is_ok());

        let cmd =
            Command::new("xclip").arg("-o").arg("-selection").arg("clipboard").output().unwrap();
        assert_eq!(cmd.stdout, b"Hello, pars");
        assert_eq!(cmd.status.success(), true);

        //TODO: cleanup gnome clipboard
        std::thread::sleep(std::time::Duration::from_secs(1 + TIMEOUT as u64));
        let cmd =
            Command::new("xclip").arg("-o").arg("-selection").arg("clipboard").output().unwrap();

        assert_eq!(cmd.stdout, b"");
    }
}
