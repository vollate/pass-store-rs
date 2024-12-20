use std::path::{Path, PathBuf};
use std::{env, fs};

pub fn find_executable_in_path(executable: &str) -> Option<PathBuf> {
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
