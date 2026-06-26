use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD};
use base64::Engine as _;
use ed25519_dalek::SigningKey;
use rand08::rngs::OsRng;
use rand08::RngCore;
use sha2::{Digest, Sha256};
use zeroize::Zeroize;

use crate::gui::{CoreError, GuiResult, KeyExportResult, SshKeySummary};

const SSH_ED25519_ALGORITHM: &[u8] = b"ssh-ed25519";
const OPENSSH_AUTH_MAGIC: &[u8] = b"openssh-key-v1\0";

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

    let mut seed = [0u8; 32];
    OsRng.fill_bytes(&mut seed);
    let signing_key = SigningKey::from_bytes(&seed);
    let public_key = signing_key.verifying_key().to_bytes();
    let private_key = openssh_ed25519_private_key(&seed, &public_key, name);
    let public_key_text = ssh_ed25519_public_key_text(&public_key, name);
    seed.zeroize();

    write_private_key(&private_path, &private_key)?;
    fs::write(private_path.with_extension("pub"), public_key_text)?;
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

pub fn delete_ssh_key(ssh_dir: &Path, name: &str) -> GuiResult<()> {
    validate_key_file_name(name)?;
    let private_path = ssh_dir.join(name);
    let public_path = ssh_dir.join(format!("{name}.pub"));
    let mut removed = false;

    if private_path.exists() {
        fs::remove_file(&private_path)?;
        removed = true;
    }
    if public_path.exists() {
        fs::remove_file(&public_path)?;
        removed = true;
    }
    if removed {
        Ok(())
    } else {
        Err(CoreError::StoreError(format!("SSH key not found: {name}")))
    }
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
    let public_key = fs::read_to_string(public_path).map_err(|err| {
        CoreError::StoreError(format!(
            "failed to read SSH public key {}: {err}",
            public_path.display()
        ))
    })?;
    let blob = public_key
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| CoreError::ValidationError("failed to parse SSH public key".to_string()))
        .and_then(|encoded| {
            STANDARD.decode(encoded).map_err(|_| {
                CoreError::ValidationError("failed to decode SSH public key".to_string())
            })
        })?;
    Ok(ssh_fingerprint_for_blob(&blob))
}

fn derive_ssh_public_key(private_path: &Path, public_path: &Path) -> GuiResult<()> {
    let private_key = fs::read_to_string(private_path).map_err(|err| {
        CoreError::StoreError(format!(
            "failed to read SSH private key {}: {err}",
            private_path.display()
        ))
    })?;
    let public_key = openssh_ed25519_public_key_from_private(&private_key)?;
    let comment = private_path.file_name().and_then(|name| name.to_str()).unwrap_or("imported-key");
    fs::write(public_path, ssh_ed25519_public_key_text(&public_key, comment))?;
    Ok(())
}

fn ssh_ed25519_public_blob(public_key: &[u8; 32]) -> Vec<u8> {
    let mut blob = Vec::new();
    push_ssh_string(&mut blob, SSH_ED25519_ALGORITHM);
    push_ssh_string(&mut blob, public_key);
    blob
}

fn ssh_ed25519_public_key_text(public_key: &[u8; 32], comment: &str) -> String {
    let blob = ssh_ed25519_public_blob(public_key);
    format!("ssh-ed25519 {} {}\n", STANDARD.encode(blob), comment.trim())
}

fn openssh_ed25519_private_key(seed: &[u8; 32], public_key: &[u8; 32], comment: &str) -> String {
    let public_blob = ssh_ed25519_public_blob(public_key);
    let mut rng = OsRng;
    let check = rng.next_u32();

    let mut private_key = Vec::with_capacity(64);
    private_key.extend_from_slice(seed);
    private_key.extend_from_slice(public_key);

    let mut private_section = Vec::new();
    push_ssh_u32(&mut private_section, check);
    push_ssh_u32(&mut private_section, check);
    push_ssh_string(&mut private_section, SSH_ED25519_ALGORITHM);
    push_ssh_string(&mut private_section, public_key);
    push_ssh_string(&mut private_section, &private_key);
    push_ssh_string(&mut private_section, comment.trim().as_bytes());
    private_key.zeroize();
    let padding = (8 - private_section.len() % 8) % 8;
    for byte in 1..=padding {
        private_section.push(byte as u8);
    }

    let mut encoded = Vec::new();
    encoded.extend_from_slice(OPENSSH_AUTH_MAGIC);
    push_ssh_string(&mut encoded, b"none");
    push_ssh_string(&mut encoded, b"none");
    push_ssh_string(&mut encoded, b"");
    push_ssh_u32(&mut encoded, 1);
    push_ssh_string(&mut encoded, &public_blob);
    push_ssh_string(&mut encoded, &private_section);

    let base64 = STANDARD.encode(encoded);
    format!(
        "-----BEGIN OPENSSH PRIVATE KEY-----\n{}-----END OPENSSH PRIVATE KEY-----\n",
        wrap_base64(&base64)
    )
}

