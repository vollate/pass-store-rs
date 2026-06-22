use std::fs;
use std::path::PathBuf;

use pars_core::gui::{list_entries, parse_entry_secret, EntryRef, EntryType, ListEntriesRequest};

fn create_file(path: PathBuf) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, "").unwrap();
}

#[test]
fn list_entries_returns_pass_files_and_directories_without_gpg_suffix() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::write(root.join(".gpg-id"), "alice@example.com\n").unwrap();
    create_file(root.join("work/dev/github.gpg"));
    create_file(root.join("finance/stripe.gpg"));
    create_file(root.join("README.md"));

    let entries = list_entries(ListEntriesRequest {
        root: root.to_path_buf(),
        target: None,
        recursive: true,
    })
    .unwrap();

    let paths = entries.iter().map(|entry| entry.path.as_str()).collect::<Vec<_>>();
    assert_eq!(paths, vec!["finance", "finance/stripe", "work", "work/dev", "work/dev/github"]);

    let github = entries.iter().find(|entry| entry.path == "work/dev/github").unwrap();
    assert_eq!(github.name, "github");
    assert_eq!(github.entry_type, EntryType::Password);
    assert_eq!(github.parent_path.as_deref(), Some("work/dev"));

    let work = entries.iter().find(|entry| entry.path == "work").unwrap();
    assert_eq!(work.entry_type, EntryType::Directory);
    assert_eq!(work.child_count, 1);
}

#[test]
fn entry_ref_rejects_path_traversal() {
    let temp = tempfile::tempdir().unwrap();
    let err = EntryRef::new(temp.path().to_path_buf(), "../outside").unwrap_err();

    assert!(err.to_string().contains("outside password store"));
}

#[test]
fn parse_entry_secret_keeps_first_line_as_password_and_preserves_raw_notes() {
    let secret = parse_entry_secret(
        "hunter2\nusername: alice\nurl: https://example.com\ncustom note\nproject=demo",
    );

    assert_eq!(secret.password, "hunter2");
    assert_eq!(secret.field_value("username"), Some("alice"));
    assert_eq!(secret.field_value("url"), Some("https://example.com"));
    assert_eq!(secret.raw_notes, "custom note\nproject=demo");
}
