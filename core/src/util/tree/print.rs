use std::collections::VecDeque;

use anyhow::Result;
use colored::Colorize;
use log::debug;

use super::{DirTree, NodeType, TreePrintConfig};

impl DirTree<'_> {
    pub fn print_tree(&self, config: &TreePrintConfig) -> Result<String> {
        debug!("Start to print tree:\n{:?}", self.map);
        let mut tree_builder = String::new(); //TODO(Vollate): we should use other structure for building string(huge dir case)
        let mut node_stack = VecDeque::<(usize, usize)>::new();
        node_stack.push_back((self.root, 0));
        let mut level_stack = VecDeque::<bool>::new();
        while let Some((parent_idx, vec_idx)) = node_stack.pop_back() {
            level_stack.pop_back();
            if vec_idx >= self.map[parent_idx].children.len() {
                continue;
            }
            let child_idx = self.map[parent_idx].children[vec_idx];
            let child = &self.map[child_idx];

            let is_local_last = vec_idx + 1 == self.map[parent_idx].children.len();
            level_stack.push_back(is_local_last);
            if !child.visible {
                node_stack.push_back((parent_idx, vec_idx + 1));
                continue;
            }
            let is_local_last = vec_idx + 1 == self.map[parent_idx].children.len();
            if level_stack.len() > 1 {
                for level_status in level_stack.iter().take(level_stack.len() - 1) {
                    if *level_status {
                        tree_builder.push_str("    ");
                    } else {
                        tree_builder.push_str("│   ");
                    }
                }
            }

            if is_local_last {
                tree_builder.push_str("└── ");
            } else {
                tree_builder.push_str("├── ");
            }

            node_stack.push_back((parent_idx, vec_idx + 1));

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
                    if child.is_recursive {
                        line = format!("{line} [recursive, not followed]\n");
                    } else {
                        line.push('\n');
                    }
                    tree_builder.push_str(line.as_str());
                    node_stack.push_back((child_idx, 0));
                    level_stack.push_back(false);
                }
                NodeType::Dir => {
                    let line = if let Some(color) = config.dir_color {
                        format!("{}\n", child.name.color(color))
                    } else {
                        format!("{}\n", child.name)
                    };
                    tree_builder.push_str(line.as_str());
                    node_stack.push_back((child_idx, 0));
                    level_stack.push_back(false);
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

    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::fs_util::create_symlink;
    use crate::util::test_util::{create_dir_structure, gen_unique_temp_dir, log_test};
    use crate::util::tree::{FilterType, TreeConfig};

    #[test]
    fn tree_normal_case() {
        let no_color_print = TreePrintConfig {
            dir_color: None,
            file_color: None,
            symbol_color: None,
            tree_color: None,
        };
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
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1", "file2"][..]),
            (Some("dir2"), &["file3", "file4"][..]),
            (Some("dir3"), &["file5"][..]),
            (Some("dir3/dir4"), &[][..]),
            (Some("dir3/dir4/dir5"), &[][..]),
        ];
        create_dir_structure(&root, structure);
        cleanup!(
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
    ├── dir4
    │   └── dir5
    └── file5"#
                );
            },
            {}
        )
    }

    #[test]
    fn test_filtered_case() {
        let no_color_print = TreePrintConfig {
            dir_color: None,
            file_color: None,
            symbol_color: None,
            tree_color: None,
        };
        // Create directory structure as below:
        // ├── dir1
        // │   └── file1
        // ├── dir2
        // │   └── file2
        // └── dir3
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[
            (Some("dir1"), &["file1"][..]),
            (Some("dir2"), &["file2"][..]),
            (Some("dir3"), &[][..]),
        ];
        create_dir_structure(&root, structure);

        // This case, only dir2 and file1 should be filtered
        cleanup!(
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
            {}
        )
    }

    #[test]
    fn test_symbolic_link() {
        let no_color_print = TreePrintConfig {
            dir_color: None,
            file_color: None,
            symbol_color: None,
            tree_color: None,
        };
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

        let (_tmp_dir, root1) = gen_unique_temp_dir();
        let (_tmp_dir, root2) = gen_unique_temp_dir();
        let structure1: &[(Option<&str>, &[&str])] = &[(Some("dir1"), &["file1"][..])];
        let structure2: &[(Option<&str>, &[&str])] =
            &[(Some("dir3"), &["file2"][..]), (Some("dir4"), &[][..])];
        create_dir_structure(&root1, structure1);
        create_dir_structure(&root2, structure2);
        create_symlink(&root2, &root1.join("dir2")).unwrap();

        cleanup!(
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
            {}
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
        let (_tmp_dir, root1) = gen_unique_temp_dir();
        let (_tmp_dir, root2) = gen_unique_temp_dir();
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
        cleanup!(
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
├── dir2 -> {}
│   ├── dir3
│   │   └── file2
│   └── dir4
├── dir3
├── dir4
└── file114514"#,
                        root2.to_str().unwrap()
                    )
                );
            },
            {}
        )
    }

    #[test]
    fn test_recursive_detection() {
        let no_color_print = TreePrintConfig {
            dir_color: None,
            file_color: None,
            symbol_color: None,
            tree_color: None,
        };

        // Test direct recursion
        {
            let (_tmp_dir, root) = gen_unique_temp_dir();
            let structure: &[(Option<&str>, &[&str])] =
                &[(Some("dir1"), &["file1.txt"][..]), (None, &["root_file.txt"][..])];
            create_dir_structure(&root, structure);

            cleanup!(
                {
                    // Create self-referential symlink
                    create_symlink(&root.join("dir1"), &root.join("dir1/loop")).unwrap();

                    let config = TreeConfig {
                        root: &root,
                        target: "",
                        filter_type: FilterType::Exclude,
                        filters: Vec::new(),
                    };
                    let bump = Bump::new();
                    let tree = DirTree::new(&config, &bump).unwrap();
                    let result = tree.print_tree(&no_color_print).unwrap();
                    log_test!("{}", result);

                    assert_eq!(
                        result,
                        format!(
                            r#"├── dir1
│   ├── file1.txt
│   └── loop -> {} [recursive, not followed]
└── root_file.txt"#,
                            root.join("dir1").to_str().unwrap()
                        )
                    );
                },
                {}
            );
        }

        // Test indirect recursion
        {
            let (_tmp_dir, root) = gen_unique_temp_dir();
            let structure: &[(Option<&str>, &[&str])] = &[
                (Some("dirA"), &["fileA.txt"][..]),
                (Some("dirB"), &["fileB.txt"][..]),
                (Some("dirC"), &["fileC.txt"][..]),
            ];
            create_dir_structure(&root, structure);

            cleanup!(
                {
                    // Create circular reference: A -> B -> C -> A
                    create_symlink(&root.join("dirB"), &root.join("dirA/linkB")).unwrap();
                    create_symlink(&root.join("dirC"), &root.join("dirB/linkC")).unwrap();
                    create_symlink(&root.join("dirA"), &root.join("dirC/linkA")).unwrap();

                    let config = TreeConfig {
                        root: &root,
                        target: "",
                        filter_type: FilterType::Exclude,
                        filters: Vec::new(),
                    };
                    let bump = Bump::new();
                    let tree = DirTree::new(&config, &bump).unwrap();
                    let result = tree.print_tree(&no_color_print).unwrap();
                    log_test!("{}", result);
                    assert_eq!(
                        result,
                        format!(
                            r#"├── dirA
│   ├── fileA.txt
│   └── linkB -> {}
│       ├── fileB.txt
│       └── linkC -> {}
│           ├── fileC.txt
│           └── linkA -> {} [recursive, not followed]
├── dirB
│   ├── fileB.txt
│   └── linkC -> {} [recursive, not followed]
└── dirC
    ├── fileC.txt
    └── linkA -> {} [recursive, not followed]"#,
                            root.join("dirB").to_str().unwrap(),
                            root.join("dirC").to_str().unwrap(),
                            root.join("dirA").to_str().unwrap(),
                            root.join("dirC").to_str().unwrap(),
                            root.join("dirA").to_str().unwrap(),
                        )
                    );
                },
                {}
            );
        }
    }
}
