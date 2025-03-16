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
use crate::util::fs_util::find_executable_in_path;

pub fn copy_to_clipboard(content: SecretString, sec_to_clear: Option<usize>) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        check_executable("pbcopy")?;
        mac::copy_to_clip_board(content, sec_to_clear)?;
    }

    #[cfg(all(unix, not(target_os = "macos")))]
    {
        if env::var("WAYLAND_DISPLAY").is_ok() {
            check_executable("wl-copy")?;
            wayland::copy_to_clip_board(content.clone(), sec_to_clear)?;
        } else if env::var("XDG_SESSION_TYPE").is_ok() {
            check_executable("xclip")?;
            xorg::copy_to_clip_board(content, sec_to_clear)?;
        } else {
            return Err(anyhow!(
                "Unknown display server, only X11 and Wayland are supported on unix systems"
            ));
        }
    }

    #[cfg(target_os = "windows")]
    {
        check_executable("powershell")?;
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

fn check_executable(executable: &str) -> Result<()> {
    if find_executable_in_path(executable).is_none() {
        return Err(anyhow!("Cannot find {} in PATH", executable));
    }
    Ok(())
}
