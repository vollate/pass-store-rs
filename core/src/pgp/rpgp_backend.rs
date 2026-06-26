use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use pgp::composed::{
    Deserializable, EncryptionCaps, KeyType, Message, MessageBuilder, SecretKeyParamsBuilder,
    SignedPublicKey, SignedSecretKey, SubkeyParamsBuilder,
};
use pgp::crypto::ecc_curve::ECCCurve;
use pgp::crypto::sym::SymmetricKeyAlgorithm;
use pgp::types::{KeyDetails, Password};
use secrecy::{ExposeSecret, SecretString};

use crate::config::cli::PgpBackendKind;
use crate::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
use crate::pgp::backend::{
    KeyGenerationRequest, PgpBackend, PgpBackendConfig, PgpBackendError, PgpBackendResult,
    PgpKeyDetails,
};
use crate::util::fs_util::get_dir_gpg_id_content;

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct RpgpBackend {
    keyring_home: PathBuf,
}

#[derive(Debug, Clone)]
struct PublicKeyRecord {
    identity: String,
    fingerprint: String,
    key_id: String,
    key: SignedPublicKey,
    armored_text: String,
    has_private_key: bool,
}

impl RpgpBackend {
    pub fn from_config(config: &PgpBackendConfig) -> PgpBackendResult<Self> {
        if config.backend != PgpBackendKind::PureRust {
            return Err(PgpBackendError::InvalidConfig(
                "rPGP backend requires pure_rust backend config".to_string(),
            ));
        }
        let keyring_home = config.keyring_home.clone().ok_or_else(|| {
            PgpBackendError::InvalidConfig("pure_rust backend requires keyring_home".to_string())
        })?;
        let backend = Self { keyring_home: PathBuf::from(keyring_home) };
        backend.ensure_dirs()?;
        Ok(backend)
    }

    fn ensure_dirs(&self) -> PgpBackendResult<()> {
        fs::create_dir_all(self.public_dir()).map_err(pgp_command_error)?;
        fs::create_dir_all(self.private_dir()).map_err(pgp_command_error)?;
        Ok(())
    }

    fn public_dir(&self) -> PathBuf {
        self.keyring_home.join("public")
    }

    fn private_dir(&self) -> PathBuf {
        self.keyring_home.join("private")
    }

    fn public_key_path(&self, fingerprint: &str) -> PathBuf {
        self.public_dir().join(format!("{}.asc", normalize_key_ref(fingerprint)))
    }

    fn private_key_path(&self, fingerprint: &str) -> PathBuf {
        self.private_dir().join(format!("{}.asc", normalize_key_ref(fingerprint)))
    }

    fn store_public_key(&self, key: &SignedPublicKey) -> PgpBackendResult<String> {
        let fingerprint = fingerprint(key);
        let armored_text =
            key.to_armored_string(None.into()).map_err(|err| pgp_command_error(err))?;
        fs::write(self.public_key_path(&fingerprint), armored_text).map_err(pgp_command_error)?;
        Ok(fingerprint)
    }

    fn store_private_key(&self, key: &SignedSecretKey) -> PgpBackendResult<String> {
        let fingerprint = secret_fingerprint(key);
        let armored_text =
            key.to_armored_string(None.into()).map_err(|err| pgp_command_error(err))?;
        fs::write(self.private_key_path(&fingerprint), armored_text).map_err(pgp_command_error)?;
        let public_key = key.to_public_key();
        self.store_public_key(&public_key)?;
        Ok(fingerprint)
    }

