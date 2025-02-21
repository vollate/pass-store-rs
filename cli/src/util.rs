use std::path::PathBuf;

use pars_core::config::ParsConfig;

pub fn unwrap_root_path(root: Option<&str>, config: &ParsConfig) -> PathBuf {
    match root {
        Some(path) => path.into(),
        None => config.path_config.default_repo.clone().into(),
    }
}
