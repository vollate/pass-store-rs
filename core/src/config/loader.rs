use std::error::Error;
use std::fs;
use std::path::Path;

use super::ParsConfig;

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