    fn read_public_records(&self) -> PgpBackendResult<Vec<PublicKeyRecord>> {
        let private_fingerprints = self.private_fingerprints()?;
        let mut records = BTreeMap::<String, PublicKeyRecord>::new();

        for path in asc_files(&self.public_dir())? {
            let armored_text = fs::read_to_string(&path).map_err(pgp_command_error)?;
            let key = parse_public_key(&armored_text)?;
            let fingerprint = fingerprint(&key);
            records.insert(
                fingerprint.clone(),
                PublicKeyRecord {
                    identity: key_identity(&key),
                    key_id: key_id(&key),
                    has_private_key: private_fingerprints.contains(&fingerprint),
                    key,
                    armored_text,
                    fingerprint,
                },
            );
        }

        for path in asc_files(&self.private_dir())? {
            let armored_text = fs::read_to_string(&path).map_err(pgp_command_error)?;
            let secret_key = parse_secret_key(&armored_text)?;
            let public_key = secret_key.to_public_key();
            let fingerprint = fingerprint(&public_key);
            records.entry(fingerprint.clone()).or_insert_with(|| PublicKeyRecord {
                identity: key_identity(&public_key),
                key_id: key_id(&public_key),
                armored_text: public_key.to_armored_string(None.into()).unwrap_or_default(),
                has_private_key: true,
                key: public_key,
                fingerprint,
            });
        }

        Ok(records.into_values().collect())
    }

    fn private_fingerprints(&self) -> PgpBackendResult<BTreeSet<String>> {
        let mut fingerprints = BTreeSet::new();
        for path in asc_files(&self.private_dir())? {
            let armored_text = fs::read_to_string(path).map_err(pgp_command_error)?;
            let key = parse_secret_key(&armored_text)?;
            fingerprints.insert(secret_fingerprint(&key));
        }
        Ok(fingerprints)
    }

    fn read_private_keys(&self) -> PgpBackendResult<Vec<SignedSecretKey>> {
        let mut keys = Vec::new();
        for path in asc_files(&self.private_dir())? {
            let armored_text = fs::read_to_string(path).map_err(pgp_command_error)?;
            keys.push(parse_secret_key(&armored_text)?);
        }
        Ok(keys)
    }

    fn resolve_public_record(&self, recipient: &str) -> PgpBackendResult<PublicKeyRecord> {
        let recipient = recipient.trim();
        self.read_public_records()?.into_iter().find(|record| record.matches(recipient)).ok_or_else(
            || {
                PgpBackendError::CommandFailed(format!(
                    "no public key found for recipient: {recipient}"
                ))
            },
        )
    }

    fn resolve_recipients(&self, recipients: &[String]) -> PgpBackendResult<Vec<PublicKeyRecord>> {
        recipients.iter().map(|recipient| self.resolve_public_record(recipient)).collect()
    }

    fn generate_secret_key(request: KeyGenerationRequest) -> PgpBackendResult<SignedSecretKey> {
        let user_id = format!("{} <{}>", request.name.trim(), request.email.trim());
        let mut signing_key = SubkeyParamsBuilder::default();
        signing_key
            .key_type(KeyType::Ed25519Legacy)
            .can_sign(true)
            .can_encrypt(EncryptionCaps::None)
            .can_authenticate(false)
            .passphrase(None);

        let mut encryption_key = SubkeyParamsBuilder::default();
        encryption_key
            .key_type(KeyType::ECDH(ECCCurve::Curve25519Legacy))
            .can_sign(false)
            .can_encrypt(EncryptionCaps::All)
            .can_authenticate(false)
            .passphrase(None);

        let mut key_params = SecretKeyParamsBuilder::default();
        key_params
            .key_type(KeyType::Ed25519Legacy)
            .can_certify(true)
            .can_sign(false)
            .can_encrypt(EncryptionCaps::None)
            .primary_user_id(user_id)
            .passphrase(request.passphrase.map(|value| value.expose_secret().to_string()))
            .subkeys(vec![
                signing_key.build().map_err(pgp_command_error)?,
                encryption_key.build().map_err(pgp_command_error)?,
            ]);

        key_params
            .build()
            .map_err(pgp_command_error)?
            .generate(rand08::thread_rng())
            .map_err(pgp_command_error)
    }
}

