use std::error::Error;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::{fs, path};

use crate::util::fs_utils::{better_rename, copy_dir_recursive, is_subpath_of};
use crate::{IOErr, IOErrType};

// Currently, we do not support cross repo rename/copy
fn handle_overwrite_delete<I, O, E>(
    path_to_overwrite: &Path,
    force: bool,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<bool, Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    if !force {
        stdout.write_fmt(format_args!(
            "File {} already exists, overwrite? [y/N]: ",
            path_to_overwrite.to_string_lossy()
        ))?;
        stdout.flush()?;
        let mut input = String::new();
        stdin.read_to_string(&mut input)?;
        if !input.trim().to_lowercase().starts_with('y') {
            stdout.write_all("Canceled\n".as_bytes())?;
            return Ok(false);
        }
    }
    if path_to_overwrite.is_file() {
        fs::remove_file(path_to_overwrite)?;
    } else if path_to_overwrite.is_dir() {
        fs::remove_dir_all(path_to_overwrite)?;
    }
    Ok(true)
}

fn copy_rename_file<I, O, E>(
    copy: bool,
    from: &Path,
    to: &Path,
    extension: &str,
    force: bool,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<(), Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    let file_name =
        from.file_name().ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, from))?;

    // assume to is a directory
    if to.exists() {
        return if to.is_dir() {
            let sub_file = to.join(file_name).with_extension(extension);
            if sub_file.exists() {
                if !handle_overwrite_delete(&sub_file, force, stdin, stdout, stderr)? {
                    return Ok(());
                }
            }
            if copy {
                fs::copy(from, sub_file)?;
            } else {
                better_rename(from.with_extension(extension), sub_file)?;
            }
            Ok(())
        } else {
            Err(IOErr::new(IOErrType::InvalidFileType, to).into())
        };
    }

    // assume to is a file, append extension to it
    let to = to.with_extension(extension);
    if to.exists() {
        if to.is_file() {
            if !handle_overwrite_delete(&to, force, stdin, stdout, stderr)? {
                return Ok(());
            }
        } else {
            return Err(IOErr::new(IOErrType::InvalidFileType, &to).into());
        }
    }
    if copy {
        fs::copy(from, to)?;
    } else {
        better_rename(from.with_extension(extension), to)?;
    }
    Ok(())
}

fn copy_rename_dir<I, O, E>(
    copy: bool,
    from: &Path,
    to: &Path,
    force: bool,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<(), Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    let file_name =
        from.file_name().ok_or_else(|| IOErr::new(IOErrType::CannotGetFileName, from))?;
    if to.exists() {
        if to.is_dir() {
            let sub_dir = to.join(file_name);
            if sub_dir.exists() {
                if !handle_overwrite_delete(&sub_dir, force, stdin, stdout, stderr)? {
                    return Ok(());
                }
            }
            if copy {
                copy_dir_recursive(from, sub_dir)?;
            } else {
                better_rename(from, sub_dir)?;
            }
        } else if to.is_file() {
            if !handle_overwrite_delete(to, force, stdin, stdout, stderr)? {
                return Ok(());
            }
            if copy {
                copy_dir_recursive(from, to)?;
            } else {
                better_rename(from, to)?;
            }
        } else {
            return Err(IOErr::new(IOErrType::InvalidFileType, to).into());
        }
    }
    Ok(())
}

