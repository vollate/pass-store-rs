use std::error::Error;

use serde::{Deserialize, Serialize};

use crate::util::tree::{self, string_to_color_opt};

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct ParsConfig {
    pub print_config: PrintConfig,
    pub path_config: PathConfig,
    pub key_config: KeyConfig,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PrintConfig {
    pub dir_color: Option<String>,
    pub file_color: Option<String>,
    pub symbol_color: Option<String>,
    pub tree_color: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PathConfig {
    pub default_repo: Option<String>,
    pub repos: Option<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct KeyConfig {}

pub mod loader;

impl TryInto<tree::PrintConfig> for PrintConfig {
    type Error = Box<dyn Error>;

    fn try_into(self) -> Result<tree::PrintConfig, Self::Error> {
        Ok(tree::PrintConfig {
            dir_color: string_to_color_opt(&self.dir_color)?,
            file_color: string_to_color_opt(&self.file_color)?,
            symbol_color: string_to_color_opt(&self.symbol_color)?,
            tree_color: string_to_color_opt(&self.tree_color)?,
        })
    }
}
