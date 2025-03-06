use std::path::PathBuf;

use pars_core::config::ParsConfig;

pub(crate) fn unwrap_root_path(root: Option<&str>, config: &ParsConfig) -> PathBuf {
    match root {
        Some(path) => path.into(),
        None => config.path_config.default_repo.clone().into(),
    }
}

pub(crate) fn to_relative_path_opt(path: Option<String>) -> Option<String> {
    path.map(|mut s| {
        while s.starts_with('/') || s.starts_with('\\') {
            s = s[1..].to_string();
        }
        s
    })
}

pub(crate) fn to_relative_path(path: String) -> String {
    let mut s = path.as_str();
    while s.starts_with('/') || s.starts_with('\\') {
        s = &s[1..];
    }
    s.to_string()
}
