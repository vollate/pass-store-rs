use std::fs;
use std::path::PathBuf;
use std::process::{self, Command, Stdio};

use pars_core::gui::{
    delete_entry, edit_entry, generate_entry, insert_entry, list_entries, move_entry,
    parse_entry_secret, read_entry, validate_git_args, DeleteEntryRequest, EditEntryRequest,
    EntryRef, EntryType, GenerateEntryRequest, GitOperationRequest, InsertEntryRequest,
    ListEntriesRequest, MoveEntryRequest, ReadEntryRequest,
};
use pars_core::pgp::key_management::key_gen_batch;
use pars_core::pgp::PGPClient;
use secrecy::ExposeSecret;
use serial_test::serial;

fn create_file(path: PathBuf) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, "").unwrap();
}

struct TestKey {
    executable: String,
    email: String,
}

impl Drop for TestKey {
    fn drop(&mut self) {
        let _ = Command::new(&self.executable)
            .args(["--batch", "--yes", "--delete-secret-and-public-keys", &self.email])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn test_pgp_executable() -> String {
    std::env::var("PASS_RS_TEST_EXECUTABLE").unwrap_or("gpg".into())
}

fn test_key_batch(email: &str) -> String {
    format!(
        r#"%echo Generating a GUI test key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Pars GUI Test
Name-Email: {email}
Expire-Date: 0
%no-protection
%commit
%echo Key generation complete
"#
    )
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

#[test]
fn git_operation_request_accepts_plain_git_args() {
    let temp = tempfile::tempdir().unwrap();
    let request = GitOperationRequest::new(
        temp.path().to_path_buf(),
        vec!["pull".to_string(), "--rebase".to_string()],
    )
    .unwrap();

    assert_eq!(request.args, vec!["pull", "--rebase"]);
}

#[test]
fn validate_git_args_rejects_shell_syntax() {
    let rejected_args = [
        vec!["status", ";", "rm"],
        vec!["status", "|", "cat"],
        vec!["status", "&&", "push"],
        vec!["status", ">", "out.txt"],
        vec!["status", "$(whoami)"],
    ];

    for args in rejected_args {
        let args = args.iter().map(|arg| arg.to_string()).collect::<Vec<_>>();
        let err = validate_git_args(&args).unwrap_err();
        assert!(err.to_string().contains("shell syntax is not allowed"));
    }
}

#[test]
fn delete_entry_removes_password_file_without_prompting() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    create_file(root.join("work/github.gpg"));

    let result = delete_entry(DeleteEntryRequest {
        entry: EntryRef::new(root.clone(), "work/github").unwrap(),
        recursive: false,
    })
    .unwrap();

    assert_eq!(result.deleted_path, "work/github");
    assert_eq!(result.deleted_type, EntryType::Password);
    assert!(!root.join("work/github.gpg").exists());
}

#[test]
fn delete_entry_requires_recursive_for_directories() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    create_file(root.join("work/github.gpg"));

    let err = delete_entry(DeleteEntryRequest {
        entry: EntryRef::new(root.clone(), "work").unwrap(),
        recursive: false,
    })
    .unwrap_err();

    assert!(err.to_string().contains("recursive=true"));
    assert!(root.join("work/github.gpg").exists());
}

#[test]
fn delete_entry_removes_directory_when_recursive_is_explicit() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    create_file(root.join("work/dev/github.gpg"));

    let result = delete_entry(DeleteEntryRequest {
        entry: EntryRef::new(root.clone(), "work").unwrap(),
        recursive: true,
    })
    .unwrap();

    assert_eq!(result.deleted_path, "work");
    assert_eq!(result.deleted_type, EntryType::Directory);
    assert!(!root.join("work").exists());
}

#[test]
#[serial]
fn insert_entry_encrypts_plain_content_without_prompting() {
    let executable = test_pgp_executable();
    let email = format!("pars-gui-insert-{}@rs.pass", process::id());
    let _key = TestKey { executable: executable.clone(), email: email.clone() };
    key_gen_batch(&executable, &test_key_batch(&email)).unwrap();

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    fs::write(root.join(".gpg-id"), format!("{email}\n")).unwrap();

    let result = insert_entry(InsertEntryRequest {
        entry: EntryRef::new(root.clone(), "work/github").unwrap(),
        content: "hunter2\nusername: alice\nurl: https://example.com".to_string(),
        overwrite: false,
        pgp_executable: executable.clone(),
    })
    .unwrap();

    assert_eq!(result.path, "work/github");
    assert!(root.join("work/github.gpg").exists());

    let client = PGPClient::new(&executable, &[&email]).unwrap();
    let decrypted = client.decrypt_stdin(&root, "work/github.gpg").unwrap();
    assert_eq!(decrypted.expose_secret(), "hunter2\nusername: alice\nurl: https://example.com");
}

#[test]
#[serial]
fn insert_entry_rejects_existing_file_without_overwrite() {
    let executable = test_pgp_executable();
    let email = format!("pars-gui-insert-conflict-{}@rs.pass", process::id());
    let _key = TestKey { executable: executable.clone(), email: email.clone() };
    key_gen_batch(&executable, &test_key_batch(&email)).unwrap();

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    fs::write(root.join(".gpg-id"), format!("{email}\n")).unwrap();

    let client = PGPClient::new(&executable, &[&email]).unwrap();
    fs::create_dir_all(root.join("work")).unwrap();
    client.encrypt("old-secret", root.join("work/github.gpg").to_str().unwrap()).unwrap();

    let err = insert_entry(InsertEntryRequest {
        entry: EntryRef::new(root.clone(), "work/github").unwrap(),
        content: "new-secret".to_string(),
        overwrite: false,
        pgp_executable: executable.clone(),
    })
    .unwrap_err();

    assert!(err.to_string().contains("already exists"));
    let decrypted = client.decrypt_stdin(&root, "work/github.gpg").unwrap();
    assert_eq!(decrypted.expose_secret(), "old-secret");
}

