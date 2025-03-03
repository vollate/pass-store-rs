#[allow(dead_code)]
#[cfg(target_os = "macos")]
mod mac;
#[cfg(feature = "x11_wayland")]
mod wayland;
#[cfg(target_os = "windows")]
mod windows;
#[cfg(feature = "x11_wayland")]
mod xorg;

use anyhow::Result;
use secrecy::SecretString;

pub fn copy_to_clipboard(content: SecretString, sec_to_clear: Option<usize>) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        mac::copy_to_clip_board(content, sec_to_clear)?;
    }
    #[cfg(any(
        target_os = "linux",
        target_os = "freebsd",
        target_os = "openbsd",
        target_os = "netbsd"
    ))]
    {
        let wayland_res = wayland::copy_to_clip_board(content.clone(), sec_to_clear);
        let xorg_res = xorg::copy_to_clip_board(content, sec_to_clear);
        if wayland_res.is_err() && xorg_res.is_err() {
            return Err("No clipboard found: have you installed 'wl-clipboard' or 'xclip'?".into());
        }
    }
    #[cfg(target_os = "windows")]
    {
        windows::copy_to_clip_board(content, sec_to_clear)?;
    }

    Ok(())
}
