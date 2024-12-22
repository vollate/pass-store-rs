use std::error::Error;
use std::fs::DirEntry;
use std::path::Path;

use regex::Regex;

use crate::gpg::GPGErr;
use crate::IOErr;

fn traverse_dir(
    dir: &Path,
    depth: usize,
    exclude: &Vec<Regex>,
    is_top_last: bool,
    result: &mut String,
) -> Result<(), Box<dyn Error>> {
    let entries: Vec<_> = dir.read_dir()?.filter_map(Result::ok).collect();
    let mut total = entries.len();
    let mut entries_filtered: Vec<DirEntry> = Vec::with_capacity(total);
    for entry in entries {
        let path = entry.path();
        if exclude.iter().any(|regex| regex.is_match(path.to_string_lossy().as_ref())) {
            continue;
        } else {
            entries_filtered.push(entry);
        }
    }
    //TODO: support color and custom
    total = entries_filtered.len();
    for (i, entry) in entries_filtered.into_iter().enumerate() {
        let path = entry.path();

        let file_name = path.file_name().ok_or_else(|| IOErr::InvalidPath)?.to_string_lossy();
        let is_local_last = i == total - 1;

        let mut prefix: String = String::new();
        if depth + 1 > 0 {
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
        }

        result.push_str(&format!("{}{}\n", prefix, file_name));

        if path.is_dir() {
            traverse_dir(
                &path,
                depth + 1,
                exclude,
                is_top_last || (depth == 0 && is_local_last),
                result,
            )?;
        }
    }
    if is_top_last && result.ends_with("\n") {
        result.pop();
    }

    Ok(())
}

pub(crate) fn tree_except(root: &Path, exclude: &Vec<Regex>) -> Result<String, Box<dyn Error>> {
    let mut real_root = root.to_path_buf();
    while real_root.is_symlink() {
        real_root = real_root.read_link()?;
    }
    if !real_root.is_dir() {
        return Err(IOErr::ExpectDir.into());
    }
    let mut result = String::new();
    traverse_dir(&real_root, 0, exclude, false, &mut result)?;
    Ok(result)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;

    use pretty_assertions::assert_eq;

    use super::*;
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

        let result = tree_except(&root, &Vec::new()).unwrap();
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
    }

    fn test_filtered_case(){

        let root = gen_unique_temp_dir();
    }
    //TODO: test filter excludition
}
