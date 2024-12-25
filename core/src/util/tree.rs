use std::error::Error;
use std::fs::DirEntry;
use std::path::Path;

use colored::{Color, Colorize};
use regex::Regex;

use crate::IOErr;

pub struct TreeColorConfig {
    pub dir_color: Option<Color>,
    pub file_color: Option<Color>,
    pub tree_color: Option<Color>,
}
impl TreeColorConfig {
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
    start_level: usize,
    depth: usize,
    exclude_filter: &Vec<Regex>,
    // color_cfg: &Option<TreeColorConfig>,//TODO: customize print
    enable_color: bool,
    is_top_last: bool,
    result: &mut String,
) -> Result<(), Box<dyn Error>> {
    let entries: Vec<_> = dir.read_dir()?.filter_map(Result::ok).collect();
    let mut total = entries.len();
    let mut entries_filtered: Vec<DirEntry> = Vec::with_capacity(total);
    for entry in entries {
        let path = entry.path();
        if exclude_filter.iter().any(|regex| regex.is_match(path.to_string_lossy().as_ref())) {
            continue;
        } else {
            entries_filtered.push(entry);
        }
    }
    total = entries_filtered.len();
    for (i, entry) in entries_filtered.into_iter().enumerate() {
        let path = entry.path();

        let file_name = path.file_name().ok_or_else(|| IOErr::InvalidPath)?.to_string_lossy();
        let is_local_last = i == total - 1;

        let mut prefix: String = String::new();
        for _ in 0..start_level {
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

        let sym_path = path.is_symlink();
        if sym_path {
            let link = path.read_link()?;
            let link_str = link.to_string_lossy();
            result.push_str(&format!("{}{} -> {}\n", prefix, file_name, link_str));
            traverse_dir(&link, start_level + 1, 0, exclude_filter, enable_color, false, result)?;
            continue;
        } else {
            result.push_str(&format!("{}{}\n", prefix, file_name));
        }

        if path.is_dir() {
            traverse_dir(
                &path,
                start_level,
                depth + 1,
                exclude_filter,
                enable_color,
                is_top_last || (depth == 0 && is_local_last),
                result,
            )?;
        }
    }
    Ok(())
}

pub(crate) fn tree_with_filter(
    root: &Path,
    exclude_filter: &Vec<Regex>,
    start_level: usize,
    enable_color: bool,
) -> Result<String, Box<dyn Error>> {
    let mut real_root = root.to_path_buf();
    while real_root.is_symlink() {
        real_root = real_root.read_link()?;
    }
    if !real_root.is_dir() {
        return Err(IOErr::ExpectDir.into());
    }
    let mut result = String::new();
    traverse_dir(&real_root, start_level, 0, exclude_filter, enable_color, false, &mut result)?;
    if result.ends_with('\n') {
        result.pop();
    }
    Ok(result)
}

#[cfg(test)]
mod tests {

    use std::fs;
    use std::path::Path;

    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util;
    use crate::util::test_utils::gen_unique_temp_dir;

    fn create_structure(base: &Path, structure: &[(&str, &[&str])]) {
        for (dir, files) in structure {
            let dir_path = base.join(dir);
            fs::create_dir_all(&dir_path).unwrap();
            for file in *files {
                fs::File::create(dir_path.join(file)).unwrap();
            }
        }
    }

    fn remove_test_dir(base: &Path) {
        fs::remove_dir_all(base).unwrap();
    }
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
        let structure: &[(&str, &[&str])] = &[
            ("dir1", &["file1", "file2"][..]),
            ("dir2", &["file3", "file4"][..]),
            ("dir3", &["file5"][..]),
            ("dir3/dir4", &[][..]),
            ("dir3/dir4/dir5", &[][..]),
        ];
        create_structure(&root, &structure);

        let result = tree_with_filter(&root, &Vec::new(), 0, false).unwrap();
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
        remove_test_dir(&root);
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
        let structure: &[(&str, &[&str])] =
            &[("dir1", &["file1"][..]), ("dir2", &["file2"][..]), ("dir3", &[][..])];
        create_structure(&root, &structure);

        // This case, only dir2 and file1 should be filtered
        let result = tree_with_filter(
            &root,
            &vec![Regex::new(r"dir2").unwrap(), Regex::new(r"file1").unwrap()],
            0,
            false,
        )
        .unwrap();
        assert_eq!(
            result,
            r#"├── dir1
└── dir3"#
        );

        // This case, nothing should be filtered
        let result =
            tree_with_filter(&root, &vec![Regex::new(r"dir114514").unwrap()], 0, false).unwrap();
        assert_eq!(
            result,
            r#"├── dir1
│   └── file1
├── dir2
│   └── file2
└── dir3"#
        );

        // This case, everything should be filtered
        let result = tree_with_filter(
            &root,
            &vec![
                Regex::new(r"dir1").unwrap(),
                Regex::new(r"dir2").unwrap(),
                Regex::new(r"dir3").unwrap(),
            ],
            0,
            false,
        )
        .unwrap();
        assert_eq!(result, "");

        remove_test_dir(&root);
    }

    #[test]
    fn test_symbolic_link() {
        // Create directory structure as below:
        // root1
        // ├── dir1
        // │   └── file1
        // └── dir2 -> root2
        // --------------------------------
        // root2
        // ├── dir3
        // │   └── file2
        // └── dir4

        let root1 = gen_unique_temp_dir();
        let root2 = gen_unique_temp_dir();
        let structure1: &[(&str, &[&str])] = &[("dir1", &["file1"][..])];
        let structure2: &[(&str, &[&str])] = &[("dir3", &["file2"][..]), ("dir4", &[][..])];
        create_structure(&root1, &structure1);
        create_structure(&root2, &structure2);
        util::fs_utils::create_symlink(&root2, &root1.join("dir2")).unwrap();

        let result = tree_with_filter(&root1, &Vec::new(), 0, false).unwrap();
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

        remove_test_dir(&root1);
        remove_test_dir(&root2);
    }
}
