use std::ffi::OsStr;
use std::fmt::Display;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::pkcs8::DecodePrivateKey;
use rand08::rngs::OsRng;
use rsa::pkcs1::DecodeRsaPrivateKey;
use rsa::RsaPrivateKey as RsaPemPrivateKey;
use ssh_key::private::{EcdsaKeypair, RsaKeypair};
use ssh_key::sec1::consts::{U32, U48, U66};
use ssh_key::sec1::EncodedPoint;
use ssh_key::{Algorithm, HashAlg, LineEnding, PrivateKey, PublicKey};

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
        || trimmed.contains("-----BEGIN EC PRIVATE KEY-----")
        || trimmed.contains("-----BEGIN PRIVATE KEY-----")
        || trimmed.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----");
    let has_ssh_private_footer = trimmed.contains("-----END OPENSSH PRIVATE KEY-----")
        || trimmed.contains("-----END RSA PRIVATE KEY-----")
        || trimmed.contains("-----END EC PRIVATE KEY-----")
        || trimmed.contains("-----END PRIVATE KEY-----")
        || trimmed.contains("-----END ENCRYPTED PRIVATE KEY-----");
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
    let public_path = ssh_public_key_path(ssh_dir, name);
    if private_path.exists() || public_path.exists() {
        return Err(CoreError::Conflict(crate::gui::EntryConflict::already_exists(name)));
    }

    let key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519).map_err(ssh_key_error)?;
    let (private_key, public_key_text) = openssh_key_pair(key, name)?;
    write_ssh_key_pair(&private_path, &private_key, &public_path, &public_key_text)?;
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
    let parsed = parse_ssh_private_key(private_key)?;
    let (private_key, public_key_text) = openssh_key_pair(parsed, name)?;

    fs::create_dir_all(ssh_dir)?;
    let private_path = ssh_dir.join(name);
    let public_path = ssh_public_key_path(ssh_dir, name);
    // A private key without its public key is unusable by every other code path, so the name is
    // only taken when the public key exists or the private key can still be loaded.
    if public_path.exists() || (private_path.exists() && is_usable_ssh_private_key(&private_path)) {
        return Err(CoreError::Conflict(crate::gui::EntryConflict::already_exists(name)));
    }

    write_ssh_key_pair(&private_path, &private_key, &public_path, &public_key_text)?;
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

    fs::create_dir_all(store_root).map_err(|error| {
        store_path_error("failed to prepare password store directory", store_root, error)
    })?;
    let gpg_id_path = store_root.join(".gpg-id");
    let existing = match fs::read_to_string(&gpg_id_path) {
        Ok(existing) => existing,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => {
            return Err(store_path_error(
                "failed to read PGP recipients file",
                &gpg_id_path,
                error,
            ));
        }
    };
    let already_present = existing.lines().any(|line| line.trim() == normalized);
    if already_present {
        return Ok(());
    }

    let mut file =
        fs::OpenOptions::new().create(true).append(true).open(&gpg_id_path).map_err(|error| {
            store_path_error("failed to open PGP recipients file for writing", &gpg_id_path, error)
        })?;
    if !existing.is_empty() && !existing.ends_with('\n') {
        writeln!(file).map_err(|error| {
            store_path_error("failed to write PGP recipients file", &gpg_id_path, error)
        })?;
    }
    writeln!(file, "{normalized}").map_err(|error| {
        store_path_error("failed to write PGP recipients file", &gpg_id_path, error)
    })?;
    Ok(())
}

fn store_path_error(operation: &str, path: &Path, error: std::io::Error) -> CoreError {
    CoreError::StoreError(format!("{operation} '{}': {error}", path.display()))
}

fn ssh_public_key_path(ssh_dir: &Path, name: &str) -> PathBuf {
    ssh_dir.join(format!("{name}.pub"))
}

fn ssh_key_summary(ssh_dir: &Path, name: &str) -> GuiResult<SshKeySummary> {
    let public_path = ssh_public_key_path(ssh_dir, name);
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
    let public = PublicKey::from_openssh(&public_key).map_err(ssh_key_error)?;
    Ok(public.fingerprint(HashAlg::Sha256).to_string())
}

fn is_usable_ssh_private_key(private_path: &Path) -> bool {
    fs::read_to_string(private_path)
        .is_ok_and(|private_key| parse_ssh_private_key(&private_key).is_ok())
}

fn parse_ssh_private_key(text: &str) -> GuiResult<PrivateKey> {
    let trimmed = text.trim();
    if trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY-----") {
        let key = PrivateKey::from_openssh(trimmed).map_err(ssh_key_error)?;
        return usable_private_key(key);
    }
    if trimmed.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
        return Err(encrypted_ssh_key_error());
    }
    if trimmed.contains("-----BEGIN RSA PRIVATE KEY-----") {
        let rsa_key = RsaPemPrivateKey::from_pkcs1_pem(trimmed).map_err(ssh_key_error)?;
        let keypair = RsaKeypair::try_from(rsa_key).map_err(ssh_key_error)?;
        return usable_private_key(PrivateKey::from(keypair));
    }
    if trimmed.contains("-----BEGIN EC PRIVATE KEY-----") {
        return parse_ec_private_key(trimmed, false);
    }
    if trimmed.contains("-----BEGIN PRIVATE KEY-----") {
        return parse_pkcs8_private_key(trimmed);
    }
    Err(CoreError::ValidationError("failed to parse SSH private key".to_string()))
}

