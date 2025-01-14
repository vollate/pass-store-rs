use std::env;
use std::error::Error;
use std::path::{Path, PathBuf};

use tempfile::TempDir;

use crate::pgp::{PGPClient, PGPErr};
use crate::util::fs_utils::path_to_str;
use crate::util::rand::rand_aplhabet_string;
use crate::{IOErr, IOErrType};

pub fn edit(
    client: &PGPClient,
    root: &Path,
    target: &str,
    editor: &Path,
) -> Result<(), Box<dyn Error>> {
    let target_path = root.join(target);
    if !target_path.exists() {
        return Err(IOErr::new(crate::IOErrType::PathNotExist, &target_path).into());
    } else if !target_path.is_file() {
        return Err(IOErr::new(crate::IOErrType::ExpectFile, &target_path).into());
    }

    let tmp_dir: PathBuf = {
        let temp_base = {
            #[cfg(unix)]
            {
                let shm_dir = PathBuf::from("/dev/shm");
                if !shm_dir.exists() {
                    env::temp_dir()
                } else {
                    shm_dir
                }
            }
            #[cfg(not(unix))]
            {
                env::temp_dir()
            }
        };
        TempDir::new_in(temp_base)?.into_path()
    };

    let temp_filename = target_path.with_extension("txt");
    let temp_filename = temp_filename
        .file_name()
        .ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, &target_path))?;
    let temp_filename = format!("{}-{}", rand_aplhabet_string(10), temp_filename.to_string_lossy());
    let temp_filepath = tmp_dir.join(temp_filename);

    // let msg=client.decrypt_with_password(file_path, passwd)
    Ok(())
}
