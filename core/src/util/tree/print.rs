use std::cmp::max;
use std::collections::VecDeque;
use std::error::Error;
use std::ffi::OsStr;
use std::fs::DirEntry;
use std::path::Path;

use chrono::format;
use colored::{Color, Colorize};
use fs_extra::file;
use log::debug;

use super::{DirTree, NodeType, PrintConfig};

impl<'a> DirTree<'a> {
    pub fn print_tree(&self, config: &PrintConfig) -> Result<String, Box<dyn Error>> {
        debug!("Start to print tree: {:?}", self.map);
        let mut tree_builder = String::new(); //TODO(Vollate): we should use other structure for building string(huge dir case)
        let mut stack = VecDeque::<(usize, usize)>::new();
        stack.push_back((self.root, 0));
        let mut space_to_print = 0;
        while let Some((parent_idx, vec_idx)) = stack.pop_back() {
            if vec_idx >= self.map[parent_idx].children.len() {
                continue;
            }
            let child_idx = self.map[parent_idx].children[vec_idx];
            let child = &self.map[child_idx];
            if !child.visiable {
                stack.push_back((parent_idx, vec_idx + 1));
                continue;
            }
            let is_local_last = vec_idx + 1 == self.map[parent_idx].children.len();

            for _ in 0..space_to_print {
                tree_builder.push_str("    ");
            }
            for _ in space_to_print..stack.len() {
                tree_builder.push_str("│   ");
            }

            if is_local_last {
                tree_builder.push_str("└── ");
            } else {
                tree_builder.push_str("├── ");
            }

            if (space_to_print > 0 || parent_idx == self.root)
                && is_local_last
                && space_to_print == stack.len()
            {
                space_to_print += 1;
            }
            stack.push_back((parent_idx, vec_idx + 1));

            match child.node_type {
                NodeType::Symlink => {
                    let mut line = if let Some(color) = config.symbol_color {
                        format!(
                            "{} -> {}",
                            child.name.color(color),
                            child.symlink_target.as_ref().unwrap()
                        )
                    } else {
                        format!("{} -> {}", child.name, child.symlink_target.as_ref().unwrap())
                    };
                    if child.is_rescursive {
                        line = format!("{} [rescursive]\n", line);
                    } else {
                        line.push('\n');
                    }
                    tree_builder.push_str(line.as_str());
                    stack.push_back((child_idx, 0));
                }
                NodeType::Dir => {
                    let line = if let Some(color) = config.dir_color {
                        format!("{}\n", child.name.color(color))
                    } else {
                        format!("{}\n", child.name)
                    };
                    tree_builder.push_str(line.as_str());
                    stack.push_back((child_idx, 0));
                }
                NodeType::File => {
                    let line = if let Some(color) = config.file_color {
                        format!("{}\n", child.name.color(color))
                    } else {
                        format!("{}\n", child.name)
                    };
                    tree_builder.push_str(line.as_str());
                }
                NodeType::Other => {
                    let line = if let Some(color) = config.tree_color {
                        format!("{}\n", child.name.color(color))
                    } else {
                        format!("{}\n", child.name)
                    };
                    tree_builder.push_str(line.as_str());
                }
                NodeType::Invalid => {
                    panic!("Should not have any invalid type");
                }
            }
        }
        tree_builder.pop();
        Ok(tree_builder)
    }
}

#[cfg(test)]
mod tests {
    use bumpalo::Bump;
    use pretty_assertions::assert_eq;
    use regex::Regex;
    use tests::test_utils::defer_cleanup;

    use super::*;
    use crate::util::fs_utils::create_symlink;
    use crate::util::log::{init_debug_logger, init_logger, set_log_level};
    use crate::util::test_utils;
    use crate::util::test_utils::{create_dir_structure, gen_unique_temp_dir};
    use crate::util::tree::{FilterType, TreeConfig};

