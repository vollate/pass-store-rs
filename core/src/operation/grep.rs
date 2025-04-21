use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::path::Path;

use anyhow::Result;
use colored::{Color, Colorize};
use regex::Regex;
use secrecy::ExposeSecret;
use walkdir::WalkDir;

use crate::config::cli::PrintConfig;
use crate::pgp::PGPClient;
use crate::util::fs_util::{get_dir_gpg_id_content, path_to_str};
use crate::util::tree::string_to_color_opt;

#[derive(Default)]
pub struct GrepPrintConfig {
    pub grep_pass_color: Option<Color>,
    pub grep_match_color: Option<Color>,
}

impl<CFG: AsRef<PrintConfig>> From<CFG> for GrepPrintConfig {
    fn from(config: CFG) -> Self {
        Self {
            grep_pass_color: string_to_color_opt(&config.as_ref().grep_pass_color),
            grep_match_color: string_to_color_opt(&config.as_ref().grep_match_color),
        }
    }
}

pub fn grep_stream<O>(
    pgp_executable: &str,
    root: &Path,
    search_str: &str,
    print_cfg: &GrepPrintConfig,
    out_stream: &mut O,
) -> Result<()>
where
    O: Write,
{
    let mut cache: Vec<(u64, Vec<String>, PGPClient)> = Vec::new();
    let search_regex = Regex::new(&regex::escape(search_str))?;

    for entry in WalkDir::new(root) {
        let entry = entry?;
        if entry.file_type().is_file() && entry.path().extension().unwrap_or_default() == "gpg" {
            let relative_path = entry.path().strip_prefix(root)?;
            let relative_path_str = path_to_str(relative_path)?;

            let mut keys_fpr = get_dir_gpg_id_content(root, entry.path())?;
            keys_fpr.sort();

            let mut hasher = DefaultHasher::new();
            keys_fpr.hash(&mut hasher);
            let key_hash = hasher.finish();

            let client: &mut PGPClient = if let Some((_, _, client)) = cache
                .iter_mut()
                .find(|(h, cached_keys, _)| *h == key_hash && *cached_keys == keys_fpr)
            {
                client
            } else {
                let new_client = PGPClient::new(
                    pgp_executable,
                    &keys_fpr.iter().map(String::as_str).collect::<Vec<_>>(),
                )?;
                cache.push((key_hash, keys_fpr.clone(), new_client));
                &mut cache.last_mut().unwrap().2
            };

            let decrypted = client.decrypt_stdin(root, path_to_str(entry.path())?)?;
            let mut has_matches = false;

            for line in decrypted.expose_secret().lines() {
                if line.contains(search_str) {
                    if !has_matches {
                        if let Some(color) = print_cfg.grep_pass_color {
                            writeln!(
                                out_stream,
                                "{}:",
                                &relative_path_str[..relative_path_str.len() - 4].color(color)
                            )?;
                        } else {
                            writeln!(
                                out_stream,
                                "{}:",
                                &relative_path_str[..relative_path_str.len() - 4]
                            )?;
                        }
                        has_matches = true;
                    }

                    let output_line = if let Some(color) = print_cfg.grep_match_color {
                        search_regex
                            .replace_all(line, |caps: &regex::Captures| {
                                caps[0].color(color).to_string()
                            })
                            .to_string()
                    } else {
                        line.to_string()
                    };
                    writeln!(out_stream, "{}", output_line)?;
                }
            }
        }
    }

    Ok(())
}

