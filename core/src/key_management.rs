use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::gui::{CoreError, GuiResult, KeyExportResult, SshKeySummary};

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ImportedKeyKind {
    PgpPublic,
    PgpPrivate,
    SshPrivate,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct PrivateKeyConfirmation {
    key_name: String,
    confirmation: String,
}

impl PrivateKeyConfirmation {
    pub fn new(key_name: impl Into<String>, confirmation: impl Into<String>) -> Self {
        Self { key_name: key_name.into(), confirmation: confirmation.into() }
    }

    fn verify(&self) -> GuiResult<()> {
        let expected = format!("EXPORT PRIVATE KEY {}", self.key_name);
        if self.confirmation == expected {
            Ok(())
        } else {
            Err(CoreError::ValidationError(format!(
                "private key export requires confirmation phrase: {expected}"
            )))
        }
    }
}

pub fn detect_imported_key_material(text: &str) -> GuiResult<ImportedKeyKind> {
    let trimmed = text.trim();
    let has_pgp_public_header = trimmed.contains("-----BEGIN PGP PUBLIC KEY BLOCK-----");
    let has_pgp_public_footer = trimmed.contains("-----END PGP PUBLIC KEY BLOCK-----");
    if has_pgp_public_header && has_pgp_public_footer {
        return Ok(ImportedKeyKind::PgpPublic);
    }

    let has_pgp_private_header = trimmed.contains("-----BEGIN PGP PRIVATE KEY BLOCK-----");
    let has_pgp_private_footer = trimmed.contains("-----END PGP PRIVATE KEY BLOCK-----");
    if has_pgp_private_header && has_pgp_private_footer {
        return Ok(ImportedKeyKind::PgpPrivate);
    }

    let has_ssh_private_header = trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY-----")
        || trimmed.contains("-----BEGIN RSA PRIVATE KEY-----")
        || trimmed.contains("-----BEGIN EC PRIVATE KEY-----");
    let has_ssh_private_footer = trimmed.contains("-----END OPENSSH PRIVATE KEY-----")
        || trimmed.contains("-----END RSA PRIVATE KEY-----")
        || trimmed.contains("-----END EC PRIVATE KEY-----");
    if has_ssh_private_header && has_ssh_private_footer {
        return Ok(ImportedKeyKind::SshPrivate);
    }

    Err(CoreError::ValidationError(
        "pasted text is not a supported PGP public key, PGP private key, or SSH private key"
            .to_string(),
    ))
}

pub fn list_ssh_keys(ssh_dir: &Path) -> GuiResult<Vec<SshKeySummary>> {
    if !ssh_dir.exists() {
        return Ok(Vec::new());
    }
    if !ssh_dir.is_dir() {
        return Err(CoreError::ValidationError(format!(
            "SSH key path is not a directory: {}",
            ssh_dir.display()
        )));
    }

    let mut keys = Vec::new();
    for entry in fs::read_dir(ssh_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension() != Some(OsStr::new("pub")) {
            continue;
        }

        let Some(stem) = path.file_stem().and_then(|name| name.to_str()) else {
            continue;
        };
        let fingerprint = ssh_public_key_fingerprint(&path)?;
        keys.push(SshKeySummary {
            name: stem.to_string(),
            fingerprint,
            has_private_key: ssh_dir.join(stem).is_file(),
        });
    }

    keys.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(keys)
}

pub fn generate_ssh_ed25519_key(ssh_dir: &Path, name: &str) -> GuiResult<SshKeySummary> {
    validate_key_file_name(name)?;
    fs::create_dir_all(ssh_dir)?;
    let private_path = ssh_dir.join(name);
    if private_path.exists() || private_path.with_extension("pub").exists() {
        return Err(CoreError::Conflict(crate::gui::EntryConflict::already_exists(name)));
    }

    let output = Command::new("ssh-keygen")
        .args(["-t", "ed25519", "-N", "", "-C", name, "-f"])
        .arg(&private_path)
        .stdin(Stdio::null())
        .output()
        .map_err(|err| CoreError::ValidationError(err.to_string()))?;
    if !output.status.success() {
        return Err(CoreError::ValidationError(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        ));
    }

    set_private_key_permissions(&private_path)?;
    ssh_key_summary(ssh_dir, name)
}

pub fn import_ssh_private_key_text(
    ssh_dir: &Path,
    name: &str,
    private_key: &str,
) -> GuiResult<SshKeySummary> {
    validate_key_file_name(name)?;
    detect_imported_key_material(private_key).and_then(|kind| match kind {
        ImportedKeyKind::SshPrivate => Ok(()),
        ImportedKeyKind::PgpPublic | ImportedKeyKind::PgpPrivate => {
            Err(CoreError::ValidationError("expected SSH private key material".to_string()))
        }
    })?;

    fs::create_dir_all(ssh_dir)?;
    let private_path = ssh_dir.join(name);
    if private_path.exists() || private_path.with_extension("pub").exists() {
        return Err(CoreError::Conflict(crate::gui::EntryConflict::already_exists(name)));
    }
    write_private_key(&private_path, private_key)?;
    derive_ssh_public_key(&private_path, &private_path.with_extension("pub"))?;
    ssh_key_summary(ssh_dir, name)
}

pub fn export_ssh_public_key(ssh_dir: &Path, name: &str) -> GuiResult<KeyExportResult> {
    validate_key_file_name(name)?;
    let public_path = ssh_dir.join(format!("{name}.pub"));
    let armored_text = fs::read_to_string(&public_path).map_err(|err| {
        CoreError::StoreError(format!(
            "failed to read SSH public key {}: {err}",
            public_path.display()
        ))
    })?;
    Ok(KeyExportResult { armored_text })
}

pub fn export_ssh_private_key(
    ssh_dir: &Path,
    name: &str,
    confirmation: PrivateKeyConfirmation,
) -> GuiResult<KeyExportResult> {
    validate_key_file_name(name)?;
    confirmation.verify()?;
    let private_path = ssh_dir.join(name);
    let armored_text = fs::read_to_string(&private_path).map_err(|err| {
        CoreError::StoreError(format!(
            "failed to read SSH private key {}: {err}",
            private_path.display()
        ))
    })?;
    Ok(KeyExportResult { armored_text })
}

pub fn add_pgp_key_to_gpg_id(store_root: &Path, fingerprint: &str) -> GuiResult<()> {
    let normalized = fingerprint.trim();
    if normalized.is_empty() || normalized.contains('\n') || normalized.contains('\r') {
        return Err(CoreError::ValidationError("PGP key fingerprint is invalid".to_string()));
    }

    fs::create_dir_all(store_root)?;
    let gpg_id_path = store_root.join(".gpg-id");
    let existing = fs::read_to_string(&gpg_id_path).unwrap_or_default();
    let already_present = existing.lines().any(|line| line.trim() == normalized);
    if already_present {
        return Ok(());
    }

    let mut file = fs::OpenOptions::new().create(true).append(true).open(&gpg_id_path)?;
    if !existing.is_empty() && !existing.ends_with('\n') {
        writeln!(file)?;
    }
    writeln!(file, "{normalized}")?;
    Ok(())
}

fn ssh_key_summary(ssh_dir: &Path, name: &str) -> GuiResult<SshKeySummary> {
    let public_path = ssh_dir.join(format!("{name}.pub"));
    Ok(SshKeySummary {
        name: name.to_string(),
        fingerprint: ssh_public_key_fingerprint(&public_path)?,
        has_private_key: ssh_dir.join(name).is_file(),
    })
}

fn ssh_public_key_fingerprint(public_path: &Path) -> GuiResult<String> {
    let output = Command::new("ssh-keygen")
        .args(["-lf"])
        .arg(public_path)
        .output()
        .map_err(|err| CoreError::ValidationError(err.to_string()))?;
    if !output.status.success() {
        return Err(CoreError::ValidationError(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    stdout
        .split_whitespace()
        .nth(1)
        .map(str::to_string)
        .ok_or_else(|| CoreError::ValidationError("failed to parse SSH fingerprint".to_string()))
}

fn derive_ssh_public_key(private_path: &Path, public_path: &Path) -> GuiResult<()> {
    let output = Command::new("ssh-keygen")
        .args(["-y", "-f"])
        .arg(private_path)
        .stdin(Stdio::null())
        .output()
        .map_err(|err| CoreError::ValidationError(err.to_string()))?;
    if !output.status.success() {
        return Err(CoreError::ValidationError(
            "failed to derive SSH public key from private key".to_string(),
        ));
    }

    fs::write(public_path, output.stdout)?;
    Ok(())
}

fn write_private_key(path: &Path, private_key: &str) -> GuiResult<()> {
    fs::write(path, private_key)?;
    set_private_key_permissions(path)
}

#[cfg(unix)]
fn set_private_key_permissions(path: &Path) -> GuiResult<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut permissions = fs::metadata(path)?.permissions();
    permissions.set_mode(0o600);
    fs::set_permissions(path, permissions)?;
    Ok(())
}

#[cfg(not(unix))]
fn set_private_key_permissions(_path: &Path) -> GuiResult<()> {
    Ok(())
}

fn validate_key_file_name(name: &str) -> GuiResult<()> {
    let name_path = PathBuf::from(name);
    if name.trim().is_empty()
        || name_path.components().count() != 1
        || name.contains('/')
        || name.contains('\\')
    {
        return Err(CoreError::ValidationError("key name must be a single file name".to_string()));
    }
    Ok(())
}
