use std::error::Error;
use std::fs::canonicalize;
use std::path::Path;

use secrecy::ExposeSecret;
use walkdir::WalkDir;

use crate::pgp::PGPClient;
use crate::util::fs_utils::path_to_str;

pub fn grep(client: &PGPClient, root: &Path, target: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let mut results = Vec::new();

    for entry in WalkDir::new(root) {
        let entry = entry?;
        if entry.file_type().is_file() {
            let relative_path = entry.path().strip_prefix(root)?;
            let relative_path_str = relative_path.to_string_lossy();

            let decrypted = client.decrypt_stdin(path_to_str(&canonicalize(&entry.path())?)?)?;

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

    use serial_test::serial;

    use crate::pgp::PGPClient;
    use crate::util::defer::cleanup;
    use crate::util::test_utils::{
        clean_up_test_key, cleanup_test_dir, create_dir_structure, gen_unique_temp_dir,
        get_test_email, get_test_executable, get_test_password, get_test_username,
        gpg_key_edit_example_batch, gpg_key_gen_example_batch,
    };

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn test_grep() {
        let executable = &get_test_executable();
        let email = &get_test_email();
        let root = gen_unique_temp_dir();
        let structure: &[(Option<&str>, &[&str])] =
            &[(Some("dir1"), &[][..]), (Some("dir2"), &[][..])];
        create_dir_structure(&root, &structure);

        cleanup!(
            {
                let mut test_client = PGPClient::new(
                    executable.to_string(),
                    None,
                    Some(get_test_username()),
                    Some(email.to_string()),
                );
                test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
                test_client.update_info().unwrap();
                test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();
            },
            {
                clean_up_test_key(executable, email).unwrap();
                cleanup_test_dir(&root);
            }
        );
    }
}