    #[test]
    fn tree_normal_case() {
        let no_color_print =
            PrintConfig { dir_color: None, file_color: None, symbol_color: None, tree_color: None };
        // Create directory structure as below:
        // ├── dir1
        // │   ├── file1
        // │   └── file2
        // ├── dir2
        // │   ├── file3
        // │   └── file4
        // └── dir3
        //     ├── dir4
        //     │   └── dir5
        //     └── file5
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1", "file2"][..]),
            (Some("dir2"), &["file3", "file4"][..]),
            (Some("dir3"), &["file5"][..]),
            (Some("dir3/dir4"), &[][..]),
            (Some("dir3/dir4/dir5"), &[][..]),
        ];
        create_dir_structure(&root, structure);
        defer_cleanup!(
            {
                let config = TreeConfig {
                    root: &root,
                    target: "",
                    filter_type: FilterType::Disable,
                    filters: Vec::new(),
                };
                let bump = Bump::new();
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(
                    result,
                    r#"├── dir1
│   ├── file1
│   └── file2
├── dir2
│   ├── file3
│   └── file4
└── dir3
    ├── file5
    └── dir4
        └── dir5"#
                );
            },
            {
                test_utils::cleanup_test_dir(&root);
            }
        )
    }

    #[test]
    fn test_filtered_case() {
        let no_color_print =
            PrintConfig { dir_color: None, file_color: None, symbol_color: None, tree_color: None };
        // Create directory structure as below:
        // ├── dir1
        // │   └── file1
        // ├── dir2
        // │   └── file2
        // └── dir3
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1"][..]),
            (Some("dir2"), &["file2"][..]),
            (Some("dir3"), &[][..]),
        ];
        create_dir_structure(&root, structure);

        // This case, only dir2 and file1 should be filtered
        defer_cleanup!(
            {
                let mut config = TreeConfig {
                    root: &root,
                    target: "",
                    filter_type: FilterType::Exclude,
                    filters: vec![Regex::new(r"dir2").unwrap(), Regex::new(r"file1").unwrap()],
                };

                let bump = Bump::new();
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(
                    result,
                    r#"├── dir1
└── dir3"#
                );

                // This case, nothing should be filtered
                config.filters = Vec::new();
                config.filter_type = FilterType::Disable;
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(
                    result,
                    r#"├── dir1
│   └── file1
├── dir2
│   └── file2
└── dir3"#
                );

                // This case, everything should be filtered
                config.filter_type = FilterType::Exclude;
                config.filters = vec![
                    Regex::new(r"dir1").unwrap(),
                    Regex::new(r"dir2").unwrap(),
                    Regex::new(r"dir3").unwrap(),
                ];
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(result, "");

                // Now, test white-list mode
                config.filter_type = FilterType::Include;
                config.filters = vec![Regex::new(r"dir1").unwrap(), Regex::new(r"file2").unwrap()];
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(
                    result,
                    r#"├── dir1
│   └── file1
└── dir2
    └── file2"#
                );
            },
            {
                test_utils::cleanup_test_dir(&root);
            }
        )
    }

    #[test]
    fn test_symbolic_link() {
        let no_color_print =
            PrintConfig { dir_color: None, file_color: None, symbol_color: None, tree_color: None };
        // Create directory structure as below:
        // root1
        // ├── dir1
        // │   └── file1
        // └── dir2 -> root2
        //
        // --------------------------------
        //
        // root2
        // ├── dir3
        // │   └── file2
        // └── dir4

        let root1 = gen_unique_temp_dir();
        let root2 = gen_unique_temp_dir();
        let structure1: &[(Option<&str>, &[&str])] = &[(Some("dir1"), &["file1"][..])];
        let structure2: &[(Option<&str>, &[&str])] =
            &[(Some("dir3"), &["file2"][..]), (Some("dir4"), &[][..])];
        create_dir_structure(&root1, structure1);
        create_dir_structure(&root2, structure2);
        create_symlink(&root2, &root1.join("dir2")).unwrap();

        defer_cleanup!(
            {
                let config = TreeConfig {
                    root: &root1,
                    target: "",
                    filter_type: FilterType::Exclude,
                    filters: Vec::new(),
                };
                let bump = Bump::new();
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(
                    result,
                    format!(
                        r#"├── dir1
│   └── file1
└── dir2 -> {}
    ├── dir3
    │   └── file2
    └── dir4"#,
                        root2.to_str().unwrap()
                    )
                );
            },
            {
                test_utils::cleanup_test_dir(&root1);
                test_utils::cleanup_test_dir(&root2);
            }
        );

        // Create directory structure as below:
        // root1
        // ├── dir1
        // │   └── file1
        // ├── dir2 -> root2
        // ├── dir3
        // ├── dir4
        // └── file114514
        //
        // --------------------------------
        //
        // root2
        // ├── dir3
        // │   └── file2
        // └── dir4
        let root1 = gen_unique_temp_dir();
        let root2 = gen_unique_temp_dir();
        let structure1: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1"][..]),
            (Some("dir3"), &[][..]),
            (Some("dir4"), &[][..]),
            (None, &["file114514"][..]),
        ];
        let structure2: &[(Option<&str>, &[&str])] =
            &[(Some("dir3"), &["file2"][..]), (Some("dir4"), &[][..])];
        create_dir_structure(&root1, structure1);
        create_dir_structure(&root2, structure2);
        create_symlink(&root2, &root1.join("dir2")).unwrap();
        defer_cleanup!(
            {
                let config = TreeConfig {
                    root: &root1,
                    target: "",
                    filter_type: FilterType::Exclude,
                    filters: Vec::new(),
                };
                let bump = Bump::new();
                let tree = DirTree::new(&config, &bump).unwrap();
                let result = tree.print_tree(&no_color_print).unwrap();
                assert_eq!(
                    result,
                    format!(
                        r#"├── dir1
│   └── file1
├── dir3
├── dir4
├── file114514
└── dir2 -> {}
    ├── dir3
    │   └── file2
    └── dir4"#,
                        root2.to_str().unwrap()
                    )
                );
            },
            {
                test_utils::cleanup_test_dir(&root1);
                test_utils::cleanup_test_dir(&root2);
            }
        )
    }
}
