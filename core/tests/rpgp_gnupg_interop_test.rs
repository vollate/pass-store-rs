use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use pars_core::config::cli::PgpBackendKind;
use pars_core::pgp::backend::{KeyGenerationRequest, PgpBackend, PgpBackendConfig};
use pars_core::pgp::rpgp_backend::RpgpBackend;
use secrecy::{ExposeSecret, SecretString};

#[test]
fn optional_gnupg_decrypts_rpgp_encrypted_entry() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let fingerprint = context.generate_rpgp_key();
    context.import_private_key_to_gnupg(&fingerprint);

    let encrypted_path = context.temp.path().join("rpgp-to-gpg.gpg");
    context
        .rpgp
        .encrypt_content(&SecretString::new("rpgp secret".into()), &encrypted_path, &[fingerprint])
        .unwrap();

    let output = gpg_command(&context.gnupg_home)
        .args(["--batch", "--yes", "--pinentry-mode", "loopback", "--decrypt"])
        .arg(&encrypted_path)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "gpg decrypt failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "rpgp secret");
}

#[test]
fn optional_rpgp_decrypts_gnupg_encrypted_entry() {
    if !run_interop_tests() {
        return;
    }
    let context = InteropContext::new();
    let fingerprint = context.generate_rpgp_key();
    context.import_public_key_to_gnupg(&fingerprint);

    let plaintext_path = context.temp.path().join("plaintext.txt");
    let encrypted_path = context.temp.path().join("gpg-to-rpgp.gpg");
    std::fs::write(&plaintext_path, "gpg secret").unwrap();
    let output = gpg_command(&context.gnupg_home)
        .args([
            "--batch",
            "--yes",
            "--trust-model",
            "always",
            "--recipient",
            &fingerprint,
            "--output",
        ])
        .arg(&encrypted_path)
        .arg("--encrypt")
        .arg(&plaintext_path)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "gpg encrypt failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let decrypted = context.rpgp.decrypt_file(&encrypted_path).unwrap();
    assert_eq!(decrypted.expose_secret(), "gpg secret");
}

struct InteropContext {
    temp: tempfile::TempDir,
    gnupg_home: std::path::PathBuf,
    rpgp: RpgpBackend,
}

impl InteropContext {
    fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let gnupg_home = temp.path().join("gnupg");
        let rpgp_home = temp.path().join("rpgp");
        std::fs::create_dir_all(&gnupg_home).unwrap();
        lock_down_dir(&gnupg_home);
        let rpgp = RpgpBackend::from_config(&PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            bundled_gpg_path: None,
            system_gpg_path: None,
            pure_rust_enabled: true,
            keyring_home: Some(rpgp_home.display().to_string()),
        })
        .unwrap();
        Self { temp, gnupg_home, rpgp }
    }

    fn generate_rpgp_key(&self) -> String {
        self.rpgp
            .generate_key(KeyGenerationRequest {
                name: "Interop Example".to_string(),
                email: "interop@example.com".to_string(),
                passphrase: None,
            })
            .unwrap()
            .fingerprint
    }

    fn import_public_key_to_gnupg(&self, fingerprint: &str) {
        let public_key = self.rpgp.export_public_key(fingerprint).unwrap();
        gpg_with_input(&self.gnupg_home, &["--import"], public_key.armored_text.as_bytes());
    }

    fn import_private_key_to_gnupg(&self, fingerprint: &str) {
        let private_key = self.rpgp.export_private_key(fingerprint, None).unwrap();
        gpg_with_input(&self.gnupg_home, &["--import"], private_key.armored_text.as_bytes());
    }
}

fn run_interop_tests() -> bool {
    if std::env::var("PARS_RUN_GPG_INTEROP").as_deref() == Ok("1") {
        return true;
    }
    eprintln!("skipping GnuPG interoperability test; set PARS_RUN_GPG_INTEROP=1 to run");
    false
}

fn gpg_with_input(gnupg_home: &Path, args: &[&str], input: &[u8]) {
    let mut child = gpg_command(gnupg_home)
        .args(["--batch", "--yes", "--pinentry-mode", "loopback"])
        .args(args)
        .stdin(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "gpg command failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn gpg_command(gnupg_home: &Path) -> Command {
    let executable = std::env::var("PARS_GPG").unwrap_or_else(|_| "gpg".to_string());
    let mut command = Command::new(executable);
    command.env("GNUPGHOME", gnupg_home);
    command
}

#[cfg(unix)]
fn lock_down_dir(path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = std::fs::metadata(path).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(path, permissions).unwrap();
}

#[cfg(not(unix))]
fn lock_down_dir(_path: &Path) {}