#[test]
#[serial]
fn generate_entry_encrypts_generated_password_without_prompting() {
    let executable = test_pgp_executable();
    let email = format!("pars-gui-generate-{}@rs.pass", process::id());
    let _key = TestKey { executable: executable.clone(), email: email.clone() };
    key_gen_batch(&executable, &test_key_batch(&email)).unwrap();

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    fs::write(root.join(".gpg-id"), format!("{email}\n")).unwrap();

    let result = generate_entry(GenerateEntryRequest {
        entry: EntryRef::new(root.clone(), "generated/api-token").unwrap(),
        length: 24,
        no_symbols: true,
        overwrite: false,
        pgp_executable: executable.clone(),
    })
    .unwrap();

    assert_eq!(result.path, "generated/api-token");
    assert_eq!(result.password.len(), 24);
    assert!(result.password.chars().all(|character| character.is_ascii_alphanumeric()));

    let client = PGPClient::new(&executable, &[&email]).unwrap();
    let decrypted = client.decrypt_stdin(&root, "generated/api-token.gpg").unwrap();
    assert_eq!(decrypted.expose_secret(), result.password);
}

#[test]
#[serial]
fn edit_entry_reencrypts_confirmed_content_without_prompting() {
    let executable = test_pgp_executable();
    let email = format!("pars-gui-edit-{}@rs.pass", process::id());
    let _key = TestKey { executable: executable.clone(), email: email.clone() };
    key_gen_batch(&executable, &test_key_batch(&email)).unwrap();

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    fs::write(root.join(".gpg-id"), format!("{email}\n")).unwrap();

    let client = PGPClient::new(&executable, &[&email]).unwrap();
    client.encrypt("old-secret", root.join("github.gpg").to_str().unwrap()).unwrap();

    let result = edit_entry(EditEntryRequest {
        entry: EntryRef::new(root.clone(), "github").unwrap(),
        content: "new-secret\nusername: alice".to_string(),
        pgp_executable: executable.clone(),
    })
    .unwrap();

    assert_eq!(result.path, "github");
    let decrypted = client.decrypt_stdin(&root, "github.gpg").unwrap();
    assert_eq!(decrypted.expose_secret(), "new-secret\nusername: alice");
}

#[test]
#[serial]
fn move_entry_renames_password_file_without_prompting() {
    let executable = test_pgp_executable();
    let email = format!("pars-gui-move-{}@rs.pass", process::id());
    let _key = TestKey { executable: executable.clone(), email: email.clone() };
    key_gen_batch(&executable, &test_key_batch(&email)).unwrap();

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    fs::write(root.join(".gpg-id"), format!("{email}\n")).unwrap();

    let client = PGPClient::new(&executable, &[&email]).unwrap();
    fs::create_dir_all(root.join("work")).unwrap();
    client.encrypt("secret", root.join("work/github.gpg").to_str().unwrap()).unwrap();

    let result = move_entry(MoveEntryRequest {
        from: EntryRef::new(root.clone(), "work/github").unwrap(),
        to: EntryRef::new(root.clone(), "archive/github").unwrap(),
        overwrite: false,
    })
    .unwrap();

    assert_eq!(result.path, "archive/github");
    assert!(!root.join("work/github.gpg").exists());
    let decrypted = client.decrypt_stdin(&root, "archive/github.gpg").unwrap();
    assert_eq!(decrypted.expose_secret(), "secret");
}

#[test]
fn move_entry_rejects_existing_destination_without_overwrite() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    create_file(root.join("work/github.gpg"));
    create_file(root.join("archive/github.gpg"));

    let err = move_entry(MoveEntryRequest {
        from: EntryRef::new(root.clone(), "work/github").unwrap(),
        to: EntryRef::new(root.clone(), "archive/github").unwrap(),
        overwrite: false,
    })
    .unwrap_err();

    assert!(err.to_string().contains("already exists"));
    assert!(root.join("work/github.gpg").exists());
    assert!(root.join("archive/github.gpg").exists());
}

#[test]
#[serial]
fn read_entry_decrypts_password_file_and_parses_content() {
    let executable = test_pgp_executable();
    let email = format!("pars-gui-read-{}@rs.pass", process::id());
    let _key = TestKey { executable: executable.clone(), email: email.clone() };
    key_gen_batch(&executable, &test_key_batch(&email)).unwrap();

    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().to_path_buf();
    fs::write(root.join(".gpg-id"), format!("{email}\n")).unwrap();

    let client = PGPClient::new(&executable, &[&email]).unwrap();
    client
        .encrypt(
            "hunter2\nusername: alice\nurl: https://example.com\nkeep this raw",
            root.join("github.gpg").to_str().unwrap(),
        )
        .unwrap();

    let secret = read_entry(ReadEntryRequest {
        entry: EntryRef::new(root, "github").unwrap(),
        pgp_executable: executable,
    })
    .unwrap();

    assert_eq!(secret.password, "hunter2");
    assert_eq!(secret.field_value("username"), Some("alice"));
    assert_eq!(secret.field_value("url"), Some("https://example.com"));
    assert_eq!(secret.raw_notes, "keep this raw");
}
