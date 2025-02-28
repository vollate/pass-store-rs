use std::error::Error;

use bumpalo::Bump;
use secrecy::ExposeSecret;

use crate::pgp::PGPClient;
use crate::util::fs_util::path_to_str;
use crate::util::str;
use crate::util::str::remove_lines_postfix;
use crate::util::tree::{DirTree, PrintConfig, TreeConfig};
use crate::{IOErr, IOErrType};

pub fn ls_io(
    client: &PGPClient,
    tree_cfg: &TreeConfig,
    print_cfg: &PrintConfig,
) -> Result<String, Box<dyn Error>> {
    let mut full_path = tree_cfg.root.join(tree_cfg.target);

    while full_path.is_symlink() {
        full_path = full_path.read_link()?;
    }

    if full_path.is_dir() {
        let bump = Bump::new();
        let tree = DirTree::new(tree_cfg, &bump)?;
        let result = tree.print_tree(print_cfg)?;
        let result = remove_lines_postfix(&result, ".gpg");
        if tree_cfg.target.is_empty() {
            Ok(format!("Password Store\n{}", result))
        } else {
            Ok(format!("{}\n{}", tree_cfg.target, result))
        }
    } else if full_path.is_file() {
        let data = client.decrypt_stdin(tree_cfg.root, path_to_str(&full_path)?)?;
        return Ok(data.expose_secret().to_string());
    } else {
        return Err(IOErr::new(IOErrType::InvalidFileType, &full_path).into());
    }
}

pub fn ls_dir(tree_cfg: &TreeConfig, print_cfg: &PrintConfig) -> Result<String, Box<dyn Error>> {
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
                let print_cfg = PrintConfig {
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