fn usable_private_key(key: PrivateKey) -> GuiResult<PrivateKey> {
    if key.is_encrypted() {
        return Err(encrypted_ssh_key_error());
    }
    match key.algorithm() {
        Algorithm::Ed25519 | Algorithm::Rsa { .. } | Algorithm::Ecdsa { .. } => Ok(key),
        other => Err(CoreError::ValidationError(format!(
            "SSH key algorithm {} cannot be used for Git. Import an Ed25519, RSA, or ECDSA key.",
            other.as_str()
        ))),
    }
}

fn encrypted_ssh_key_error() -> CoreError {
    CoreError::ValidationError(
        "SSH private key is encrypted. Remove the passphrase before importing.".to_string(),
    )
}

fn parse_pkcs8_private_key(text: &str) -> GuiResult<PrivateKey> {
    if let Ok(rsa_key) = RsaPemPrivateKey::from_pkcs8_pem(text) {
        let keypair = RsaKeypair::try_from(rsa_key).map_err(ssh_key_error)?;
        return usable_private_key(PrivateKey::from(keypair));
    }
    parse_ec_private_key(text, true)
}

fn parse_ec_private_key(text: &str, pkcs8: bool) -> GuiResult<PrivateKey> {
    if let Some(key) = ec_private_key_p256(text, pkcs8) {
        return usable_private_key(key);
    }
    if let Some(key) = ec_private_key_p384(text, pkcs8) {
        return usable_private_key(key);
    }
    if let Some(key) = ec_private_key_p521(text, pkcs8) {
        return usable_private_key(key);
    }
    Err(CoreError::ValidationError("failed to parse EC private key".to_string()))
}

fn ec_private_key_p256(text: &str, pkcs8: bool) -> Option<PrivateKey> {
    let secret = if pkcs8 {
        p256::SecretKey::from_pkcs8_pem(text).ok()?
    } else {
        p256::SecretKey::from_sec1_pem(text).ok()?
    };
    let point = secret.public_key().to_encoded_point(false);
    let public = EncodedPoint::<U32>::from_bytes(point.as_bytes()).ok()?;
    Some(PrivateKey::from(EcdsaKeypair::NistP256 { public, private: secret.into() }))
}

fn ec_private_key_p384(text: &str, pkcs8: bool) -> Option<PrivateKey> {
    let secret = if pkcs8 {
        p384::SecretKey::from_pkcs8_pem(text).ok()?
    } else {
        p384::SecretKey::from_sec1_pem(text).ok()?
    };
    let point = secret.public_key().to_encoded_point(false);
    let public = EncodedPoint::<U48>::from_bytes(point.as_bytes()).ok()?;
    Some(PrivateKey::from(EcdsaKeypair::NistP384 { public, private: secret.into() }))
}

fn ec_private_key_p521(text: &str, pkcs8: bool) -> Option<PrivateKey> {
    let secret = if pkcs8 {
        p521::SecretKey::from_pkcs8_pem(text).ok()?
    } else {
        p521::SecretKey::from_sec1_pem(text).ok()?
    };
    let point = secret.public_key().to_encoded_point(false);
    let public = EncodedPoint::<U66>::from_bytes(point.as_bytes()).ok()?;
    Some(PrivateKey::from(EcdsaKeypair::NistP521 { public, private: secret.into() }))
}

fn openssh_key_pair(mut key: PrivateKey, comment: &str) -> GuiResult<(String, String)> {
    key.set_comment(comment);
    let private_key = key.to_openssh(LineEnding::LF).map_err(ssh_key_error)?;
    let mut public = key.public_key().clone();
    public.set_comment(comment);
    let mut public_key = public.to_openssh().map_err(ssh_key_error)?;
    if !public_key.ends_with('\n') {
        public_key.push('\n');
    }
    Ok((private_key.to_string(), public_key))
}

fn ssh_key_error(error: impl Display) -> CoreError {
    let detail = error.to_string();
    if detail.contains("BEGIN") || detail.len() > 200 {
        return CoreError::ValidationError("failed to parse SSH private key".to_string());
    }
    CoreError::ValidationError(format!("failed to parse SSH private key: {detail}"))
}

fn write_ssh_key_pair(
    private_path: &Path,
    private_key: &str,
    public_path: &Path,
    public_key_text: &str,
) -> GuiResult<()> {
    write_private_key(private_path, private_key)?;
    if let Err(error) = fs::write(public_path, public_key_text) {
        let _ = fs::remove_file(private_path);
        return Err(error.into());
    }
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