impl PublicKeyRecord {
    fn matches(&self, recipient: &str) -> bool {
        let normalized = normalize_key_ref(recipient);
        self.fingerprint == normalized
            || self.fingerprint.ends_with(&normalized)
            || self.key_id == normalized
            || self.key_id.ends_with(&normalized)
            || self.identity.eq_ignore_ascii_case(recipient)
            || self.identity.to_ascii_lowercase().contains(&recipient.to_ascii_lowercase())
    }
}

impl PgpBackend for RpgpBackend {
    fn decrypt_file(&self, encrypted_path: &Path) -> PgpBackendResult<SecretString> {
        let encrypted = fs::read(encrypted_path).map_err(pgp_command_error)?;
        let mut last_error = None::<String>;

        for key in self.read_private_keys()? {
            let Ok(message) = Message::from_bytes(encrypted.as_slice()) else {
                return Err(PgpBackendError::CommandFailed(format!(
                    "failed to parse encrypted message: {}",
                    encrypted_path.display()
                )));
            };
            match message.decrypt(&Password::empty(), &key) {
                Ok(mut decrypted) => {
                    if decrypted.is_compressed() {
                        decrypted = decrypted.decompress().map_err(pgp_command_error)?;
                    }
                    let data = decrypted.as_data_vec().map_err(pgp_command_error)?;
                    let text = String::from_utf8(data).map_err(pgp_command_error)?;
                    return Ok(SecretString::from(text));
                }
                Err(error) => last_error = Some(error.to_string()),
            }
        }

        Err(PgpBackendError::CommandFailed(
            last_error
                .unwrap_or_else(|| "no private keys are available for decryption".to_string()),
        ))
    }

