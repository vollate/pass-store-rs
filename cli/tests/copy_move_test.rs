use std::fs;
use std::path::Path;
use std::process::{Command as ProcessCommand, Output};

use assert_cmd::Command;
use predicates::prelude::predicate;
use tempfile::TempDir;

struct Store {
    temp: TempDir,
}

impl Store {
    fn new() -> Self {
        let store = Self { temp: tempfile::tempdir().unwrap() };
        store.write("config.toml", b"");
        store.write(".gpg-id", b"source@example.invalid\n");
        store.git(&["init", "-q"]);
        store.git(&["config", "user.name", "Pars test"]);
        store.git(&["config", "user.email", "pars@example.invalid"]);
        store.git(&["config", "commit.gpgsign", "false"]);
        store.git(&["config", "core.autocrlf", "false"]);
        store
    }

    fn root(&self) -> &Path {
        self.temp.path()
    }

    fn write(&self, path: &str, contents: &[u8]) {
        let path = self.root().join(path);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, contents).unwrap();
    }

    fn isolate(&self, command: &mut ProcessCommand) {
        command.env_clear();
        for key in ["PATH", "SystemRoot", "WINDIR", "PATHEXT", "TMP", "TEMP", "TMPDIR"] {
            if let Some(value) = std::env::var_os(key) {
                command.env(key, value);
            }
        }
        command
            .current_dir(self.root())
            .env("HOME", self.root())
            .env("USERPROFILE", self.root())
            .env("XDG_CONFIG_HOME", self.root())
            .env("APPDATA", self.root())
            .env("GNUPGHOME", self.root().join("gnupg"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", self.root().join("no-global-git-config"))
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("PARS_CONFIG_PATH", self.root().join("config.toml"));
    }

    fn git(&self, args: &[&str]) -> Output {
        let mut command = ProcessCommand::new("git");
        self.isolate(&mut command);
        let output = command.args(args).output().unwrap();
        assert!(
            output.status.success(),
            "git {args:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        output
    }

    fn commit(&self) {
        self.git(&["add", "-A"]);
        self.git(&["commit", "-qm", "Fixture"]);
    }

    fn pars(&self, operation: &str, source: &str, destination: &str) -> Command {
        let mut command = ProcessCommand::new(assert_cmd::cargo::cargo_bin!("pars"));
        self.isolate(&mut command);
        command.arg("-R").arg(self.root()).args([operation, source, destination]);
        Command::from_std(command)
    }
}

fn assert_canceled(
    source: &str,
    destination: &str,
    source_file: &str,
    target_file: &str,
    different_recipients: bool,
) {
    for operation in ["cp", "mv"] {
        for input in ["n\n", "\n", ""] {
            for dirty in [false, true] {
                let store = Store::new();
                store.write(source_file, b"source ciphertext");
                store.write(target_file, b"destination ciphertext");
                if different_recipients {
                    // Cancellation must happen before any decryption/key lookup. No real keys needed.
                    store.write("target/.gpg-id", b"destination@example.invalid\n");
                }
                store.commit();
                if dirty {
                    store.write("staged.gpg", b"unrelated staged ciphertext");
                    store.git(&["add", "staged.gpg"]);
                    store.write("untracked.gpg", b"unrelated untracked ciphertext");
                }
                let head = store.git(&["rev-parse", "HEAD"]).stdout;
                let status = store.git(&["status", "--porcelain=v1", "-uall"]).stdout;
                let staged = store.git(&["diff", "--cached", "--binary"]).stdout;

                store
                    .pars(operation, source, destination)
                    .write_stdin(input)
                    .assert()
                    .success()
                    .stdout(predicate::str::contains("Canceled"))
                    .stderr(predicate::str::is_empty());

                assert_eq!(fs::read(store.root().join(source_file)).unwrap(), b"source ciphertext");
                assert_eq!(
                    fs::read(store.root().join(target_file)).unwrap(),
                    b"destination ciphertext"
                );
                assert_eq!(store.git(&["rev-parse", "HEAD"]).stdout, head);
                assert_eq!(store.git(&["status", "--porcelain=v1", "-uall"]).stdout, status);
                assert_eq!(store.git(&["diff", "--cached", "--binary"]).stdout, staged);
            }
        }
    }
}

#[test]
fn cancel_file_overwrite() {
    assert_canceled("source", "target/entry", "source.gpg", "target/entry.gpg", false);
}

#[test]
fn cancel_file_overwrite_with_different_recipients() {
    assert_canceled("source", "target/entry", "source.gpg", "target/entry.gpg", true);
}

#[test]
fn cancel_file_into_directory() {
    assert_canceled("source", "target", "source.gpg", "target/source.gpg", false);
}

#[test]
fn cancel_file_into_directory_with_different_recipients() {
    assert_canceled("source", "target", "source.gpg", "target/source.gpg", true);
}

#[test]
fn cancel_directory_overwrite() {
    assert_canceled("source", "target", "source/entry.gpg", "target/source/entry.gpg", false);
}

#[test]
fn cancel_directory_over_file() {
    assert_canceled("source", "target", "source/entry.gpg", "target", false);
}

#[test]
fn completed_operations_still_commit() {
    for operation in ["cp", "mv"] {
        // New destinations, confirmed overwrites and forced overwrites must still commit.
        for mode in ["new", "yes", "force"] {
            let store = Store::new();
            store.write("source.gpg", b"source ciphertext");
            if mode != "new" {
                store.write("nested/target.gpg", b"destination ciphertext");
            }
            store.commit();
            let head = store.git(&["rev-parse", "HEAD"]).stdout;
            let mut command = store.pars(operation, "source", "nested/target");
            if mode == "force" {
                command.arg("--force");
            }
            command.write_stdin(if mode == "yes" { "y\n" } else { "" }).assert().success();

            assert_eq!(
                fs::read(store.root().join("nested/target.gpg")).unwrap(),
                b"source ciphertext"
            );
            assert_eq!(store.root().join("source.gpg").exists(), operation == "cp");
            assert_ne!(store.git(&["rev-parse", "HEAD"]).stdout, head);
            assert_eq!(store.git(&["rev-list", "--count", "HEAD"]).stdout, b"2\n");
            assert!(store.git(&["status", "--porcelain=v1"]).stdout.is_empty());
        }
    }
}

#[test]
fn missing_source_still_fails_without_committing() {
    for operation in ["cp", "mv"] {
        let store = Store::new();
        store.commit();
        let head = store.git(&["rev-parse", "HEAD"]).stdout;
        store.pars(operation, "missing", "target").assert().failure();
        assert_eq!(store.git(&["rev-parse", "HEAD"]).stdout, head);
        assert!(store.git(&["status", "--porcelain=v1"]).stdout.is_empty());
    }
}