pub fn copy_rename_io<I, O, E>(
    copy: bool,
    root: &Path,
    from: &str,
    to: &str,
    extension: &str,
    force: bool,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<(), Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    let mut from_path = {
        if Path::new(from).is_absolute() {
            PathBuf::from(from)
        } else {
            root.join(from)
        }
    };

    if !is_subpath_of(root, &from_path)? {
        let err_msg = format!("'{}' is not the subpath of the root path '{}'", to, root.display());
        writeln!(stderr, "{}", err_msg)?;
        return Err(err_msg.into());
    }
    if !from_path.exists() {
        let try_path = from_path.with_extension(extension);
        if !try_path.exists() {
            return Err(IOErr::new(IOErrType::PathNotExist, &from_path).into());
        }
        from_path = try_path;
    }

    let to_path = root.join(to);
    if !is_subpath_of(root, &to_path)? {
        let err_msg = format!("'{}' is not the subpath of the root path '{}'", to, root.display());
        writeln!(stderr, "{}", err_msg)?;
        return Err(err_msg.into());
    }

    let to_is_dir = to.ends_with(path::MAIN_SEPARATOR);
    if to_is_dir {
        if !to_path.exists() || !to_path.is_dir() {
            writeln!(
                stderr,
                "Cannot {} '{}' to '{}': No such directory",
                if copy { "copy" } else { "rename" },
                from,
                to
            )?;
            return Err(IOErr::new(IOErrType::PathNotExist, &to_path).into());
        }
    }

    if from_path.is_file() {
        copy_rename_file(copy, &from_path, &to_path, extension, force, stdin, stdout, stderr)
    } else if from_path.is_dir() {
        copy_rename_dir(copy, &from_path, &to_path, force, stdin, stdout, stderr)
    } else {
        Err(IOErr::new(IOErrType::InvalidFileType, &from_path).into())
    }
}

#[cfg(test)]
mod tests {
    use std::io::{self};
    use std::thread::{self, sleep};

    use os_pipe::pipe;
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::test_utils::{cleanup_test_dir, create_dir_structure, gen_unique_temp_dir};
    #[test]
    fn rename_tests() {
        let (mut stdin, mut stdin_w) = pipe().unwrap();
        let mut stdout = io::stdout().lock();
        let mut stderr = io::stderr().lock();

        // Original structure:
        // root
        // ├── a.gpg
        // ├── d_dir/
        // ├── e_dir/
        // └── b.gpg
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(None, &["a.gpg", "b.gpg"][..]), (Some("d_dir"), &[][..]), (Some("e_dir"), &[][..])];
        create_dir_structure(&root, structure);

        // Rename a.gpg to c.gpg
        copy_rename_io(false, &root, "a", "c", "gpg", false, &mut stdin, &mut stdout, &mut stderr)
            .unwrap();
        assert_eq!(false, root.join("a.gpg").exists());
        assert_eq!(true, root.join("c.gpg").exists());

        // Rename b.gpg to c.gpg, without force, input "n" interactively
        thread::spawn(move || {
            sleep(std::time::Duration::from_millis(100));
            stdin_w.write_all(b"n\n").unwrap();
        });
        copy_rename_io(false, &root, "b", "c", "gpg", false, &mut stdin, &mut stdout, &mut stderr)
            .unwrap();
        assert_eq!(true, root.join("b.gpg").exists());

        // Rename b.gpg to c.gpg, with force
        copy_rename_io(false, &root, "b", "c", "gpg", true, &mut stdin, &mut stdout, &mut stderr)
            .unwrap();
        assert_eq!(false, root.join("b.gpg").exists());
        assert_eq!(true, root.join("c.gpg").exists());

        // Now, try to rename file into a dir(end with path separator)
        copy_rename_io(
            false,
            &root,
            "c",
            &format!("d_dir{}", std::path::MAIN_SEPARATOR_STR),
            "gpg",
            false,
            &mut stdin,
            &mut stdout,
            &mut stderr,
        )
        .unwrap();
        assert_eq!(false, root.join("c.gpg").exists());
        assert_eq!(true, root.join("d_dir").join("c.gpg").exists());

        // Try to rename d_dir to e_dir, should be e_dir/d_dir
        copy_rename_io(
            false,
            &root,
            "d_dir",
            "e_dir",
            "gpg",
            false,
            &mut stdin,
            &mut stdout,
            &mut stderr,
        )
        .unwrap();
        assert_eq!(false, root.join("d_dir").exists());
        assert_eq!(true, root.join("e_dir").join("d_dir").exists());

