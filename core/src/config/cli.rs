use std::error::Error;
use std::fs;
use std::path::Path;
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
    pub repos: Vec<String>,
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
        let default_path = match dirs::home_dir() {
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
        };
        PathConfig { default_repo: default_path.clone(), repos: vec![default_path] }
    }
}

pub fn load_config<P: AsRef<Path>>(path: P) -> Result<ParsConfig, Box<dyn Error>> {
    let content = fs::read_to_string(path)?;
    let config: ParsConfig = toml::from_str(&content)?;
    Ok(config)
}

pub fn save_config<P: AsRef<Path>>(config: &ParsConfig, path: P) -> Result<(), Box<dyn Error>> {
    let toml_str = toml::to_string_pretty(config)?;
    fs::write(path, toml_str)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::test_util::gen_unique_temp_dir;

    #[test]
    fn load_save_test() {
        let (_temp_dir, root) = gen_unique_temp_dir();
        let config_path = root.join("config.toml");

        let test_config = ParsConfig::default();
        save_config(&test_config, &config_path).unwrap();
        let loaded_config = load_config(&config_path).unwrap();
        assert_eq!(test_config, loaded_config);
    }

    #[test]
    fn invalid_path_test() {
        let test_config = ParsConfig::default();
        let result = if cfg!(unix) {
            save_config(&test_config, "/home/user/\0file.txt")
        } else if cfg!(windows) {
            save_config(&test_config, "C:\\<illegal>\\invalid.toml")
        } else {
            Err(Box::from("Unsupported OS"))
        };

        assert!(result.is_err());
    }
}
