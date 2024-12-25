use std::error::Error;
use std::fs::DirEntry;
#[cfg(unix)]
use std::os::unix::fs::symlink;
#[cfg(windows)]
use std::os::windows::fs::{symlink_dir, symlink_file};
use std::path::{Path, PathBuf};
use std::{env, fs};

const BACKUP_EXTENSION: &str = "rsbak";
pub(crate) fn find_executable_in_path(executable: &str) -> Option<PathBuf> {
    if let Some(paths) = env::var_os("PATH") {
        for path in env::split_paths(&paths) {
            let full_path = path.join(executable);

            if is_executable(&full_path) {
                return Some(full_path);
            }
        }
    }

    None
}

pub(crate) fn get_home_dir() -> PathBuf {
    if let Some(home_str) = env::var_os("HOME") {
        PathBuf::from(home_str)
    } else {
        // #[cfg(windows)]
        // {
        //     if let Some(userprofile) = env::var_os("USERPROFILE").map(PathBuf::from) {
        //         userprofile
        //     } else {
        //         PathBuf::from("~")
        //     }
        // }
        // #[cfg(unix)]
        // {
        // }
        //TODO: fix this
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

pub(crate) fn restore_encrypted_file(file_path: &Path) -> Result<(), Box<dyn Error>> {
    if let Some(extension) = file_path.extension() {
        if extension == BACKUP_EXTENSION {
            let original_path = file_path.with_extension("");
            fs::rename(file_path, original_path)?;
        } else {
            return Err(format!("File extension is not {}", BACKUP_EXTENSION).into());
        }
    }
    Err("Fild does not has extension".into())
}

fn is_executable(path: &Path) -> bool {
    if path.is_file() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::metadata(path)
                .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
                .unwrap_or(false)
        }

        #[cfg(windows)]
        {
            path.extension()
                .map(|ext| ext == "exe" || ext == "bat" || ext == "cmd")
                .unwrap_or(false)
        }
    } else {
        false
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
}