        cleanup_test_dir(&root);
    }

    #[test]
    fn copy_tests() {
        let (mut stdin, mut stdin_w) = pipe().unwrap();
        let mut stdout = io::stdout().lock();
        let mut stderr = io::stderr().lock();

        // Original structure:
        // root
        // ├── a.gpg
        // ├── d_dir/
        // ├── e_dir/
        // └── b.gpg
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(None, &["a.gpg", "b.gpg"][..]), (Some("d_dir"), &[][..]), (Some("e_dir"), &[][..])];
        create_dir_structure(&root, structure);

        // Copy a.gpg to c.gpg
        fs::write(root.join("a.gpg"), "foo_a").unwrap();
        assert_eq!(false, root.join("c.gpg").exists());
        copy_rename_io(true, &root, "a", "c", "gpg", false, &mut stdin, &mut stdout, &mut stderr)
            .unwrap();
        assert_eq!(true, root.join("a.gpg").exists());
        assert_eq!(true, root.join("c.gpg").exists());
        assert_eq!("foo_a", fs::read_to_string(root.join("c.gpg")).unwrap());

        // Copy b.gpg to c.gpg, without force, input "n" interactively
        fs::write(root.join("b.gpg"), "foo_b").unwrap();
        thread::spawn(move || {
            sleep(std::time::Duration::from_millis(100));
            stdin_w.write_all(b"n\n").unwrap();
        });
        copy_rename_io(true, &root, "b", "c", "gpg", false, &mut stdin, &mut stdout, &mut stderr)
            .unwrap();
        assert_ne!("foo_b", fs::read_to_string(root.join("c.gpg")).unwrap());

        // Copy b.gpg to c.gpg, with force, overwrite the content of c.gpg
        copy_rename_io(true, &root, "b", "c", "gpg", true, &mut stdin, &mut stdout, &mut stderr)
            .unwrap();
        assert_eq!("foo_b", fs::read_to_string(root.join("c.gpg")).unwrap());

        // Now, try to copy file into a dir(end with path separator)
        fs::write(root.join("c.gpg"), "foo_c").unwrap();
        copy_rename_io(
            true,
            &root,
            "c",
            &format!("d_dir{}", std::path::MAIN_SEPARATOR_STR),
            "gpg",
            false,
            &mut stdin,
            &mut stdout,
            &mut stderr,
        )
        .unwrap();
        assert_eq!(true, root.join("c.gpg").exists());
        assert_eq!("foo_c", fs::read_to_string(root.join("c.gpg")).unwrap());

        // Try to copy d_dir to e_dir, should be e_dir/d_dir
        copy_rename_io(
            true,
            &root,
            "d_dir",
            "e_dir",
            "gpg",
            false,
            &mut stdin,
            &mut stdout,
            &mut stderr,
        )
        .unwrap();
        assert_eq!(true, root.join("d_dir").exists());
        assert_eq!(true, root.join("e_dir").join("d_dir").exists());

        cleanup_test_dir(&root);
    }

    #[test]
    // Try to access parent directory, should be blocked
    fn path_attack_protection_test() {
        let mut stdin = io::stdin().lock();
        let mut stdout = io::stdout().lock();
        let mut stderr = io::stderr().lock();

        // Simple structure:
        // root
        // └── a.gpg
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] = &[(None, &["a.gpg"][..])];
        if let Ok(_) = copy_rename_io(
            false,
            &root,
            "../../a",
            "c",
            "gpg",
            false,
            &mut stdin,
            &mut stdout,
            &mut stderr,
        ) {
            panic!("Should not be able to access parent directory: {}/../../a", root.display());
        }
        if let Ok(_) = copy_rename_io(
            false,
            &root,
            "a",
            "../../c",
            "gpg",
            false,
            &mut stdin,
            &mut stdout,
            &mut stderr,
        ) {
            panic!("Should not be able to access parent directory: {}/../../c", root.display());
        }
    }
}
