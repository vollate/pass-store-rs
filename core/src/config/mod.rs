#[allow(dead_code)]
use std::{env, path};

use serde::{Deserialize, Serialize};

use crate::constants::default_constants::{EDITOR, GIT_EXECUTABLE, PGP_EXECUTABLE};

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
#[serde(default)]
pub struct ParsConfig {
    #[serde(default = "PrintConfig::default")]
    pub print_config: PrintConfig,
    #[serde(default = "PathConfig::default")]
    pub path_config: PathConfig,
    #[serde(default = "ExecutableConfig::default")]
    pub executable_config: ExecutableConfig,
}

#[derive(Debug, Serialize, Deserialize, Eq, PartialEq, Clone)]
pub struct PrintConfig {
    pub dir_color: String,
    pub file_color: String,
    pub symbol_color: String,
    pub tree_color: String,
    pub grep_pass_color: String,
    pub grep_match_color: String,
}

#[derive(Debug, Serialize, Deserialize, Eq, PartialEq)]
pub struct PathConfig {
    pub default_repo: String,
}

#[derive(Debug, Serialize, Deserialize, Eq, PartialEq)]
pub struct ExecutableConfig {
    pub pgp_executable: String,
    pub editor_executable: String,
    pub git_executable: String,
}

impl Default for PrintConfig {
    fn default() -> Self {
        Self {
            dir_color: "cyan".into(),
            file_color: String::new(),
            symbol_color: "bright green".into(),
            tree_color: String::new(),
            grep_pass_color: "bright green".into(),
            grep_match_color: "bright red".into(),
        }
    }
}

impl AsRef<PrintConfig> for PrintConfig {
    fn as_ref(&self) -> &PrintConfig {
        self
    }
}

impl PrintConfig {
    pub fn none() -> Self {
        Self {
            dir_color: String::new(),
            file_color: String::new(),
            symbol_color: String::new(),
            tree_color: String::new(),
            grep_pass_color: String::new(),
            grep_match_color: String::new(),
        }
    }
}

impl Default for ExecutableConfig {
    fn default() -> Self {
        Self {
            pgp_executable: PGP_EXECUTABLE.into(),
            editor_executable: EDITOR.into(),
            git_executable: GIT_EXECUTABLE.into(),
        }
    }
}

impl Default for PathConfig {
    fn default() -> Self {
        PathConfig {
            default_repo: {
                match dirs::home_dir() {
                    Some(path) => {
                        format!("{}{}.password-store", path.display(), path::MAIN_SEPARATOR)
                    }
                    None => {
                        format!(
                            "{}{}.password-store",
                            env::var(
                                #[cfg(unix)]
                                {
                                    "HOME"
                                },
                                #[cfg(windows)]
                                {
                                    "USERPROFILE"
                                }
                            )
                            .unwrap_or("~".into()),
                            path::MAIN_SEPARATOR
                        )
                    }
                }
            },
        }
    }
}

pub mod loader;
