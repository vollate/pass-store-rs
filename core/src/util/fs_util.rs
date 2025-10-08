use std::io::{BufRead, Read, Write};
#[cfg(unix)]
use std::os::unix::fs::symlink;
#[cfg(windows)]
use std::os::windows::fs::{symlink_dir, symlink_file};
use std::path::{Path, PathBuf};
use std::{env, fs, io};

use anyhow::{anyhow, Result};
use clean_path::Clean;
use directories::ProjectDirs;
use fs_extra::dir::{self, CopyOptions};
use log::debug;
use secrecy::{ExposeSecret, SecretBox};

use crate::constants::default_constants::BACKUP_EXTENSION;
use crate::pgp::PGPClient;
use crate::{IOErr, IOErrType};

pub fn find_executable_in_path(executable: &str) -> Option<PathBuf> {
    if let Some(paths) = env::var_os("PATH") {
        for path in env::split_paths(&paths) {
            let full_path = path.join(executable);

            if is_executable(&full_path).is_ok() {
                return Some(full_path);
            }
        }
    }
    None
}

pub fn better_rename<P: AsRef<Path>, Q: AsRef<Path>>(from: P, to: Q) -> Result<()> {
    let from = from.as_ref();
    let to = to.as_ref();
    if let Err(err) = fs::rename(from, to) {
        if err.kind() == io::ErrorKind::CrossesDevices {
            if from.is_dir() {
                dir::copy(from, to, &CopyOptions::new())?;
                fs::remove_dir_all(from)?;
            } else {
                fs::copy(from, to)?;
                fs::remove_file(from)?;
            }
        } else {
            return Err(err.into());
        }
    }

    Ok(())
}

pub fn copy_dir_recursive<P: AsRef<Path>, Q: AsRef<Path>>(from: P, to: Q) -> Result<()> {
    let mut options = CopyOptions::new();
    options.overwrite = false;
    options.copy_inside = true;
    dir::copy(from, to, &options)?;
    Ok(())
}

pub fn get_home_dir() -> PathBuf {
    dirs::home_dir().unwrap_or(PathBuf::from("~"))
}

pub fn get_dir_gpg_id_content(root: &Path, cur_dir: &Path) -> Result<Vec<String>> {
    path_attack_check(root, cur_dir)?;
    let mut to_check = cur_dir.to_path_buf();

    while to_check != root {
        if to_check.is_dir() {
            let key_file = to_check.join(".gpg-id");
            debug!("Check {key_file:?} for .gpg-id file");

            if key_file.exists() && key_file.is_file() {
                if let Ok(key) = fs::read_to_string(key_file) {
                    debug!("Found key(s): {key:?}");

                    return Ok(key
                        .lines()
                        .map(|line| line.trim())
                        .filter(|line| !line.is_empty())
                        .map(|line| line.to_string())
                        .collect());
                }
            }
        }
        match to_check.parent() {
            Some(parent) => {
                to_check = parent.to_path_buf();
            }
            None => break,
        }
    }

    if root.is_dir() {
        let key_file = root.join(".gpg-id");
        debug!("Checking root {root:?} for .gpg-id file");
        if key_file.exists() && key_file.is_file() {
            if let Ok(key) = fs::read_to_string(key_file) {
                debug!("Found key: {key:?}");
                return Ok(key
                    .split('\n')
                    .map(|line| line.trim())
                    .filter(|line| !line.is_empty())
                    .map(|line| line.to_string())
                    .collect());
            }
        }
    }
    Err(anyhow!(format!("Cannot find '.gpg-id' for {:?}", cur_dir)))
}

pub(crate) fn backup_encrypted_file(file_path: &Path) -> Result<PathBuf> {
    let extension = format!(
        "{}.{}",
        file_path.extension().unwrap_or_default().to_string_lossy(),
        BACKUP_EXTENSION
    );
    let backup_path = file_path.with_extension(&extension);
    fs::rename(file_path, &backup_path)?;
    Ok(backup_path)
}