fn openssh_ed25519_public_key_from_private(private_key: &str) -> GuiResult<[u8; 32]> {
    let body = private_key
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with("-----"))
        .collect::<String>();
    let decoded = STANDARD.decode(body).map_err(|_| {
        CoreError::ValidationError("failed to decode OpenSSH private key".to_string())
    })?;

    let mut reader = SshReader::new(&decoded);
    reader.read_magic(OPENSSH_AUTH_MAGIC)?;
    let cipher = reader.read_string()?;
    let kdf = reader.read_string()?;
    let _kdf_options = reader.read_string()?;
    if cipher != b"none" || kdf != b"none" {
        return Err(CoreError::ValidationError(
            "only unencrypted OpenSSH ed25519 private keys are supported".to_string(),
        ));
    }
    if reader.read_u32()? != 1 {
        return Err(CoreError::ValidationError(
            "OpenSSH private key must contain exactly one key".to_string(),
        ));
    }
    let public_blob = reader.read_string()?.to_vec();
    let private_section = reader.read_string()?;

    let mut private_reader = SshReader::new(private_section);
    let check = private_reader.read_u32()?;
    if private_reader.read_u32()? != check {
        return Err(CoreError::ValidationError(
            "OpenSSH private key checkints do not match".to_string(),
        ));
    }
    if private_reader.read_string()? != SSH_ED25519_ALGORITHM {
        return Err(CoreError::ValidationError(
            "only OpenSSH ed25519 private keys are supported".to_string(),
        ));
    }
    let public_key = public_key_array(private_reader.read_string()?)?;
    let private_key = private_reader.read_string()?;
    if private_key.len() != 64 || private_key[32..] != public_key {
        return Err(CoreError::ValidationError(
            "OpenSSH ed25519 private key payload is invalid".to_string(),
        ));
    }
    if public_blob != ssh_ed25519_public_blob(&public_key) {
        return Err(CoreError::ValidationError(
            "OpenSSH private key public blob is invalid".to_string(),
        ));
    }
    Ok(public_key)
}

fn public_key_array(bytes: &[u8]) -> GuiResult<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| CoreError::ValidationError("SSH ed25519 public key is invalid".to_string()))
}

fn ssh_fingerprint_for_blob(blob: &[u8]) -> String {
    let digest = Sha256::digest(blob);
    format!("SHA256:{}", STANDARD_NO_PAD.encode(digest))
}

fn push_ssh_u32(output: &mut Vec<u8>, value: u32) {
    output.extend_from_slice(&value.to_be_bytes());
}

fn push_ssh_string(output: &mut Vec<u8>, value: &[u8]) {
    push_ssh_u32(output, value.len() as u32);
    output.extend_from_slice(value);
}

fn wrap_base64(encoded: &str) -> String {
    let mut wrapped = String::new();
    for chunk in encoded.as_bytes().chunks(70) {
        wrapped.push_str(std::str::from_utf8(chunk).expect("base64 is ascii"));
        wrapped.push('\n');
    }
    wrapped
}

struct SshReader<'a> {
    input: &'a [u8],
    offset: usize,
}

impl<'a> SshReader<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, offset: 0 }
    }

    fn read_magic(&mut self, magic: &[u8]) -> GuiResult<()> {
        let bytes = self.read_exact(magic.len())?;
        if bytes == magic {
            Ok(())
        } else {
            Err(CoreError::ValidationError("invalid OpenSSH private key".to_string()))
        }
    }

    fn read_u32(&mut self) -> GuiResult<u32> {
        let bytes = self.read_exact(4)?;
        Ok(u32::from_be_bytes(bytes.try_into().expect("length checked")))
    }

    fn read_string(&mut self) -> GuiResult<&'a [u8]> {
        let length = self.read_u32()? as usize;
        self.read_exact(length)
    }

    fn read_exact(&mut self, length: usize) -> GuiResult<&'a [u8]> {
        let end = self
            .offset
            .checked_add(length)
            .ok_or_else(|| CoreError::ValidationError("invalid SSH key length".to_string()))?;
        if end > self.input.len() {
            return Err(CoreError::ValidationError("truncated SSH key".to_string()));
        }
        let bytes = &self.input[self.offset..end];
        self.offset = end;
        Ok(bytes)
    }
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
