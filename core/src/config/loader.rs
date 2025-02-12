use std::error::Error;
use std::fs;
use std::path::Path;

use config::{Config as ConfigLoader, File};

use super::ParsConfig;
use crate::util::fs_util::path_to_str;

pub fn load_config<P: AsRef<Path>>(path: P) -> Result<ParsConfig, Box<dyn Error>> {
    let file_path = path_to_str(path.as_ref())?;
    let cfg_loader =
        ConfigLoader::builder().add_source(File::with_name(file_path).required(false)).build()?;
    Ok(cfg_loader.try_deserialize::<ParsConfig>()?)
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
    fn test_save_and_load_config() {
        let (_temp_dir, root) = gen_unique_temp_dir();
        let config_path = root.join("config.toml");

        let test_config = ParsConfig::default();
        save_config(&test_config, &config_path).unwrap();
        let loaded_config = load_config(&config_path).unwrap();
        assert_eq!(test_config, loaded_config);
    }

    #[test]
    fn test_save_config_invalid_path() {
        let test_config = ParsConfig::default();
        let result = save_config(&test_config, "/.invalid.toml");
        assert!(result.is_err());
    }
}
