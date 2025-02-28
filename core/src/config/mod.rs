use serde::{Deserialize, Serialize};

#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub struct ParsConfig {
    pub print_config: PrintConfig,
    pub path_config: PathConfig,
    pub executable_config: ExecutableConfig,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct ParsConfigSerializable {
    pub print_config: PrintConfigSerializable,
    pub path_config: PathConfigSerializable,
    pub executable_config: ExecutableConfigSerializable,
}

#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub struct PrintConfig {
    pub dir_color: String,
    pub file_color: String,
    pub symbol_color: String,
    pub tree_color: String,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PrintConfigSerializable {
    pub dir_color: Option<String>,
    pub file_color: Option<String>,
    pub symbol_color: Option<String>,
    pub tree_color: Option<String>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PathConfig {
    pub default_repo: String,
    pub repos: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PathConfigSerializable {
    pub default_repo: Option<String>,
    pub repos: Option<Vec<String>>,
}
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ExecutableConfig {
    pub pgp_executable: String,
    pub editor_executable: String,
    pub git_executable: String,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct ExecutableConfigSerializable {
    pub pgp_executable: Option<String>,
    pub editor_executable: Option<String>,
    pub git_executable: Option<String>,
}

impl Default for ExecutableConfig {
    fn default() -> Self {
        Self {
            pgp_executable: "gpg".into(),
            editor_executable: {
                #[cfg(unix)]
                {
                    "vim".into()
                }
                #[cfg(windows)]
                {
                    "notepad".into()
                }
            },
            git_executable: "git".into(),
        }
    }
}
impl Default for PathConfig {
    fn default() -> Self {
        PathConfig {
            default_repo: {
                #[cfg(unix)]
                {
                    "~/.password-store".into()
                }
                #[cfg(windows)]
                {
                    "~\\.password-store".into()
                }
            },
            repos: Vec::default(),
        }
    }
}

impl From<ParsConfigSerializable> for ParsConfig {
    fn from(val: ParsConfigSerializable) -> Self {
        ParsConfig {
            print_config: val.print_config.into(),
            path_config: val.path_config.into(),
            executable_config: val.executable_config.into(),
        }
    }
}

impl From<PrintConfigSerializable> for PrintConfig {
    fn from(val: PrintConfigSerializable) -> Self {
        PrintConfig {
            dir_color: val.dir_color.unwrap_or_default(),
            file_color: val.file_color.unwrap_or_default(),
            symbol_color: val.symbol_color.unwrap_or_default(),
            tree_color: val.tree_color.unwrap_or_default(),
        }
    }
}

impl From<PathConfigSerializable> for PathConfig {
    fn from(val: PathConfigSerializable) -> Self {
        Self {
            default_repo: val.default_repo.unwrap_or(
                #[cfg(unix)]
                {
                    "~/.password-store".into()
                },
                #[cfg(windows)]
                {
                    "~\\.password-store".into()
                },
            ),
            repos: val.repos.unwrap_or_default(),
        }
    }
}

impl From<ExecutableConfigSerializable> for ExecutableConfig {
    fn from(val: ExecutableConfigSerializable) -> Self {
        Self {
            pgp_executable: val.pgp_executable.unwrap_or("gpg".into()),
            editor_executable: val.editor_executable.unwrap_or({
                #[cfg(unix)]
                {
                    "vim".into()
                }
                #[cfg(windows)]
                {
                    "notepad".into()
                }
            }),
            git_executable: val.git_executable.unwrap_or("git".into()),
        }
    }
}

impl From<ParsConfig> for ParsConfigSerializable {
    fn from(val: ParsConfig) -> Self {
        ParsConfigSerializable {
            print_config: val.print_config.into(),
            path_config: val.path_config.into(),
            executable_config: val.executable_config.into(),
        }
    }
}

impl From<PrintConfig> for PrintConfigSerializable {
    fn from(val: PrintConfig) -> Self {
        PrintConfigSerializable {
            dir_color: Some(val.dir_color),
            file_color: Some(val.file_color),
            symbol_color: Some(val.symbol_color),
            tree_color: Some(val.tree_color),
        }
    }
}

impl From<PathConfig> for PathConfigSerializable {
    fn from(val: PathConfig) -> Self {
        PathConfigSerializable { default_repo: Some(val.default_repo), repos: Some(val.repos) }
    }
}

impl From<ExecutableConfig> for ExecutableConfigSerializable {
    fn from(val: ExecutableConfig) -> Self {
        Self {
            pgp_executable: Some(val.pgp_executable),
            editor_executable: Some(val.editor_executable),
            git_executable: Some(val.git_executable),
        }
    }
}

pub mod loader;
