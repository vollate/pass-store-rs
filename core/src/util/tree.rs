use std::error::Error;
use std::ffi::OsStr;
use std::fs::DirEntry;
use std::path::Path;

use colored::{Color, Colorize};
use regex::Regex;

use crate::{IOErr, IOErrType};

#[derive(PartialEq, Eq)]
pub enum FilterType {
    Include,
    Exclude,
    Disable,
}

impl Default for FilterType {
    fn default() -> Self {
        FilterType::Disable
    }
}

pub struct TreeConfig {
    pub filter_type: FilterType,
    pub filters: Option<Vec<Regex>>,
    pub dir_color: Option<Color>,
    pub file_color: Option<Color>,
    pub tree_color: Option<Color>,
}
impl Default for TreeConfig {
    fn default() -> Self {
        TreeConfig {
            filter_type: FilterType::Disable,
            filters: None,
            dir_color: Some(Color::Blue),
            file_color: Some(Color::White),
            tree_color: Some(Color::Green),
        }
    }
}

impl TreeConfig {
    pub fn nocolor() -> Self {
        TreeConfig {
            filter_type: FilterType::Disable,
            filters: None,
            dir_color: None,
            file_color: None,
            tree_color: None,
        }
    }

    pub fn colored_filter(filter_useage: FilterType, filters: &Vec<Regex>) -> Self {
        let mut ret = TreeConfig::default();
        ret.filter_type = filter_useage;
        ret.filters = Some(filters.clone());
        ret
    }

    fn print_dirs(&self, input: String) -> String {
        match self.dir_color.as_ref() {
            Some(c) => input.color(*c).to_string(),
            None => input,
        }
    }

    fn print_files(&self, input: String) -> String {
        match self.file_color.as_ref() {
            Some(c) => input.color(*c).to_string(),
            None => input,
        }
    }

    fn print_tree(&self, input: String) -> String {
        match self.tree_color.as_ref() {
            Some(c) => input.color(*c).to_string(),
            None => input,
        }
    }
}
fn traverse_dir(
    dir: &Path,
    left_space: usize,
    depth: usize,
    config: &TreeConfig,
    is_top_last: bool,
    result: &mut String,
) -> Result<(), Box<dyn Error>> {
    let entries: Vec<_> = dir.read_dir()?.filter_map(Result::ok).collect();
    let mut total = entries.len();
    let mut entries_filtered: Vec<DirEntry> = Vec::with_capacity(total);
    if config.filter_type == FilterType::Disable
        || config.filters.is_none()
        || (config.filters.is_some() && config.filters.as_ref().unwrap().is_empty())
    {
        entries_filtered = entries;
    } else {
        for entry in entries {
            let path = entry.path();
            let exclude_filter = config.filters.as_ref().unwrap();
            match config.filter_type {
                //This should be impossible to reach
                FilterType::Disable => {}
                FilterType::Include => {
                    if exclude_filter
                        .iter()
                        .all(|regex| !regex.is_match(path.to_string_lossy().as_ref()))
                    {
                        entries_filtered.push(entry);
                    }
                }
                FilterType::Exclude => {
                    if !exclude_filter
                        .iter()
                        .any(|regex| regex.is_match(path.to_string_lossy().as_ref()))
                    {
                        entries_filtered.push(entry);
                    }
                }
            }
        }
    }
    total = entries_filtered.len();
    for (i, entry) in entries_filtered.into_iter().enumerate() {
        let path = entry.path();

        let print_path = {
            if path.is_file() && path.extension() == Some(OsStr::new("gpg")) {
                path.with_extension("")
            } else {
                path.clone()
            }
        };

        let file_name = print_path
            .file_name()
            .ok_or_else(|| IOErr::new(IOErrType::InvalidPath, &path))?
            .to_string_lossy();
        let is_local_last = i == total - 1;

        let mut prefix: String = String::new();
        for _ in 0..left_space {
            prefix.push_str("    ");
        }
        if is_top_last {
            for _ in 0..depth {
                prefix.push_str("    ");
            }
        } else {
            for _ in 0..depth {
                prefix.push_str("│   ");
            }
        }
        if is_local_last {
            prefix.push_str("└── ");
        } else {
            prefix.push_str("├── ");
        }

        if path.is_symlink() {
            let link = path.read_link()?;
            let link_str = link.to_string_lossy();
            result.push_str(&format!("{}{} -> {}\n", prefix, file_name, link_str));
            traverse_dir(&link, left_space + 1, 0, config, false, result)?; //TODO: really false?
            continue;
        } else {
            result.push_str(&format!("{}{}\n", prefix, file_name));
        }

        if path.is_dir() {
            traverse_dir(
                &path,
                left_space,
                depth + 1,
                config,
                is_top_last || (depth == 0 && is_local_last),
                result,
            )?;
        }
    }
    Ok(())
}

pub(crate) fn tree_directory(root: &Path, config: &TreeConfig) -> Result<String, Box<dyn Error>> {
    let mut real_root = root.to_path_buf();

    while real_root.is_symlink() {
        real_root = real_root.read_link()?;
    }

    if !real_root.is_dir() {
        return Err(IOErr::new(IOErrType::ExpectDir, &real_root).into());
    }

    let mut result = String::new();
    traverse_dir(&real_root, 0, 0, config, false, &mut result)?;

    if result.ends_with('\n') {
        result.pop();
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;
    use tests::test_utils::defer_cleanup;

    use super::*;
    use crate::util::fs_utils::create_symlink;
    use crate::util::test_utils;
    use crate::util::test_utils::{create_dir_structure, gen_unique_temp_dir};

    #[test]
    fn tree_normal_case() {
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
                let result = tree_directory(&root, &TreeConfig::nocolor()).unwrap();
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
                let mut config = TreeConfig::nocolor();
                config.filter_type = FilterType::Exclude;
                config.filters =
                    Some(vec![Regex::new(r"dir2").unwrap(), Regex::new(r"file1").unwrap()]);
                let result = tree_directory(&root, &config).unwrap();
                assert_eq!(
                    result,
                    r#"├── dir1
└── dir3"#
                );

                // This case, nothing should be filtered
                config.filters = None;
                let result = tree_directory(&root, &config).unwrap();
                assert_eq!(
                    result,
                    r#"├── dir1
│   └── file1
├── dir2
│   └── file2
└── dir3"#
                );

                // This case, everything should be filtered
                config.filters = Some(vec![
                    Regex::new(r"dir1").unwrap(),
                    Regex::new(r"dir2").unwrap(),
                    Regex::new(r"dir3").unwrap(),
                ]);
                let result = tree_directory(&root, &config).unwrap();
                assert_eq!(result, "");
            },
            {
                test_utils::cleanup_test_dir(&root);
            }
        )
    }

    #[test]
    fn test_symbolic_link() {
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

        let result = tree_directory(&root1, &TreeConfig::nocolor()).unwrap();
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

        test_utils::cleanup_test_dir(&root1);
        test_utils::cleanup_test_dir(&root2);

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

        let result = tree_directory(&root1, &TreeConfig::nocolor()).unwrap();
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

        test_utils::cleanup_test_dir(&root1);
        test_utils::cleanup_test_dir(&root2);
    }
}
