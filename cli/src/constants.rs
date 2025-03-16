use log::LevelFilter;
use pars_core::util::fs_util::{get_home_dir, path_to_str};

pub fn default_config_path() -> String {
    let path = get_home_dir().join(".config/pars/config.toml");

    match path_to_str(&path) {
        Ok(path) => path.into(),
        Err(_) => {
            eprintln!(
                "Error getting default config path, use '~/.config/pars/config.toml' instead"
            );
            "~/.config/pars/config.toml".into()
        }
    }
}

pub const DEFAULT_LOG_LEVEL: LevelFilter = LevelFilter::Info;
pub const SECRET_EXTENSION: &str = "gpg";
pub const DEFAULT_PASS_LENGTH: usize = 20;

#[repr(i32)]
pub enum ParsExitCode {
    Success = 0,
    Error = 1,
    InvalidArgs = 2,
    CommandNotFound = 127,
    PermissionDenied = 5,
    NotExecutable = 126,
    Timeout = 124,
    OutOfMemory = 137,
    ConfigError = 100,
    NetworkError = 101,
    PGPError = 199,
    GitError = 120,
    ClipboardError = 121,
}

#[cfg(target_os = "linux")]
impl From<ParsExitCode> for i32 {
    #[allow(unreachable_patterns)]
    fn from(val: ParsExitCode) -> Self {
        match val {
            ParsExitCode::Success => 0,
            ParsExitCode::Error => 1,
            ParsExitCode::InvalidArgs => 2,
            ParsExitCode::CommandNotFound => 127,
            ParsExitCode::PermissionDenied => 13,
            ParsExitCode::NotExecutable => 126,
            ParsExitCode::Timeout => 124,
            ParsExitCode::OutOfMemory => 137,
            ParsExitCode::ConfigError => 100,
            ParsExitCode::NetworkError => 101,
            ParsExitCode::PGPError => 199,
            ParsExitCode::GitError => 120,
            ParsExitCode::ClipboardError => 121,
            _ => 1,
        }
    }
}

#[cfg(target_os = "windows")]
impl From<ParsExitCode> for i32 {
    #[allow(unreachable_patterns)]
    fn from(val: ParsExitCode) -> Self {
        match val {
            ParsExitCode::Success => 0,
            ParsExitCode::Error => 1,
            ParsExitCode::InvalidArgs => 2,
            ParsExitCode::CommandNotFound => 1,
            ParsExitCode::PermissionDenied => 5,
            ParsExitCode::NotExecutable => 3,
            ParsExitCode::Timeout => 1,
            ParsExitCode::OutOfMemory => 8,
            ParsExitCode::ConfigError => 100,
            ParsExitCode::NetworkError => 101,
            ParsExitCode::PGPError => 199,
            ParsExitCode::GitError => 120,
            ParsExitCode::ClipboardError => 121,
            _ => 1,
        }
    }
}

#[cfg(target_os = "macos")]
impl From<ParsExitCode> for i32 {
    #[allow(unreachable_patterns)]

    fn from(val: ParsExitCode) -> Self {
        match val {
            ParsExitCode::Success => 0,
            ParsExitCode::Error => 1,
            ParsExitCode::InvalidArgs => 2,
            ParsExitCode::CommandNotFound => 127,
            ParsExitCode::PermissionDenied => 13,
            ParsExitCode::NotExecutable => 126,
            ParsExitCode::Timeout => 124,
            ParsExitCode::OutOfMemory => 137,
            ParsExitCode::ConfigError => 100,
            ParsExitCode::NetworkError => 101,
            ParsExitCode::PGPError => 199,
            ParsExitCode::GitError => 120,
            ParsExitCode::ClipboardError => 121,
            _ => 1,
        }
    }
}
