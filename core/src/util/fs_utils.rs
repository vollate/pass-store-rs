use std::error::Error;
use std::fs::DirEntry;
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::symlink;
#[cfg(windows)]
use std::os::windows::fs::{symlink_dir, symlink_file};
use std::path::{Path, PathBuf};
use std::{env, fs, io};

use clean_path::Clean;
use fs_extra::dir::{self, CopyOptions};

use crate::{IOErr, IOErrType};

const BACKUP_EXTENSION: &str = "rsbak";

pub(crate) fn find_executable_in_path(executable: &str) -> Option<PathBuf> {
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

pub(crate) fn better_rename<P: AsRef<Path>, Q: AsRef<Path>>(
    from: P,
    to: Q,
) -> Result<(), Box<dyn Error>> {
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
        }
    }

    Ok(())
}

pub(crate) fn copy_dir_recursive<P: AsRef<Path>, Q: AsRef<Path>>(
    from: P,
    to: Q,
) -> Result<(), Box<dyn Error>> {
    let mut options = CopyOptions::new();
    options.overwrite = false;
    options.copy_inside = true;
    dir::copy(from, to, &options)?;
    Ok(())
}

pub(crate) fn get_home_dir() -> PathBuf {
    #[cfg(unix)]
    {
        if let Some(home_str) = env::var_os("HOME") {
            PathBuf::from(home_str)
        } else {
            PathBuf::from("~")
        }
    }

    #[cfg(windows)]
    {
        if let Some(userprofile) = env::var_os("USERPROFILE") {
            PathBuf::from(userprofile)
        } else if let (Some(homedrive), Some(homepath)) =
            (env::var_os("HOMEDRIVE"), env::var_os("HOMEPATH"))
        {
            PathBuf::from(format!("{}{}", homedrive.to_string_lossy(), homepath.to_string_lossy()))
        } else {
            PathBuf::from("~")
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        PathBuf::from("~")
    }
}

pub(crate) fn process_files_recursively<F>(
    path: &PathBuf,
    process: &F,
) -> Result<(), Box<dyn Error>>
where
    F: Fn(&DirEntry) -> Result<(), Box<dyn Error>>,
{
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            let path = entry.path();

            if path.is_dir() {
                process_files_recursively(&path.to_path_buf(), process)?;
            } else {
                process(&entry)?;
            }
        }
    }
    Ok(())
}

pub(crate) fn backup_encrypted_file(file_path: &Path) -> Result<PathBuf, Box<dyn Error>> {
    let extension = format!(
        "{}.{}",
        file_path.extension().unwrap_or_default().to_string_lossy(),
        BACKUP_EXTENSION
    );
    let backup_path = file_path.with_extension(&extension);
    fs::rename(file_path, &backup_path)?;
    Ok(backup_path)
}

pub(crate) fn restore_backup_file(file_path: &Path) -> Result<(), Box<dyn Error>> {
    if let Some(extension) = file_path.extension() {
        if extension == BACKUP_EXTENSION {
            let original_path = file_path.with_extension("");
            fs::rename(file_path, original_path)?;
            return Ok(());
        } else {
            return Err(format!("File extension is not {}", BACKUP_EXTENSION).into());
        }
    }
    Err("File does not has extension".into())
}

fn is_executable(path: &Path) -> Result<bool, Box<dyn Error>> {
    if path.is_file() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            Ok(fs::metadata(path).map(|metadata| metadata.permissions().mode() & 0o111 != 0)?)
        }

        #[cfg(windows)]
        {
            Ok(path.extension().map(|ext| ext == "exe" || ext == "bat" || ext == "cmd")?)
        }

        #[cfg(not(any(unix, windows)))]
        {
            Ok(false)
        }
    } else {
        Ok(false)
    }
}

pub fn create_symlink<P: AsRef<Path>>(original: P, link: P) -> Result<(), Box<dyn Error>> {
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

pub(crate) fn path_to_str(path: &Path) -> Result<&str, Box<dyn Error>> {
    Ok(path.to_str().ok_or_else(|| IOErr::new(IOErrType::InvalidPath, path))?)
}

pub(crate) fn filename_to_str(path: &Path) -> Result<&str, Box<dyn Error>> {
    Ok(path
        .file_name()
        .ok_or_else(|| IOErr::new(IOErrType::InvalidPath, path))?
        .to_str()
        .ok_or_else(|| IOErr::new(IOErrType::InvalidName, path))?)
}

pub(crate) fn is_subpath_of<P: AsRef<Path>>(parent: P, child: P) -> Result<bool, Box<dyn Error>> {
    let child_clean = child.as_ref().clean();
    let parent_clean = parent.as_ref().clean();
    Ok(child_clean.starts_with(&parent_clean))
}

pub(crate) fn set_readonly<P: AsRef<Path>>(path: P, readonly: bool) -> Result<(), Box<dyn Error>> {
    let metadata = fs::metadata(path.as_ref())?;
    let mut permissions = metadata.permissions();
    permissions.set_readonly(readonly);
    fs::set_permissions(path, permissions)?;
    Ok(())
}

pub fn path_attack_check<E>(
    root: &Path,
    child: &Path,
    child_name: &str,
    err_stream: &mut E,
) -> Result<(), Box<dyn Error>>
where
    E: Write,
{
    if !is_subpath_of(root, &child)? {
        let err_msg =
            format!("'{}' is not the subpath of the root path '{}'", child_name, root.display());
        writeln!(err_stream, "{}", err_msg)?;
        Err(err_msg.into())
    } else {
        Ok(())
    }
}
