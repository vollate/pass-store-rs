use std::fs;

use pars_core::config::cli::{load_config, save_config, ParsConfig};
use tempfile::tempdir;

fn legacy_config(default_repo: &str, repos: &[&str]) -> String {
    format!(
        r#"
[path_config]
default_repo = {default_repo:?}
repos = {repos:?}
"#
    )
}

#[test]
fn legacy_default_is_authoritative_and_ignored_directories_remain() {
    let temp = tempdir().unwrap();
    let selected = temp.path().join("selected");
    let ignored = temp.path().join("ignored");
    fs::create_dir_all(&selected).unwrap();
    fs::create_dir_all(&ignored).unwrap();
    let config_path = temp.path().join("pars.toml");
    fs::write(
        &config_path,
        legacy_config(
            &selected.display().to_string(),
            &[&ignored.display().to_string(), &selected.display().to_string()],
        ),
    )
    .unwrap();

    let config = load_config(&config_path).unwrap();
    assert_eq!(config.path_config.default_repo, selected.display().to_string());
    assert_eq!(config.path_config.repos, vec![selected.display().to_string()]);
    assert!(ignored.is_dir(), "normalization must never delete ignored roots");
}

#[test]
fn empty_legacy_default_recovers_first_non_empty_repo() {
    let temp = tempdir().unwrap();
    let recovered = temp.path().join("recovered");
    let later = temp.path().join("later");
    let config_path = temp.path().join("pars.toml");
    fs::write(
        &config_path,
        legacy_config("", &["", &recovered.display().to_string(), &later.display().to_string()]),
    )
    .unwrap();

    let config = load_config(config_path).unwrap();
    assert_eq!(config.path_config.default_repo, recovered.display().to_string());
    assert_eq!(config.path_config.repos, vec![recovered.display().to_string()]);
}

#[test]
fn missing_legacy_paths_are_normalized_without_filesystem_mutation() {
    let temp = tempdir().unwrap();
    let missing = temp.path().join("missing");
    let ignored = temp.path().join("also-missing");
    let config_path = temp.path().join("pars.toml");
    fs::write(
        &config_path,
        legacy_config(
            &missing.display().to_string(),
            &[&missing.display().to_string(), &ignored.display().to_string()],
        ),
    )
    .unwrap();

    let config = load_config(config_path).unwrap();
    assert_eq!(config.path_config.default_repo, missing.display().to_string());
    assert_eq!(config.path_config.repos, vec![missing.display().to_string()]);
    assert!(!missing.exists());
    assert!(!ignored.exists());
}

#[test]
fn save_normalizes_compatibility_mirror_to_zero_or_one_path() {
    let temp = tempdir().unwrap();
    let config_path = temp.path().join("pars.toml");
    let mut config = ParsConfig::default();
    config.path_config.default_repo = "/canonical".to_string();
    config.path_config.repos = vec!["/ignored".to_string(), "/canonical".to_string()];

    save_config(&config, &config_path).unwrap();
    let persisted = fs::read_to_string(&config_path).unwrap();
    assert!(persisted.contains("default_repo = \"/canonical\""));
    assert!(persisted.contains("repos = [\"/canonical\"]"));
    assert!(!persisted.contains("/ignored"));

    let loaded = load_config(config_path).unwrap();
    assert_eq!(loaded.path_config.repos, vec!["/canonical"]);
}

#[test]
fn config_save_atomically_replaces_existing_file_and_cleans_temporary_file() {
    let temp = tempdir().unwrap();
    let config_path = temp.path().join("pars.toml");
    fs::write(&config_path, "invalid old contents").unwrap();
    let config = ParsConfig::default();

    save_config(&config, &config_path).unwrap();

    assert_eq!(load_config(&config_path).unwrap(), config);
    assert!(temp.path().read_dir().unwrap().all(|entry| !entry
        .unwrap()
        .file_name()
        .to_string_lossy()
        .ends_with(".tmp")));
}

#[cfg(windows)]
#[test]
fn config_save_replaces_existing_destination_on_windows() {
    let temp = tempdir().unwrap();
    let config_path = temp.path().join("pars.toml");
    fs::write(&config_path, "old contents that must be replaced").unwrap();

    let mut config = ParsConfig::default();
    config.path_config.default_repo = r"C:\\vault".to_string();
    config.path_config.repos = vec![r"C:\\vault".to_string()];
    save_config(&config, &config_path).unwrap();

    assert_eq!(load_config(config_path).unwrap(), config);
}

#[test]
fn default_config_round_trips_with_one_compatibility_path() {
    let temp = tempdir().unwrap();
    let config_path = temp.path().join("pars.toml");
    let config = ParsConfig::default();
    save_config(&config, &config_path).unwrap();
    assert_eq!(load_config(config_path).unwrap(), config);
    assert_eq!(config.path_config.repos.len(), 1);
}
