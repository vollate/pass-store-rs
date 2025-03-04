#[allow(dead_code)]
#[cfg(target_os = "macos")]
mod mac;

#[cfg(all(unix, not(target_os = "macos")))]
mod unix {
    #[cfg(any(
        target_os = "linux",
        target_os = "freebsd",
        target_os = "openbsd",
        target_os = "netbsd"
    ))]
    pub mod wayland;

    #[cfg(any(
        target_os = "linux",
        target_os = "freebsd",
        target_os = "openbsd",
        target_os = "netbsd"
    ))]
    pub mod xorg;
}

#[cfg(target_os = "windows")]
mod windows;

#[cfg(all(unix, not(target_os = "macos")))]
use std::env;

#[allow(unused_imports)]
use anyhow::{anyhow, Result};
use secrecy::SecretString;

#[cfg(all(unix, not(target_os = "macos")))]
use crate::util::fs_util::find_executable_in_path;

pub fn copy_to_clipboard(content: SecretString, sec_to_clear: Option<usize>) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        mac::copy_to_clip_board(content, sec_to_clear)?;
    }

    #[cfg(all(unix, not(target_os = "macos")))]
    {
        if env::var("WAYLAND_DISPLAY").is_ok() {
            check_executable("wl-copy")?;
            unix::wayland::copy_to_clip_board(content.clone(), sec_to_clear)?;
        } else if env::var("XDG_SESSION_TYPE").is_ok() {
            check_executable("xclip")?;
            unix::xorg::copy_to_clip_board(content, sec_to_clear)?;
        } else {
            return Err(anyhow!("Unknown display server, only X11 and Wayland are supported"));
        }
    }

    #[cfg(target_os = "windows")]
    {
        windows::copy_to_clip_board(content, sec_to_clear)?;
    }

    Ok(())
}

#[cfg(all(unix, not(target_os = "macos")))]
fn check_executable(executable: &str) -> Result<()> {
    if find_executable_in_path(executable).is_none() {
        return Err(anyhow!("{} not found in PATH", executable));
    }
    Ok(())
}
