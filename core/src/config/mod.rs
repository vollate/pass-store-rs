use std::error::Error;

use serde::{Deserialize, Serialize};

use crate::util::tree::{self, string_to_color_opt};

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ParsConfig {
    pub print_config: PrintConfig,
    pub path_config: PathConfig,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct ParsConfigSerializable {
    pub print_config: PrintConfigSerializable,
    pub path_config: PathConfigSerializable,
}

#[derive(Clone, PartialEq, Eq, Debug)]
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
    pub pgp_executable: String,
    pub default_repo: String,
    pub repos: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PathConfigSerializable {
    pub pgp_executable: Option<String>,
    pub default_repo: Option<String>,
    pub repos: Option<Vec<String>>,
}

impl TryInto<tree::PrintConfig> for PrintConfig {
    type Error = Box<dyn Error>;

    fn try_into(self) -> Result<tree::PrintConfig, Self::Error> {
        Ok(tree::PrintConfig {
            dir_color: string_to_color_opt(&self.dir_color),
            file_color: string_to_color_opt(&self.file_color),
            symbol_color: string_to_color_opt(&self.symbol_color),
            tree_color: string_to_color_opt(&self.tree_color),
        })
    }
}

impl Into<ParsConfig> for ParsConfigSerializable {
    fn into(self) -> ParsConfig {
        ParsConfig { print_config: self.print_config.into(), path_config: self.path_config.into() }
    }
}

impl Into<PrintConfig> for PrintConfigSerializable {
    fn into(self) -> PrintConfig {
        PrintConfig {
            dir_color: self.dir_color.unwrap_or_default(),
            file_color: self.file_color.unwrap_or_default(),
            symbol_color: self.symbol_color.unwrap_or_default(),
            tree_color: self.tree_color.unwrap_or_default(),
        }
    }
}

impl Into<PathConfig> for PathConfigSerializable {
    fn into(self) -> PathConfig {
        PathConfig {
            pgp_executable: self.pgp_executable.unwrap_or("gpg".to_string()),
            default_repo: self.default_repo.unwrap_or(
                #[cfg(unix)]
                {
                    "~/.password-store".to_string()
                },
                #[cfg(windows)]
                {
                    "~\\.password-store".to_string()
                },
            ),
            repos: self.repos.unwrap_or_default(),
        }
    }
}

impl Into<ParsConfigSerializable> for ParsConfig {
    fn into(self) -> ParsConfigSerializable {
        ParsConfigSerializable {
            print_config: self.print_config.into(),
            path_config: self.path_config.into(),
        }
    }
}

impl Into<PrintConfigSerializable> for PrintConfig {
    fn into(self) -> PrintConfigSerializable {
        PrintConfigSerializable {
            dir_color: Some(self.dir_color),
            file_color: Some(self.file_color),
            symbol_color: Some(self.symbol_color),
            tree_color: Some(self.tree_color),
        }
    }
}

impl Into<PathConfigSerializable> for PathConfig {
    fn into(self) -> PathConfigSerializable {
        PathConfigSerializable {
            pgp_executable: Some(self.pgp_executable),
            default_repo: Some(self.default_repo),
            repos: Some(self.repos),
        }
    }
}

pub mod loader;
