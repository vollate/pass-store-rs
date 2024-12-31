use std::error::Error;
use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::str::from_utf8;
use std::{fs, path};

use crate::util::fs_utils::get_path_separator;
use crate::{IOErr, IOErrType};

pub fn rename_io<I, O, E>(
    root: &Path,
    from: &str,
    to: &str,
    extension: &str,
    force: bool,
    stdin: I,
    stdout: O,
    stderr: E,
) -> Result<(), Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    let from_path = root.join(from);
    let to_path = root.join(to);
    if !from_path.exists() {
        return Err(IOErr::new(IOErrType::PathNotExist, &from_path).into());
    }
    todo!()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::io::{self, Read, Write};

    use pretty_assertions::{assert_eq, assert_ne};

    use super::*;
    use crate::util::fs_utils::get_path_separator;
    use crate::util::test_utils::{cleanup_test_dir, create_dir_structure, gen_unique_temp_dir};
    #[test]
    fn normal_tests() {
        let stdin = io::stdin();
        let stdout = io::stdout();
        let stderr = io::stderr();

        // Original structure:
        // root
        // ├── a.gpg
        // ├── foo/
        // └── b.gpg
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(None, &["a.gpg", "b.gpg"][..]), (Some("foo"), &[][..])];
        create_dir_structure(&root, structure);

        // Rename a.gpg to c.gpg
        rename_io(&root, "a", "c", "gpg", false, stdin.lock(), stdout.lock(), stderr.lock())
            .unwrap();
        assert_eq!(false, root.join("a.gpg").exists());
        assert_eq!(true, root.join("c.gpg").exists());

        // Rename b.gpg to c.gpg, without force
        println!("There should be an interact confirm, chose no");
        if let Ok(_) =
            rename_io(&root, "b", "c", "gpg", false, stdin.lock(), stdout.lock(), stderr.lock())
        {
            panic!("Should not rename b.gpg to c.gpg without force option");
        }

        // Rename b.gpg to c.gpg, with force
        rename_io(&root, "b", "c", "gpg", true, stdin.lock(), stdout.lock(), stderr.lock())
            .unwrap();
        assert_eq!(false, root.join("b.gpg").exists());
        assert_eq!(true, root.join("c.gpg").exists());

        // Now, try to rename file into a dir(end with path separator)
        rename_io(
            &root,
            "c",
            &format!("foo{}", get_path_separator()),
            "gpg",
            false,
            stdin.lock(),
            stdout.lock(),
            stderr.lock(),
        )
        .unwrap();
        assert_eq!(false, root.join("c.gpg").exists());
        assert_eq!(true, root.join("foo").join("c.gpg").exists());

        cleanup_test_dir(&root);
        //TODO: check more? really necessary?
    }
}