    fn encrypt_content(
        &self,
        plaintext: &SecretString,
        output_path: &Path,
        recipients: &[String],
    ) -> PgpBackendResult<()> {
        let records = self.resolve_recipients(recipients)?;
        let mut rng = rand08::thread_rng();
        let mut builder =
            MessageBuilder::from_bytes("", plaintext.expose_secret().as_bytes().to_vec())
                .seipd_v1(&mut rng, SymmetricKeyAlgorithm::AES256);

        for record in &records {
            if let Some(subkey) =
                record.key.public_subkeys.iter().find(|key| key.algorithm().can_encrypt())
            {
                builder.encrypt_to_key(&mut rng, subkey).map_err(pgp_command_error)?;
            } else if record.key.algorithm().can_encrypt() {
                builder.encrypt_to_key(&mut rng, &record.key).map_err(pgp_command_error)?;
            } else {
                return Err(PgpBackendError::CommandFailed(format!(
                    "key cannot encrypt for recipient: {}",
                    record.identity
                )));
            }
        }

        let encrypted = builder.to_vec(&mut rng).map_err(pgp_command_error)?;
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent).map_err(pgp_command_error)?;
        }
        fs::write(output_path, encrypted).map_err(pgp_command_error)
    }

    fn generate_key(&self, request: KeyGenerationRequest) -> PgpBackendResult<KeyImportResult> {
        let key = Self::generate_secret_key(request)?;
        let fingerprint = self.store_private_key(&key)?;
        Ok(KeyImportResult { fingerprint, imported_private_key: true })
    }

    fn import_public_key(&self, armored_text: &str) -> PgpBackendResult<KeyImportResult> {
        let key = parse_public_key(armored_text)?;
        let fingerprint = self.store_public_key(&key)?;
        Ok(KeyImportResult { fingerprint, imported_private_key: false })
    }

    fn import_private_key(&self, armored_text: &SecretString) -> PgpBackendResult<KeyImportResult> {
        let key = parse_secret_key(armored_text.expose_secret())?;
        let fingerprint = self.store_private_key(&key)?;
        Ok(KeyImportResult { fingerprint, imported_private_key: true })
    }

    fn export_public_key(&self, fingerprint: &str) -> PgpBackendResult<KeyExportResult> {
        let record = self.resolve_public_record(fingerprint)?;
        Ok(KeyExportResult { armored_text: record.armored_text })
    }

    fn export_private_key(
        &self,
        fingerprint: &str,
        _passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<KeyExportResult> {
        let path = self.private_key_path(fingerprint);
        let armored_text = fs::read_to_string(path).map_err(pgp_command_error)?;
        Ok(KeyExportResult { armored_text })
    }

    fn delete_key(&self, fingerprint: &str) -> PgpBackendResult<()> {
        let normalized = normalize_key_ref(fingerprint);
        if normalized.is_empty() {
            return Err(PgpBackendError::CommandFailed(
                "PGP key fingerprint is required".to_string(),
            ));
        }

        let public_path = self.public_key_path(&normalized);
        let private_path = self.private_key_path(&normalized);
        let mut removed = false;

        if public_path.exists() {
            fs::remove_file(&public_path).map_err(pgp_command_error)?;
            removed = true;
        }
        if private_path.exists() {
            fs::remove_file(&private_path).map_err(pgp_command_error)?;
            removed = true;
        }
        if removed {
            Ok(())
        } else {
            Err(PgpBackendError::CommandFailed(format!(
                "no PGP key found for fingerprint: {fingerprint}"
            )))
        }
    }

    fn list_keys(&self) -> PgpBackendResult<Vec<PgpKeySummary>> {
        Ok(self
            .read_public_records()?
            .into_iter()
            .map(|record| PgpKeySummary {
                identity: record.identity,
                fingerprint: record.fingerprint,
                has_private_key: record.has_private_key,
            })
            .collect())
    }

    fn inspect_fingerprint(&self, identity: &str) -> PgpBackendResult<PgpKeyDetails> {
        let record = self.resolve_public_record(identity)?;
        Ok(PgpKeyDetails {
            identity: record.identity,
            fingerprint: record.fingerprint,
            has_private_key: record.has_private_key,
            public_key_algorithm: Some(format!("{:?}", record.key.algorithm())),
        })
    }

    fn validate_gpg_id(
        &self,
        store_root: &Path,
        target_path: &Path,
    ) -> PgpBackendResult<Vec<String>> {
        let recipients = get_dir_gpg_id_content(store_root, target_path)
            .map_err(|err| PgpBackendError::InvalidGpgId(err.to_string()))?
            .into_iter()
            .map(|recipient| recipient.trim().to_string())
            .filter(|recipient| !recipient.is_empty() && !recipient.starts_with('#'))
            .collect::<Vec<_>>();

        if recipients.is_empty() {
            return Err(PgpBackendError::InvalidGpgId(format!(
                "no recipients found for {}",
                target_path.display()
            )));
        }
        self.resolve_recipients(&recipients)?;
        Ok(recipients)
    }
}

fn parse_public_key(armored_text: &str) -> PgpBackendResult<SignedPublicKey> {
    let (key, _) = SignedPublicKey::from_string(armored_text).map_err(pgp_command_error)?;
    key.verify_bindings().map_err(pgp_command_error)?;
    Ok(key)
}

fn parse_secret_key(armored_text: &str) -> PgpBackendResult<SignedSecretKey> {
    let (key, _) = SignedSecretKey::from_string(armored_text).map_err(pgp_command_error)?;
    key.verify_bindings().map_err(pgp_command_error)?;
    Ok(key)
}

fn asc_files(dir: &Path) -> PgpBackendResult<Vec<PathBuf>> {
    if !dir.is_dir() {
        return Ok(Vec::new());
    }
    let mut paths = fs::read_dir(dir)
        .map_err(pgp_command_error)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "asc"))
        .collect::<Vec<_>>();
    paths.sort();
    Ok(paths)
}

fn key_identity(key: &SignedPublicKey) -> String {
    key.details.users.first().and_then(|user| user.id.as_str()).unwrap_or("OpenPGP key").to_string()
}

