#[allow(dead_code)]
pub(crate) mod default_constants {
    pub const CLIP_TIME: usize = 45;
    pub const PGP_EXECUTABLE: &str = "gpg2";
    pub const GIT_EXECUTABLE: &str = "git";
    pub const EDITOR: &str = {
        #[cfg(unix)]
        {
            "vim"
        }
        #[cfg(windows)]
        {
            "notepad"
        }
    };

    pub const WAYLAND_COPY_EXECUTABLE: &str = "wl-copy";
    pub const X11_COPY_EXECUTABLE: &str = "xclip";
}

pub mod env_variables {
    pub const LOG_LEVEL_VAR: &str = "PARS_LOG_LEVEL";
    pub const CONFIG_PATH_ENV: &str = "PARS_CONFIG_PATH";
    pub const CLIP_TIME_ENV: &str = "PARS_CLIP_TIME";
}
