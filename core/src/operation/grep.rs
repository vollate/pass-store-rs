use std::error::Error;
use std::path::Path;

use secrecy::ExposeSecret;
use walkdir::WalkDir;

use crate::pgp::PGPClient;
use crate::util::fs_util::path_to_str;

pub fn grep(client: &PGPClient, root: &Path, target: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let mut results = Vec::new();

    for entry in WalkDir::new(root) {
        let entry = entry?;
        if entry.file_type().is_file() {
            let relative_path = entry.path().strip_prefix(root)?;
            let relative_path_str = relative_path.to_string_lossy();

            let decrypted = client.decrypt_stdin(&root, path_to_str(entry.path())?)?;

            let matching_lines: Vec<String> = decrypted
                .expose_secret()
                .lines()
                .filter(|line| line.contains(target))
                .map(|s| s.to_string())
                .collect();

            if relative_path_str.contains(target) || !matching_lines.is_empty() {
                results.push(format!("{}:", relative_path_str));
                results.extend(matching_lines);
            }
        }
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use pretty_assertions::assert_eq;
    use serial_test::serial;
    use tempfile::TempDir;

    use super::*;
    use crate::util::defer::cleanup;
    use crate::util::test_util::*;

    fn setup_test_environment() -> (String, String, PGPClient, TempDir, PathBuf) {
        let executable = get_test_executable();
        let email = get_test_email();
        let username = get_test_username();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        let file1_content = "test password\nfoo bar\nsecret content\nnullptr";
        let file2_content = "another password\ntest line\nmore content";

        let structure: &[(Option<&str>, &[&str])] =
            &[(Some("dir1"), &[][..]), (Some("dir2"), &[][..])];
        create_dir_structure(&root, structure);

        let mut test_client =
            PGPClient::new(executable.clone(), None, Some(username), Some(email.clone()));

        test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        test_client.update_info().unwrap();
        test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();

        test_client
            .encrypt(file1_content, root.join("dir1/test_pass.gpg").to_str().unwrap())
            .unwrap();
        test_client
            .encrypt(file2_content, root.join("dir2/normal_file.gpg").to_str().unwrap())
            .unwrap();

        (executable, email, test_client, _tmp_dir, root)
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_grep_content_match() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let results = grep(&test_client, &root, "null").unwrap();
                assert_eq!(results, vec!["dir1/test_pass.gpg:", "nullptr"]);
            },
            {
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_grep_filename_match() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let results = grep(&test_client, &root, "secret").unwrap();
                assert_eq!(results, vec!["dir1/test_pass.gpg:", "secret content"]);
            },
            {
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_grep_no_matches() {
        let (executable, email, test_client, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let results = grep(&test_client, &root, "nonexistent").unwrap();
                assert!(results.is_empty());
            },
            {
                clean_up_test_key(&executable, &email).unwrap();
            }
        );
    }
}
