#[allow(dead_code)]
#[cfg(target_os = "macos")]
mod mac;
#[cfg(all(unix, not(target_os = "macos")))]
pub mod wayland;
#[cfg(all(unix, not(target_os = "macos")))]
pub mod xorg;

#[cfg(target_os = "windows")]
mod windows;

use std::env;

#[allow(unused_imports)]
use anyhow::{anyhow, Result};
use secrecy::SecretString;

use crate::constants::PARS_DEFAULT_CLIP_TIME;
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

pub fn get_clip_time() -> Option<usize> {
    let time = match env::var("PARS_CLIP_TIME") {
        Ok(val) => val.parse::<usize>().unwrap_or(PARS_DEFAULT_CLIP_TIME),
        Err(_) => PARS_DEFAULT_CLIP_TIME,
    };
    if 0 == time {
        None
    } else {
        Some(time)
    }
}

#[cfg(all(unix, not(target_os = "macos")))]
fn check_executable(executable: &str) -> Result<()> {
    if find_executable_in_path(executable).is_none() {
        return Err(anyhow!("{} not found in PATH", executable));
    }
    Ok(())
}
