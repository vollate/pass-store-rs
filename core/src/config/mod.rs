use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct ParsConfig {
    pub print_config: PrintConfig,
    pub path_config: PathConfig,
    pub key_config: KeyConfig,
}
#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PrintConfig {}
#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct PathConfig {
    pub default_repo: Option<String>,
    pub repos: Option<Vec<String>>,
}
#[derive(Debug, Serialize, Deserialize, Default, Eq, PartialEq)]
pub struct KeyConfig {}

pub mod loader;
