use anyhow::Result;
use bumpalo::Bump;
use log::debug;
use secrecy::SecretString;

use crate::pgp::PGPClient;
use crate::util::fs_util::{get_dir_gpg_id_content, path_to_str};
use crate::util::str;
use crate::util::str::remove_lines_postfix;
use crate::util::tree::{DirTree, TreeConfig, TreePrintConfig};
use crate::{IOErr, IOErrType};

pub enum LsOrShow {
    Password(SecretString),
    DirTree(String),
}

pub fn ls_io(
    pgp_executable: &str,
    tree_cfg: &TreeConfig,
    print_cfg: &TreePrintConfig,
) -> Result<LsOrShow> {
    let mut full_path = tree_cfg.root.join(tree_cfg.target);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        debug!("ls_io: '{}' is dir", tree_cfg.target);
        let bump = Bump::new();
        let tree = DirTree::new(tree_cfg, &bump)?;
        let result = tree.print_tree(print_cfg)?;
        let result = remove_lines_postfix(&result, ".gpg");
        let tree = if tree_cfg.target.is_empty() {
            format!("Password Store\n{}", result)
        } else {
            format!("{}\n{}", tree_cfg.target, result)
        };
        return Ok(LsOrShow::DirTree(tree));
    }

    if let Some(filename) = full_path.file_name().and_then(|n| n.to_str()) {
        full_path.set_file_name(format!("{}.gpg", filename));
    } else {
        return Err(IOErr::new(IOErrType::InvalidName, &full_path).into());
    }

    if full_path.is_file() {
        debug!("ls_io: '{}' is file", tree_cfg.target);
        // Get the appropriate key fingerprints for this file's path
        let key_fprs = get_dir_gpg_id_content(tree_cfg.root, &full_path)?;
        let client = PGPClient::new(
            pgp_executable,
            &key_fprs.iter().map(|s| s.as_str()).collect::<Vec<&str>>(),
        )?;

        let data = client.decrypt_stdin(tree_cfg.root, path_to_str(&full_path)?)?;
        Ok(LsOrShow::Password(data))
    } else if !full_path.exists() {
        Err(IOErr::new(IOErrType::PathNotExist, &full_path).into())
    } else {
        debug!("ls_io: {:?} is neither file or dir", full_path);
        Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into())
    }
}

pub fn ls_dir(tree_cfg: &TreeConfig, print_cfg: &TreePrintConfig) -> Result<String> {
    let mut full_path = tree_cfg.root.join(tree_cfg.target);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        let bump = Bump::new();
        let tree = DirTree::new(tree_cfg, &bump)?;
        let result = tree.print_tree(print_cfg)?;
        let result = str::remove_lines_postfix(&result, ".gpg");
        if tree_cfg.target.is_empty() {
            Ok(format!("Password Store\n{}", result))
        } else {
            Ok(format!("{}\n{}", tree_cfg.target, result))
        }
    } else {
        Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into())
    }
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::test_util::{create_dir_structure, gen_unique_temp_dir};
    use crate::util::tree::FilterType;

    //TODO: check interactive mode
    #[test]
    fn tree_dir() {
        // Structure
        // root
        // ├── dir1
        // │   ├── file1.gpg
        // │   └── file2.gpg
        // ├── dir2
        // │   ├── file3.gpg
        // │   └── file4.gpg
        // └── test.py

        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1.gpg", "file2.gpg"][..]),
            (Some("dir2"), &["file3.gpg", "file4.gpg"][..]),
            (None, &["test.py"][..]),
        ];
        create_dir_structure(&root, structure);

        cleanup!(
            {
                let mut config = TreeConfig {
                    root: &root,
                    target: "",
                    filter_type: FilterType::Disable,
                    filters: Vec::new(),
                };
                let print_cfg = TreePrintConfig {
                    dir_color: None,
                    file_color: None,
                    symbol_color: None,
                    tree_color: None,
                };

                config.target = "dir1";
                let res = ls_dir(&config, &print_cfg).unwrap();
                assert_eq!(
                    res,
                    r#"dir1
├── file1
└── file2"#
                );

                config.target = "dir2";
                let res = ls_dir(&config, &print_cfg).unwrap();
                assert_eq!(
                    res,
                    r#"dir2
├── file3
└── file4"#
                );

                config.target = "";
                let res = ls_dir(&config, &print_cfg).unwrap();
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
            {}
        )
    }
}