fn fingerprint(key: &impl KeyDetails) -> String {
    format!("{:X}", key.fingerprint())
}

fn secret_fingerprint(key: &SignedSecretKey) -> String {
    format!("{:X}", key.primary_key.fingerprint())
}

fn key_id(key: &impl KeyDetails) -> String {
    format!("{}", key.legacy_key_id()).to_ascii_uppercase()
}

fn normalize_key_ref(value: &str) -> String {
    value.chars().filter(|c| !c.is_whitespace()).collect::<String>().to_ascii_uppercase()
}

fn pgp_command_error(error: impl std::fmt::Display) -> PgpBackendError {
    PgpBackendError::CommandFailed(error.to_string())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use secrecy::{ExposeSecret, SecretString};
    use tempfile::tempdir;

    use super::*;
    use crate::config::cli::PgpBackendKind;
    use crate::pgp::backend::{KeyGenerationRequest, PgpBackend, PgpBackendConfig};

    fn pure_rust_config(keyring_home: &std::path::Path) -> PgpBackendConfig {
        PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            keyring_home: Some(keyring_home.display().to_string()),
            ..Default::default()
        }
    }

    #[test]
    fn generated_key_can_be_listed_and_exported() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");

        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: "Alice Example".to_string(),
                email: "alice@example.com".to_string(),
                passphrase: None,
            })
            .expect("generate key");

        assert!(!generated.fingerprint.is_empty());
        assert!(generated.imported_private_key);

        let keys = backend.list_keys().expect("list keys");
        assert_eq!(keys.len(), 1);
        assert_eq!(keys[0].fingerprint, generated.fingerprint);
        assert!(keys[0].identity.contains("Alice Example"));
        assert!(keys[0].identity.contains("alice@example.com"));
        assert!(keys[0].has_private_key);

        let public = backend.export_public_key(&generated.fingerprint).expect("public export");
        assert!(public.armored_text.contains("BEGIN PGP PUBLIC KEY BLOCK"));

        let private =
            backend.export_private_key(&generated.fingerprint, None).expect("private export");
        assert!(private.armored_text.contains("BEGIN PGP PRIVATE KEY BLOCK"));
    }

    #[test]
    fn deletes_generated_key_from_keyring() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");
        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: "Delete Me".to_string(),
                email: "delete@example.com".to_string(),
                passphrase: None,
            })
            .expect("generate key");

        backend.delete_key(&generated.fingerprint).expect("delete key");

        assert!(backend.list_keys().expect("list keys").is_empty());
        assert!(backend.export_public_key(&generated.fingerprint).is_err());
        assert!(backend.export_private_key(&generated.fingerprint, None).is_err());
    }

    #[test]
    fn deleting_missing_key_reports_error() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");

        let err = backend.delete_key("ABC").expect_err("missing key should fail");

        assert!(err.to_string().contains("ABC"));
    }

    #[test]
    fn encrypts_and_decrypts_entry_content() {
        let temp = tempdir().expect("tempdir");
        let keyring_home = temp.path().join("keys");
        let store_root = temp.path().join("store");
        fs::create_dir_all(&store_root).expect("store");

        let backend = RpgpBackend::from_config(&pure_rust_config(&keyring_home)).expect("backend");
        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: "Bob Example".to_string(),
                email: "bob@example.com".to_string(),
                passphrase: None,
            })
            .expect("generate key");

        fs::write(store_root.join(".gpg-id"), format!("{}\n", generated.fingerprint))
            .expect("write gpg-id");
        let recipients = backend
            .validate_gpg_id(&store_root, &store_root.join("secret.gpg"))
            .expect("recipients");

        let output = store_root.join("secret.gpg");
        backend
            .encrypt_content(&SecretString::from("hunter2\nusername: bob"), &output, &recipients)
            .expect("encrypt");

        let decrypted = backend.decrypt_file(&output).expect("decrypt");
        assert_eq!(decrypted.expose_secret(), "hunter2\nusername: bob");
    }
}
