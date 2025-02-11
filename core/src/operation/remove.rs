use std::error::Error;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use crate::util::fs_util::is_subpath_of;
use crate::{IOErr, IOErrType};

fn remove_dir_recursive<E>(dir: &Path, stderr: &mut E) -> io::Result<()>
where
    E: Write,
{
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let entry_path = entry.path();

        if entry_path.is_dir() {
            remove_dir_recursive(&entry_path, stderr)?;
        } else {
            fs::remove_file(&entry_path)?;
            writeln!(stderr, "Removed file '{}'", entry_path.display())?;
        }
    }

    fs::remove_dir(dir)?;
    writeln!(stderr, "Removed directory '{}'", dir.display())?;
    Ok(())
}

pub fn remove_io<I, O, E>(
    root: &Path,
    dist: &str,
    recursive: bool,
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
    let mut dist_path = {
        if Path::new(dist).is_absolute() {
            PathBuf::from(dist)
        } else {
            root.join(dist)
        }
    };

    if !is_subpath_of(root, &dist_path)? {
        return Err(format!(
            "'{}' is not the sub-path of the root path '{}'",
            dist,
            root.display()
        )
        .into());
    }

    if !dist_path.exists() {
        let with_extension = dist_path.with_extension("gpg");
        if !with_extension.exists() {
            return if force {
                Ok(())
            } else {
                writeln!(stderr, "Cannot remove '{}': No such file or directory", dist)?;
                Err(IOErr::new(IOErrType::PathNotExist, &dist_path).into())
            };
        }
        dist_path = with_extension;
    }

    let confirm_msg = format!(
        "Are you sure you would like to delete {} at storage {}? [y/N]",
        dist_path.display(),
        root.display()
    );
    if !force {
        writeln!(stdout, "{}", confirm_msg)?;
        let mut input = String::new();
        stdin.read_to_string(&mut input)?;
        if !input.trim().to_lowercase().starts_with('y') {
            return Ok(());
        }
    }

    if dist_path.is_file() {
        fs::remove_file(&dist_path)?;
        writeln!(stderr, "Removed '{}'", dist)?;
    } else if dist_path.is_dir() {
        if recursive {
            remove_dir_recursive(&dist_path, stderr)?;
        } else {
            let err_msg = format!("Cannot remove '{}': Is a directory.", dist);
            writeln!(stderr, "{}", err_msg)?;
            return Err(IOErr::new(IOErrType::ExpectFile, &dist_path).into());
        }
    } else {
        let err_msg = format!("Cannot remove '{}': Not a file or directory.", dist);
        writeln!(stderr, "{}", err_msg)?;
        return Err(IOErr::new(IOErrType::InvalidFileType, &dist_path).into());
    }

    Ok(())
}

#[cfg(test)]
mod test {
    use core::panic;
    use std::thread::sleep;
    use std::time::Duration;
    use std::{io, thread};

    use os_pipe::pipe;
    use pretty_assertions::assert_eq;

    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::fs_util::set_readonly;
    use crate::util::test_util::{create_dir_structure, gen_unique_temp_dir};

    fn enter_input_with_delay<T>(
        input_str: &str,
        delay: Duration,
        mut stdin_writer: T,
    ) -> thread::JoinHandle<()>
    where
        T: Write + Send + 'static,
    {
        let input = input_str.to_string();
        thread::spawn(move || {
            sleep(delay);
            stdin_writer.write_all(input.as_bytes()).unwrap();
        })
    }

    #[test]
    fn test_remove_io() {
        // Origin structure:
        // root
        // ├── dir1
        // │   ├── file1
        // │   └── file2
        // ├ file3
        // └ dir2
        let (_tmp_dir, root) = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(Some("dir1"), &["file1", "file2"]), (Some("dir2"), &[]), (None, &["file3"])];
        create_dir_structure(&root, structure);
        set_readonly(&root.join("file3"), true).unwrap();
        set_readonly(&root.join("dir1").join("file1"), true).unwrap();

        cleanup!(
            {
                let mut stdout = io::stdout().lock();
                let mut stderr = io::stderr().lock();

                // Test remove a file
                let dist = "file3";
                let (mut stdin, stdin_w) = pipe().unwrap();
                let input_thread =
                    enter_input_with_delay("n\n", Duration::from_millis(100), stdin_w);
                remove_io(&root, dist, false, false, &mut stdin, &mut stdout, &mut stderr).unwrap();
                assert_eq!(true, root.join(dist).exists());
                input_thread.join().unwrap();

                remove_io(&root, dist, false, true, &mut stdin, &mut stdout, &mut stderr).unwrap();
                assert_eq!(false, root.join(dist).exists());

                // Test remove a directory
                // Remove an empty directory, without recursive option
                let dist = "dir2";
                let (mut stdin, stdin_w) = pipe().unwrap();
                let input_thread =
                    enter_input_with_delay("y\n", Duration::from_millis(100), stdin_w);
                if let Ok(_) =
                    remove_io(&root, dist, false, false, &mut stdin, &mut stdout, &mut stderr)
                {
                    panic!("Expect fail to remove a non-empty directory without recursive option.");
                }
                input_thread.join().unwrap();

                // With recursive option
                let (mut stdin, stdin_w) = pipe().unwrap();
                let input_thread =
                    enter_input_with_delay("y\n", Duration::from_millis(100), stdin_w);
                remove_io(&root, dist, true, false, &mut stdin, &mut stdout, &mut stderr).unwrap();
                assert_eq!(false, root.join(dist).exists());
                input_thread.join().unwrap();

                // Remove a non-empty directory with some read-only files, without force option
                let dist = "dir1";
                let (mut stdin, stdin_w) = pipe().unwrap();
                let input_thread =
                    enter_input_with_delay("y\n", Duration::from_millis(100), stdin_w);
                remove_io(&root, dist, true, false, &mut stdin, &mut stdout, &mut stderr).unwrap();
                assert_eq!(false, root.join(dist).exists());
                input_thread.join().unwrap();

                // Test remove a non-exist file
                let dist = "non-exist-file";
                let (mut stdin, stdin_w) = pipe().unwrap();
                let input_thread =
                    enter_input_with_delay("y\n", Duration::from_millis(100), stdin_w);
                if let Ok(_) =
                    remove_io(&root, dist, false, false, &mut stdin, &mut stdout, &mut stderr)
                {
                    panic!("Expect to fail to remove a non-exist file without force option.");
                }
                input_thread.join().unwrap();

                // With force option
                let (mut stdin, stdin_w) = pipe().unwrap();
                let input_thread =
                    enter_input_with_delay("y\n", Duration::from_millis(100), stdin_w);
                remove_io(&root, dist, false, true, &mut stdin, &mut stdout, &mut stderr).unwrap();
                input_thread.join().unwrap();
            },
            {}
        )
    }
}