pub(crate) fn restore_backup_file(file_path: &Path) -> Result<()> {
    if let Some(extension) = file_path.extension() {
        return if extension == BACKUP_EXTENSION {
            let original_path = file_path.with_extension("");
            fs::rename(file_path, original_path)?;
            Ok(())
        } else {
            Err(anyhow!(format!("File extension is not {}", BACKUP_EXTENSION)))
        };
    }
    Err(anyhow!("File does not has extension"))
}

fn is_executable(path: &Path) -> Result<bool> {
    if path.is_file() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            Ok(fs::metadata(path).map(|metadata| metadata.permissions().mode() & 0o111 != 0)?)
        }

        #[cfg(windows)]
        {
            Ok(path.extension().is_some_and(|ext| ext == "exe" || ext == "bat" || ext == "cmd"))
        }

        #[cfg(not(any(unix, windows)))]
        {
            Ok(false)
        }
    } else {
        Ok(false)
    }
}

pub fn create_symlink<P: AsRef<Path>>(original: P, link: P) -> Result<()> {
    #[cfg(unix)]
    {
        Ok(symlink(original, link)?)
    }

    #[cfg(windows)]
    {
        if original.as_ref().is_dir() {
            Ok(symlink_dir(original, link)?)
        } else {
            Ok(symlink_file(original, link)?)
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        Err("Symlinks are not supported on this platform".into())
    }
}

pub fn path_to_str(path: &Path) -> Result<&str> {
    Ok(path.to_str().ok_or_else(|| IOErr::new(IOErrType::InvalidPath, path))?)
}

pub fn filename_to_str(path: &Path) -> Result<&str> {
    Ok(path
        .file_name()
        .ok_or_else(|| IOErr::new(IOErrType::InvalidPath, path))?
        .to_str()
        .ok_or_else(|| IOErr::new(IOErrType::InvalidName, path))?)
}

pub fn is_sub_path_of<P: AsRef<Path>>(parent: P, child: P) -> Result<bool> {
    let child_clean = child.as_ref().clean();
    let parent_clean = parent.as_ref().clean();
    Ok(child_clean.starts_with(&parent_clean))
}

pub fn set_readonly<P: AsRef<Path>>(path: P, readonly: bool) -> Result<()> {
    let metadata = fs::metadata(path.as_ref())?;
    let mut permissions = metadata.permissions();
    permissions.set_readonly(readonly);
    fs::set_permissions(path, permissions)?;
    Ok(())
}

pub fn path_attack_check(root: &Path, child: &Path) -> Result<()> {
    if !is_sub_path_of(root, child)? {
        Err(IOErr::new(IOErrType::PathNotInRepo, child).into())
    } else {
        Ok(())
    }
}

pub fn prompt_overwrite<R: Read + BufRead, W: Write>(
    in_s: &mut R,
    err_s: &mut W,
    pass_name: &str,
) -> Result<bool> {
    write!(err_s, "An entry already exists for {pass_name}. Overwrite? [y/N]: ")?;
    let mut input = String::new();
    in_s.read_line(&mut input)?;
    Ok(input.trim().eq_ignore_ascii_case("y"))
}

pub fn create_or_overwrite(
    client: &PGPClient,
    pass_path: &Path,
    password: &SecretBox<str>,
) -> Result<()> {
    if pass_path.exists() {
        let backup = backup_encrypted_file(pass_path)?;
        match client.encrypt(password.expose_secret(), path_to_str(pass_path)?) {
            Ok(_) => {
                fs::remove_file(&backup)?;
                Ok(())
            }
            Err(e) => {
                restore_backup_file(&backup)?;
                Err(e)
            }
        }
    } else {
        client.encrypt(password.expose_secret(), path_to_str(pass_path)?)?;
        Ok(())
    }
}

pub fn default_config_path() -> String {
    if let Some(proj_dirs) = ProjectDirs::from("", "", "pars") {
        let config_path = proj_dirs.config_dir().join("config.toml");
        config_path.to_string_lossy().into_owned()
    } else {
        eprintln!(
            "Error determining config directory, falling back to '~/.config/pars/config.toml'"
        );
        "~/.config/pars/config.toml".into()
    }
}
