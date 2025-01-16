use std::error::Error;
use std::path::Path;

use regex::Regex;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_utils::path_to_str;
use crate::util::tree::{tree_with_filter, TreeColorConfig};
use crate::{IOErr, IOErrType};

pub fn ls_interact(
    client: &PGPClient,
    root_path: &Path,
    target_path: &str,
    filters: &Vec<Regex>,
    color_config: Option<TreeColorConfig>,
) -> Result<String, Box<dyn Error>> {
    let mut full_path = root_path.join(target_path);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        let result = tree_with_filter(&full_path, filters, color_config.is_some())?;
        if target_path.is_empty() {
            Ok(format!("Password Store\n{}", result))
        } else {
            Ok(format!("{}\n{}", target_path, result))
        }
    } else if full_path.is_file() {
        let data = client.decrypt_stdin(path_to_str(&full_path)?)?;
        return Ok(data.expose_secret().to_string());
    } else {
        return Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into());
    }
}

// Maybe unused
pub fn ls_dir(
    root_path: &Path,
    target_path: &Path,
    filters: &Vec<Regex>,
    color_config: Option<TreeColorConfig>,
) -> Result<String, Box<dyn Error>> {
    let mut full_path = root_path.join(target_path);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        let result = tree_with_filter(&full_path, filters, color_config.is_some())?;
        if target_path.as_os_str().is_empty() {
            Ok(format!("Password Store\n{}", result))
        } else {
            Ok(format!("{}\n{}", path_to_str(target_path)?, result))
        }
    } else {
        Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into())
    }
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::test_utils::{
        cleanup_test_dir, create_dir_structure, defer_cleanup, gen_unique_temp_dir,
    };
    //TODO: check interactive mode
    #[test]
    fn test_ls_dir() {
        // Structure
        // root
        // ├── dir1
        // │   ├── file1.gpg
        // │   └── file2.gpg
        // ├── dir2
        // │   ├── file3.gpg
        // │   └── file4.gpg
        // └── test.py

        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1.gpg", "file2.gpg"][..]),
            (Some("dir2"), &["file3.gpg", "file4.gpg"][..]),
            (None, &["test.py"][..]),
        ];
        create_dir_structure(&root, structure);

        defer_cleanup!(
            {
                let res = ls_dir(&root, Path::new("dir1"), &vec![], None).unwrap();
                assert_eq!(
                    res,
                    r#"dir1
├── file1
└── file2"#
                );

                let res = ls_dir(&root, Path::new("dir2"), &vec![], None).unwrap();
                assert_eq!(
                    res,
                    r#"dir2
├── file3
└── file4"#
                );

                let res = ls_dir(&root, Path::new(""), &vec![], None).unwrap();
                assert_eq!(
                    res,
                    r#"Password Store
├── dir1
│   ├── file1
│   └── file2
├── dir2
│   ├── file3
│   └── file4
└── test.py"#
                );
            },
            {
                cleanup_test_dir(&root);
            }
        )
    }
}
