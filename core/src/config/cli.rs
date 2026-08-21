use std::error::Error;
use std::fs;
use std::io::Write;
use std::path::Path;
#[allow(dead_code)]
use std::{env, path};

use log::warn;
use serde::{Deserialize, Serialize};
use tempfile::NamedTempFile;

use crate::constants::default_constants::{EDITOR, GIT_EXECUTABLE, PGP_EXECUTABLE};
use crate::pgp::backend::PgpBackendConfig;

#[derive(Debug, Clone, Serialize, Deserialize, Default, Eq, PartialEq)]
#[serde(default)]
pub struct ParsConfig {
    #[serde(default = "PrintConfig::default")]
    pub print_config: PrintConfig,
    #[serde(default = "PathConfig::default")]
    pub path_config: PathConfig,
    #[serde(default = "ExecutableConfig::default")]
    pub executable_config: ExecutableConfig,
    #[serde(default = "PgpBackendConfig::default")]
    pub pgp_config: PgpBackendConfig,
    #[serde(default = "FeatureConfig::default")]
    pub feature_config: FeatureConfig,
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

#[derive(Debug, Clone, Serialize, Deserialize, Eq, PartialEq)]
pub struct PathConfig {
    pub default_repo: String,
    pub repos: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Eq, PartialEq)]
pub struct ExecutableConfig {
    pub pgp_executable: String,
    pub editor_executable: String,
    pub git_executable: String,
}

#[derive(Debug, Serialize, Deserialize, Eq, PartialEq, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub enum PgpBackendKind {
    #[serde(rename = "bundled")]
    Bundled,
    SystemGpg,
    PureRust,
}

#[derive(Debug, Clone, Serialize, Deserialize, Eq, PartialEq)]
pub struct FeatureConfig {
    pub clip_time: Option<usize>,
    pub fuzzy_search: bool,
    pub vim_mode: bool,
    pub exit_on_copy: bool,
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

impl PathConfig {
    /// Collapse the legacy GUI repository registry to one canonical store.
    ///
    /// `default_repo` remains authoritative. Only when it is empty do we
    /// recover the first non-empty legacy `repos` entry. The compatibility
    /// mirror is then kept at zero or one element so older CLI builds can
    /// still resolve the selected store without reintroducing GUI switching.
    pub fn normalize_canonical_store(&mut self) {
        let canonical = if self.default_repo.trim().is_empty() {
            self.repos.iter().find(|repo| !repo.trim().is_empty()).cloned()
        } else {
            Some(self.default_repo.clone())
        };
        match canonical {
            Some(root) => {
                self.default_repo = root.clone();
                self.repos = vec![root];
            }
            None => {
                self.default_repo.clear();
                self.repos.clear();
            }
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

impl Default for FeatureConfig {
    fn default() -> Self {
        FeatureConfig {
            clip_time: Some(45),
            fuzzy_search: true,
            vim_mode: false,
            exit_on_copy: false,
        }
    }
}

pub fn load_config<P: AsRef<Path>>(path: P) -> Result<ParsConfig, Box<dyn Error>> {
    let content = fs::read_to_string(path)?;
    let mut config: ParsConfig = toml::from_str(&content)?;
    config.path_config.normalize_canonical_store();
    Ok(config)
}

pub fn save_config<P: AsRef<Path>>(config: &ParsConfig, path: P) -> Result<(), Box<dyn Error>> {
    let path = path.as_ref();
    let parent =
        path.parent().filter(|value| !value.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let mut normalized = config.clone();
    normalized.path_config.normalize_canonical_store();
    let toml_str = toml::to_string_pretty(&normalized)?;

    // NamedTempFile::persist uses replace-existing semantics on every supported
    // platform (MoveFileExW on Windows and rename on Unix) while keeping the
    // temporary file on the same filesystem as the destination.
    let mut temporary = NamedTempFile::new_in(parent)?;
    temporary.write_all(toml_str.as_bytes())?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

pub fn handle_env_config(config: ParsConfig) -> ParsConfig {
    use env_var_handler::*;

    let mut new_conf = config;
    let config = &mut new_conf;

    handle_clip_time(config);
    handle_fuzzy(config);
    handle_vim_mode(config);

    new_conf
}

mod env_var_handler {
    use super::*;

    pub(super) fn handle_clip_time(config: &mut ParsConfig) {
        if let Ok(sec_str) = env::var("PARS_CLIP_TIME") {
            match sec_str.parse::<usize>() {
                Ok(sec) => {
                    config.feature_config.clip_time = {
                        if sec == 0 {
                            None
                        } else {
                            Some(sec)
                        }
                    }
                }
                Err(e) => {
                    warn!("Parse env variable 'PARS_CLIP_TIME' met error {e}");
                }
            }
        }
    }

    pub(super) fn handle_fuzzy(config: &mut ParsConfig) {
        if env::var("PARS_NO_FUZZY").is_ok() {
            config.feature_config.fuzzy_search = false;
        }
    }

    pub(super) fn handle_vim_mode(config: &mut ParsConfig) {
        if env::var("PARS_VIM_MODE").is_ok() {
            config.feature_config.vim_mode = true;
        }
    }
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
    fn legacy_multi_store_config_keeps_default_only() {
        let (_temp_dir, root) = gen_unique_temp_dir();
        let config_path = root.join("legacy.toml");
        fs::write(
            &config_path,
            "[path_config]\ndefault_repo = \"/vault/personal\"\nrepos = [\"/vault/work\", \"/vault/personal\"]\n",
        )
        .unwrap();

        let loaded = load_config(&config_path).unwrap();
        assert_eq!(loaded.path_config.default_repo, "/vault/personal");
        assert_eq!(loaded.path_config.repos, vec!["/vault/personal"]);
    }

    #[test]
    fn legacy_empty_default_recovers_first_non_empty_store() {
        let (_temp_dir, root) = gen_unique_temp_dir();
        let config_path = root.join("legacy-empty.toml");
        fs::write(
            &config_path,
            "[path_config]\ndefault_repo = \"\"\nrepos = [\"\", \"/vault/recovered\", \"/vault/ignored\"]\n",
        )
        .unwrap();

        let loaded = load_config(&config_path).unwrap();
        assert_eq!(loaded.path_config.default_repo, "/vault/recovered");
        assert_eq!(loaded.path_config.repos, vec!["/vault/recovered"]);
    }

    #[test]
    fn empty_store_config_remains_empty() {
        let mut path_config = PathConfig { default_repo: String::new(), repos: vec![] };
        path_config.normalize_canonical_store();
        assert!(path_config.default_repo.is_empty());
        assert!(path_config.repos.is_empty());
    }

    #[test]
    fn generate_default_config_test() {
        let mut default_config = ParsConfig::default();
        default_config.path_config.default_repo = "<Your Home>/.password-store".into();
        default_config.path_config.repos = vec!["<Your Home>/.password-store".into()];
        let root = env!("CARGO_MANIFEST_DIR");
        let save_path = Path::new(root).parent().unwrap().join("config").join("cli");
        if !save_path.exists() {
            fs::create_dir_all(&save_path).unwrap();
        }
        save_config(&default_config, save_path.join("pars_config.toml"))
            .expect("Failed to save default config");
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
