use pass_store_rs_core::util::fs_util::{get_home_dir, path_to_str};

pub fn default_config_path() -> String {
    let path = get_home_dir().join(".config/pars/config.toml");

    match path_to_str(&path) {
        Ok(path) => path.into(),
        Err(_) => {
            eprintln!(
                "Error getting default config path, use '~/.config/pars/config.toml' instead"
            );
            "~/.config/pars/config.toml".into()
        }
    }
}

#[repr(i32)]
pub enum ParsExitCode {
    Success = 0,
    Error = 1,
}