pub fn grep(
    pgp_executable: &str,
    root: &Path,
    search_str: &str,
    print_cfg: &GrepPrintConfig,
) -> Result<Vec<String>> {
    let mut results = Vec::new();
    let mut cache: Vec<(u64, Vec<String>, PGPClient)> = Vec::new();
    let search_regex = Regex::new(&regex::escape(search_str))?;

    for entry in WalkDir::new(root) {
        let entry = entry?;
        if entry.file_type().is_file() && entry.path().extension().unwrap_or_default() == "gpg" {
            let relative_path = entry.path().strip_prefix(root)?;
            let relative_path_str = path_to_str(relative_path)?;

            let mut keys_fpr = get_dir_gpg_id_content(root, entry.path())?;
            keys_fpr.sort();

            let mut hasher = DefaultHasher::new();
            keys_fpr.hash(&mut hasher);
            let key_hash = hasher.finish();

            let client: &mut PGPClient = if let Some((_, _, client)) = cache
                .iter_mut()
                .find(|(h, cached_keys, _)| *h == key_hash && *cached_keys == keys_fpr)
            {
                client
            } else {
                let new_client = PGPClient::new(
                    pgp_executable,
                    &keys_fpr.iter().map(String::as_str).collect::<Vec<_>>(),
                )?;
                cache.push((key_hash, keys_fpr.clone(), new_client));
                &mut cache.last_mut().unwrap().2
            };

            let decrypted = client.decrypt_stdin(root, path_to_str(entry.path())?)?;
            let matching_lines: Vec<String> = decrypted
                .expose_secret()
                .lines()
                .filter(|line| line.contains(search_str))
                .map(|line| {
                    if let Some(color) = print_cfg.grep_match_color {
                        search_regex
                            .replace_all(line, |caps: &regex::Captures| {
                                caps[0].color(color).to_string()
                            })
                            .to_string()
                    } else {
                        line.to_string()
                    }
                })
                .collect();

            if !matching_lines.is_empty() {
                if let Some(color) = print_cfg.grep_pass_color {
                    results.push(format!(
                        "{}:",
                        &relative_path_str[..relative_path_str.len() - 4].color(color)
                    ));
                } else {
                    results.push(format!("{}:", &relative_path_str[..relative_path_str.len() - 4]));
                }
                results.extend(matching_lines);
            }
        }
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use std::path::{self, PathBuf};

    use pretty_assertions::assert_eq;
    use serial_test::serial;
    use tempfile::TempDir;

    use super::*;
    use crate::pgp::key_management::key_gen_batch;
    use crate::util::defer::cleanup;
    use crate::util::test_util::*;

    fn setup_test_environment() -> (String, String, TempDir, PathBuf) {
        let executable = get_test_executable();
        let email = get_test_email();
        let (_tmp_dir, root) = gen_unique_temp_dir();

        let file1_content = "INF\n2112112";
        let file2_content = "Overlord\nNAN";

        let structure: &[(Option<&str>, &[&str])] =
            &[(Some("dir1"), &[][..]), (Some("dir2"), &[][..])];
        create_dir_structure(&root, structure);

        key_gen_batch(&executable, &gpg_key_gen_example_batch()).unwrap();
        let test_client = PGPClient::new(executable.clone(), &[&email]).unwrap();
        test_client.key_edit_batch(&gpg_key_edit_example_batch()).unwrap();

        test_client.encrypt(file1_content, root.join("dir1/01.gpg").to_str().unwrap()).unwrap();
        test_client.encrypt(file2_content, root.join("dir2/10.gpg").to_str().unwrap()).unwrap();
        write_gpg_id(&root, &test_client.get_keys_fpr());
        (executable, email, _tmp_dir, root)
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn grep_content_match() {
        let (executable, email, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let results = grep(&executable, &root, "211", &GrepPrintConfig::default()).unwrap();
                assert_eq!(results, vec![&format!("dir1{}01:", path::MAIN_SEPARATOR), "2112112"]);
            },
            {
                clean_up_test_key(&executable, &[&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn grep_filename_match() {
        let (executable, email, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let results =
                    grep(&executable, &root, "Overlord", &GrepPrintConfig::default()).unwrap();
                assert_eq!(results, vec![&format!("dir2{}10:", path::MAIN_SEPARATOR), "Overlord"]);

                let results = grep(&executable, &root, "01", &GrepPrintConfig::default()).unwrap();
                assert_eq!(results, Vec::<String>::new());
            },
            {
                clean_up_test_key(&executable, &[&email]).unwrap();
            }
        );
    }

    #[test]
    #[serial]
    #[ignore = "need run interactively"]
    fn grep_no_matches() {
        let (executable, email, _tmp_dir, root) = setup_test_environment();

        cleanup!(
            {
                let results =
                    grep(&executable, &root, "nonexistent", &GrepPrintConfig::default()).unwrap();
                assert!(results.is_empty());
            },
            {
                clean_up_test_key(&executable, &[&email]).unwrap();
            }
        );
    }
}
