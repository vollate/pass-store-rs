#[allow(dead_code)]
#[cfg(target_os = "macos")]
mod mac;
#[cfg(any(
    target_os = "linux",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "netbsd"
))]
mod wayland;
#[cfg(target_os = "windows")]
mod windows;
#[cfg(any(
    target_os = "linux",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "netbsd"
))]
mod xorg;

use std::env;

use anyhow::{anyhow, Result};
use secrecy::SecretString;

use crate::util::fs_util::find_executable_in_path;

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
        if env::var("WAYLAND_DISPLAY").is_ok() {
            if find_executable_in_path("wl-copy").is_none() {
                return Err(anyhow!("wl-copy not found in PATH"));
            }
            wayland::copy_to_clip_board(content.clone(), sec_to_clear)?;
        } else if env::var("XDG_SESSION_TYPE").is_ok() {
            if find_executable_in_path("xclip").is_none() {
                return Err(anyhow!("xclip not found in PATH"));
            }
            xorg::copy_to_clip_board(content, sec_to_clear)?;
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
