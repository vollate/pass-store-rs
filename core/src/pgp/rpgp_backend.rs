use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use lazy_static::lazy_static;
use parking_lot::Mutex;
use pgp::composed::{
    Deserializable, EncryptionCaps, KeyType, Message, MessageBuilder, SecretKeyParamsBuilder,
    SignedPublicKey, SignedSecretKey, SubkeyParamsBuilder,
};
use pgp::crypto::aead::AeadAlgorithm;
use pgp::crypto::ecc_curve::ECCCurve;
use pgp::crypto::hash::HashAlgorithm;
use pgp::crypto::sym::SymmetricKeyAlgorithm;
use pgp::ser::Serialize as _;
use pgp::types::{KeyDetails, KeyVersion, Password, S2kParams, SecretParams, StringToKey};
use rand08::Rng;
use secrecy::{ExposeSecret, SecretString};
use tempfile::Builder as TempFileBuilder;
use zeroize::Zeroize;

use crate::config::cli::PgpBackendKind;
use crate::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
use crate::pgp::backend::{
    KeyGenerationRequest, PgpBackend, PgpBackendConfig, PgpBackendError, PgpBackendResult,
    PgpKeyDeletionResult, PgpKeyDetails, PgpPrivateKeyPreparation,
};
use crate::pgp::import::{format_fingerprint, public_key_identity, InspectedPgpKey};
use crate::util::fs_util::get_dir_gpg_id_content;

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct RpgpBackend {
    keyring_home: PathBuf,
}

lazy_static! {
    static ref KEY_MUTATION_LOCKS: Mutex<BTreeMap<PathBuf, Arc<Mutex<()>>>> =
        Mutex::new(BTreeMap::new());
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

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
enum AtomicWriteStage {
    Permissions,
    Sync,
    Rename,
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

    fn mutation_lock(&self, fingerprint: &str) -> Arc<Mutex<()>> {
        let path = self.private_key_path(fingerprint);
        KEY_MUTATION_LOCKS.lock().entry(path).or_insert_with(|| Arc::new(Mutex::new(()))).clone()
    }

    fn atomic_write(&self, path: &Path, bytes: &[u8], private: bool) -> PgpBackendResult<()> {
        self.atomic_write_with_hook(path, bytes, private, |_| Ok(()))
    }

    fn atomic_write_with_hook(
        &self,
        path: &Path,
        bytes: &[u8],
        private: bool,
        mut hook: impl FnMut(AtomicWriteStage) -> PgpBackendResult<()>,
    ) -> PgpBackendResult<()> {
        let parent = path.parent().ok_or(PgpBackendError::ReprotectionFailed)?;
        let fingerprint = path.file_stem().and_then(|value| value.to_str()).unwrap_or("pgp-key");
        let mut temporary = TempFileBuilder::new()
            .prefix(&format!(".{fingerprint}."))
            .suffix(".tmp")
            .tempfile_in(parent)
            .map_err(|_| PgpBackendError::ReprotectionFailed)?;

        hook(AtomicWriteStage::Permissions)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = if private { 0o600 } else { 0o644 };
            temporary
                .as_file()
                .set_permissions(fs::Permissions::from_mode(mode))
                .map_err(|_| PgpBackendError::ReprotectionFailed)?;
        }

        temporary
            .write_all(bytes)
            .and_then(|_| temporary.flush())
            .map_err(|_| PgpBackendError::ReprotectionFailed)?;
        hook(AtomicWriteStage::Sync)?;
        temporary.as_file().sync_all().map_err(|_| PgpBackendError::ReprotectionFailed)?;
        hook(AtomicWriteStage::Rename)?;
        temporary.persist(path).map_err(|_| PgpBackendError::ReprotectionFailed)?;
        File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| PgpBackendError::ReprotectionFailed)?;
        Ok(())
    }

    fn store_public_key(&self, key: &SignedPublicKey) -> PgpBackendResult<String> {
        let fingerprint = fingerprint(key);
        let armored_text = key.to_armored_string(None.into()).map_err(pgp_command_error)?;
        self.atomic_write(
            self.public_key_path(&fingerprint).as_path(),
            armored_text.as_bytes(),
            false,
        )?;
        Ok(fingerprint)
    }

    fn store_private_record(&self, key: &SignedSecretKey) -> PgpBackendResult<String> {
        let fingerprint = secret_fingerprint(key);
        let mut armored_text = key.to_armored_string(None.into()).map_err(pgp_command_error)?;
        let private_result = self.atomic_write(
            self.private_key_path(&fingerprint).as_path(),
            armored_text.as_bytes(),
            true,
        );
        armored_text.zeroize();
        private_result?;
        Ok(fingerprint)
    }

    fn store_private_key(&self, key: &SignedSecretKey) -> PgpBackendResult<String> {
        let fingerprint = self.store_private_record(key)?;
        let public_key = key.to_public_key();
        self.store_public_key(&public_key)?;
        Ok(fingerprint)
    }

    fn clean_preparation_temporaries(&self, fingerprint: &str) -> PgpBackendResult<()> {
        let prefix = format!(".{}.", normalize_key_ref(fingerprint));
        for entry in fs::read_dir(self.private_dir()).map_err(pgp_command_error)? {
            let path = entry.map_err(pgp_command_error)?.path();
            let matches = path
                .file_name()
                .and_then(|value| value.to_str())
                .is_some_and(|name| name.starts_with(&prefix) && name.ends_with(".tmp"));
            if matches {
                fs::remove_file(path).map_err(pgp_command_error)?;
            }
        }
        Ok(())
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
        // Subkeys carry their own protection. Leaving them unprotected while the primary is locked
        // would let anyone holding the keyring decrypt entries without the passphrase, since
        // decryption only ever touches the encryption subkey.
        let passphrase = request.passphrase.map(|value| value.expose_secret().to_string());

        let mut signing_key = SubkeyParamsBuilder::default();
        signing_key
            .key_type(KeyType::Ed25519Legacy)
            .can_sign(true)
            .can_encrypt(EncryptionCaps::None)
            .can_authenticate(false)
            .passphrase(passphrase.clone());

        let mut encryption_key = SubkeyParamsBuilder::default();
        encryption_key
            .key_type(KeyType::ECDH(ECCCurve::Curve25519Legacy))
            .can_sign(false)
            .can_encrypt(EncryptionCaps::All)
            .can_authenticate(false)
            .passphrase(passphrase.clone());

        let mut key_params = SecretKeyParamsBuilder::default();
        key_params
            .key_type(KeyType::Ed25519Legacy)
            .can_certify(true)
            .can_sign(false)
            .can_encrypt(EncryptionCaps::None)
            .primary_user_id(user_id)
            .passphrase(passphrase)
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

const MANAGED_V4_S2K_COUNT: u8 = 224;
const MANAGED_V6_ARGON2_T: u8 = 3;
const MANAGED_V6_ARGON2_P: u8 = 4;
const MANAGED_V6_ARGON2_M_ENC: u8 = 16;

fn managed_s2k_params(version: KeyVersion) -> PgpBackendResult<S2kParams> {
    let mut rng = rand08::thread_rng();
    match version {
        KeyVersion::V4 => {
            let sym_alg = SymmetricKeyAlgorithm::AES256;
            let mut iv = vec![0u8; sym_alg.block_size()];
            rng.fill(&mut iv[..]);
            Ok(S2kParams::Cfb {
                sym_alg,
                s2k: StringToKey::new_iterated(
                    &mut rng,
                    HashAlgorithm::Sha256,
                    MANAGED_V4_S2K_COUNT,
                ),
                iv: iv.into(),
            })
        }
        KeyVersion::V6 => {
            let sym_alg = SymmetricKeyAlgorithm::AES256;
            let aead_mode = AeadAlgorithm::Ocb;
            let mut nonce = vec![0u8; aead_mode.nonce_size()];
            rng.fill(&mut nonce[..]);
            Ok(S2kParams::Aead {
                sym_alg,
                aead_mode,
                s2k: StringToKey::new_argon2(
                    &mut rng,
                    MANAGED_V6_ARGON2_T,
                    MANAGED_V6_ARGON2_P,
                    MANAGED_V6_ARGON2_M_ENC,
                ),
                nonce: nonce.into(),
            })
        }
        _ => Err(PgpBackendError::UnsupportedProtection),
    }
}

fn has_managed_protection(params: &SecretParams, version: KeyVersion) -> bool {
    let SecretParams::Encrypted(encrypted) = params else {
        return false;
    };
    matches!(
        (version, encrypted.string_to_key_params()),
        (
            KeyVersion::V4,
            S2kParams::Cfb {
                sym_alg: SymmetricKeyAlgorithm::AES256,
                s2k: StringToKey::IteratedAndSalted {
                    hash_alg: HashAlgorithm::Sha256,
                    count: MANAGED_V4_S2K_COUNT,
                    ..
                },
                ..
            },
        ) | (
            KeyVersion::V6,
            S2kParams::Aead {
                sym_alg: SymmetricKeyAlgorithm::AES256,
                aead_mode: AeadAlgorithm::Ocb,
                s2k: StringToKey::Argon2 {
                    t: MANAGED_V6_ARGON2_T,
                    p: MANAGED_V6_ARGON2_P,
                    m_enc: MANAGED_V6_ARGON2_M_ENC,
                    ..
                },
                ..
            },
        )
    )
}

fn prepare_secret_key(
    mut key: SignedSecretKey,
    passphrase: Option<&SecretString>,
) -> PgpBackendResult<(SignedSecretKey, bool)> {
    let fingerprint_before = secret_fingerprint(&key);
    let public_before = key.to_public_key().to_bytes().map_err(pgp_command_error)?;
    let has_protected_packet = key.primary_key.secret_params().is_encrypted()
        || key.secret_subkeys.iter().any(|subkey| subkey.key.secret_params().is_encrypted());

    if !has_protected_packet {
        key.verify_bindings().map_err(pgp_command_error)?;
        return Ok((key, false));
    }

    let supplied = passphrase
        .map(ExposeSecret::expose_secret)
        .filter(|value| !value.is_empty())
        .ok_or(PgpBackendError::PassphraseRequired)?;
    let password = Password::from(supplied.to_string());
    let mut migrated = false;

    if key.primary_key.secret_params().is_encrypted() {
        let version = key.primary_key.version();
        if has_managed_protection(key.primary_key.secret_params(), version) {
            match key.primary_key.unlock(&password, |_, _| Ok(())) {
                Ok(Ok(())) => {}
                Ok(Err(_)) | Err(_) => return Err(PgpBackendError::IncorrectPassphrase),
            }
        } else {
            key.primary_key
                .remove_password(&password)
                .map_err(|_| PgpBackendError::IncorrectPassphrase)?;
            key.primary_key
                .set_password_with_s2k(&password, managed_s2k_params(version)?)
                .map_err(|_| PgpBackendError::ReprotectionFailed)?;
            migrated = true;
        }
    }

    for subkey in &mut key.secret_subkeys {
        if !subkey.key.secret_params().is_encrypted() {
            continue;
        }
        let version = subkey.key.version();
        if has_managed_protection(subkey.key.secret_params(), version) {
            match subkey.key.unlock(&password, |_, _| Ok(())) {
                Ok(Ok(())) => {}
                Ok(Err(_)) | Err(_) => return Err(PgpBackendError::IncorrectPassphrase),
            }
        } else {
            subkey
                .key
                .remove_password(&password)
                .map_err(|_| PgpBackendError::IncorrectPassphrase)?;
            subkey
                .key
                .set_password_with_s2k(&password, managed_s2k_params(version)?)
                .map_err(|_| PgpBackendError::ReprotectionFailed)?;
            migrated = true;
        }
    }

    key.verify_bindings().map_err(|_| PgpBackendError::ReprotectionFailed)?;
    let fingerprint_after = secret_fingerprint(&key);
    let public_after = key.to_public_key().to_bytes().map_err(pgp_command_error)?;
    if fingerprint_before != fingerprint_after || public_before != public_after {
        return Err(PgpBackendError::ReprotectionFailed);
    }

    Ok((key, migrated))
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
    fn decrypt_file(
        &self,
        encrypted_path: &Path,
        passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<SecretString> {
        let encrypted = fs::read(encrypted_path).map_err(pgp_command_error)?;
        let mut last_error = None::<String>;
        let password = passphrase
            .map(|value| Password::from(value.expose_secret().to_string()))
            .unwrap_or_else(Password::empty);

        for key in self.read_private_keys()? {
            let Ok(message) = Message::from_bytes(encrypted.as_slice()) else {
                return Err(PgpBackendError::CommandFailed(format!(
                    "failed to parse encrypted message: {}",
                    encrypted_path.display()
                )));
            };
            match message.decrypt(&password, &key) {
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
        let lock = self.mutation_lock(&secret_fingerprint(&key));
        let _guard = lock.lock();
        let fingerprint = self.store_private_key(&key)?;
        Ok(KeyImportResult { fingerprint, imported_private_key: true })
    }

    fn import_key(&self, key: &InspectedPgpKey) -> PgpBackendResult<KeyImportResult> {
        self.import_key_with_passphrase(key, None)
    }

    fn import_key_with_passphrase(
        &self,
        key: &InspectedPgpKey,
        passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<KeyImportResult> {
        let expected = key.fingerprint().to_string();
        let lock = self.mutation_lock(&expected);
        let _guard = lock.lock();

        let (fingerprint, imported_private_key) = match key.secret_key() {
            Some(secret_key) => {
                let (prepared, _) = prepare_secret_key(secret_key.clone(), passphrase)?;
                (self.store_private_key(&prepared)?, true)
            }
            None => {
                let public_key = key.public_key().map_err(pgp_command_error)?;
                public_key.verify_bindings().map_err(pgp_command_error)?;
                (self.store_public_key(&public_key)?, false)
            }
        };
        if normalize_key_ref(&fingerprint) != normalize_key_ref(&expected) {
            return Err(PgpBackendError::ReprotectionFailed);
        }
        Ok(KeyImportResult { fingerprint, imported_private_key })
    }

    fn prepare_private_key(
        &self,
        fingerprint: &str,
        passphrase: &SecretString,
    ) -> PgpBackendResult<PgpPrivateKeyPreparation> {
        let normalized = normalize_key_ref(fingerprint);
        if normalized.is_empty() {
            return Err(PgpBackendError::CommandFailed(
                "PGP key fingerprint is required".to_string(),
            ));
        }
        let lock = self.mutation_lock(&normalized);
        let _guard = lock.lock();
        let path = self.private_key_path(&normalized);
        let armored_text = fs::read_to_string(&path).map_err(pgp_command_error)?;
        let key = parse_secret_key(&armored_text)?;
        let (prepared, migrated) = prepare_secret_key(key, Some(passphrase))?;
        let confirmed = secret_fingerprint(&prepared);
        if normalize_key_ref(&confirmed) != normalized {
            return Err(PgpBackendError::ReprotectionFailed);
        }
        if migrated {
            self.store_private_record(&prepared)?;
        }
        Ok(PgpPrivateKeyPreparation { fingerprint: confirmed, migrated })
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

    fn delete_key(&self, fingerprint: &str) -> PgpBackendResult<PgpKeyDeletionResult> {
        let normalized = normalize_key_ref(fingerprint);
        if normalized.is_empty() {
            return Err(PgpBackendError::CommandFailed(
                "PGP key fingerprint is required".to_string(),
            ));
        }

        let public_path = self.public_key_path(&normalized);
        let private_path = self.private_key_path(&normalized);
        let lock = self.mutation_lock(&normalized);
        let _guard = lock.lock();
        let had_private_key = private_path.exists();
        let had_public_key = public_path.exists();
        if !had_private_key && !had_public_key {
            return Err(PgpBackendError::CommandFailed(format!(
                "no PGP key found for fingerprint: {fingerprint}"
            )));
        }

        self.clean_preparation_temporaries(&normalized)?;
        if had_private_key {
            fs::remove_file(&private_path).map_err(pgp_command_error)?;
        }
        let private_key_absent = !private_path.exists();
        if !private_key_absent {
            return Err(PgpBackendError::CommandFailed(
                "private PGP key deletion could not be verified".to_string(),
            ));
        }

        let public_cleanup_error = if had_public_key {
            fs::remove_file(&public_path).err().map(|error| error.to_string())
        } else {
            None
        };
        let public_key_absent = !public_path.exists();

        Ok(PgpKeyDeletionResult {
            fingerprint: normalized,
            had_private_key,
            private_key_absent,
            public_key_absent,
            public_cleanup_error,
        })
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
    public_key_identity(key)
}

fn fingerprint(key: &impl KeyDetails) -> String {
    format_fingerprint(key)
}

fn secret_fingerprint(key: &SignedSecretKey) -> String {
    format_fingerprint(&key.primary_key)
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

    use pgp::types::EncryptedSecretParams;
    use secrecy::{ExposeSecret, SecretString};
    use tempfile::tempdir;

    use super::*;
    use crate::config::cli::PgpBackendKind;
    use crate::pgp::backend::{KeyGenerationRequest, PgpBackend, PgpBackendConfig};
    use crate::pgp::import::{import_inspected_pgp_key, inspect_pgp_key_bytes};

    fn pure_rust_config(keyring_home: &std::path::Path) -> PgpBackendConfig {
        PgpBackendConfig {
            backend: PgpBackendKind::PureRust,
            keyring_home: Some(keyring_home.display().to_string()),
            ..Default::default()
        }
    }

    fn legacy_v4_s2k(count: u8) -> S2kParams {
        let mut rng = rand08::thread_rng();
        let sym_alg = SymmetricKeyAlgorithm::AES256;
        let mut iv = vec![0u8; sym_alg.block_size()];
        rng.fill(&mut iv[..]);
        S2kParams::Cfb {
            sym_alg,
            s2k: StringToKey::new_iterated(&mut rng, HashAlgorithm::Sha1, count),
            iv: iv.into(),
        }
    }

    fn nonmanaged_v4_s2k(count: u8) -> S2kParams {
        let mut rng = rand08::thread_rng();
        let sym_alg = SymmetricKeyAlgorithm::AES256;
        let mut iv = vec![0u8; sym_alg.block_size()];
        rng.fill(&mut iv[..]);
        S2kParams::Cfb {
            sym_alg,
            s2k: StringToKey::new_iterated(&mut rng, HashAlgorithm::Sha384, count),
            iv: iv.into(),
        }
    }

    fn nonmanaged_protected_key(passphrase: &str) -> SignedSecretKey {
        let mut signing_key = SubkeyParamsBuilder::default();
        signing_key
            .version(KeyVersion::V4)
            .key_type(KeyType::Ed25519Legacy)
            .can_sign(true)
            .can_encrypt(EncryptionCaps::None)
            .can_authenticate(false);
        let mut encryption_key = SubkeyParamsBuilder::default();
        encryption_key
            .version(KeyVersion::V4)
            .key_type(KeyType::ECDH(ECCCurve::Curve25519Legacy))
            .can_sign(false)
            .can_encrypt(EncryptionCaps::All)
            .can_authenticate(false);
        let mut key_params = SecretKeyParamsBuilder::default();
        key_params
            .version(KeyVersion::V4)
            .key_type(KeyType::Ed25519Legacy)
            .can_certify(true)
            .can_sign(false)
            .can_encrypt(EncryptionCaps::None)
            .primary_user_id("Legacy Example <legacy@example.com>".to_string())
            .subkeys(vec![
                signing_key.build().expect("signing subkey"),
                encryption_key.build().expect("encryption subkey"),
            ]);
        let mut key = key_params
            .build()
            .expect("legacy params")
            .generate(rand08::thread_rng())
            .expect("generate legacy fixture");
        assert_eq!(key.primary_key.version(), KeyVersion::V4);
        let password = Password::from(passphrase.to_string());
        key.primary_key
            .set_password_with_s2k(&password, nonmanaged_v4_s2k(1))
            .expect("protect primary");
        for subkey in &mut key.secret_subkeys {
            subkey
                .key
                .set_password_with_s2k(&password, nonmanaged_v4_s2k(1))
                .expect("protect subkey");
        }
        key
    }

    fn compliant_v6_key(passphrase: &str) -> SignedSecretKey {
        let encryption_key = SubkeyParamsBuilder::default()
            .version(KeyVersion::V6)
            .key_type(KeyType::X25519)
            .can_encrypt(EncryptionCaps::All)
            .passphrase(Some(passphrase.to_string()))
            .build()
            .expect("v6 encryption subkey");
        SecretKeyParamsBuilder::default()
            .version(KeyVersion::V6)
            .key_type(KeyType::Ed25519)
            .can_certify(true)
            .can_sign(true)
            .primary_user_id("Version Six <v6@example.com>".to_string())
            .passphrase(Some(passphrase.to_string()))
            .subkey(encryption_key)
            .build()
            .expect("v6 key params")
            .generate(rand08::thread_rng())
            .expect("generate v6 key")
    }

    fn all_protected_packets_are_managed(key: &SignedSecretKey) -> bool {
        has_managed_protection(key.primary_key.secret_params(), key.primary_key.version())
            && key.secret_subkeys.iter().all(|subkey| {
                has_managed_protection(subkey.key.secret_params(), subkey.key.version())
            })
    }

    #[test]
    fn managed_policy_constants_are_explicit_and_legacy_sha1_is_rejected() {
        let managed = managed_s2k_params(KeyVersion::V4).expect("managed v4");
        let managed_params =
            SecretParams::Encrypted(EncryptedSecretParams::new(vec![0u8; 20].into(), managed));
        assert!(has_managed_protection(&managed_params, KeyVersion::V4));

        let maximum_sha1 = SecretParams::Encrypted(EncryptedSecretParams::new(
            vec![0u8; 20].into(),
            legacy_v4_s2k(255),
        ));
        assert!(!has_managed_protection(&maximum_sha1, KeyVersion::V4));

        let S2kParams::Aead { sym_alg, aead_mode, s2k, .. } =
            managed_s2k_params(KeyVersion::V6).expect("managed v6")
        else {
            panic!("v6 policy must use AEAD");
        };
        assert_eq!(sym_alg, SymmetricKeyAlgorithm::AES256);
        assert_eq!(aead_mode, AeadAlgorithm::Ocb);
        assert!(matches!(s2k, StringToKey::Argon2 { t: 3, p: 4, m_enc: 16, .. }));
    }

    #[test]
    fn legacy_packets_are_reprotected_once_with_the_same_password() {
        let passphrase = SecretString::from("legacy password");
        let key = nonmanaged_protected_key(passphrase.expose_secret());
        let fingerprint_before = secret_fingerprint(&key);
        let public_before = key.to_public_key().to_bytes().expect("public bytes");

        let (prepared, migrated) =
            prepare_secret_key(key, Some(&passphrase)).expect("prepare legacy key");
        assert!(migrated);
        assert!(all_protected_packets_are_managed(&prepared));
        assert_eq!(secret_fingerprint(&prepared), fingerprint_before);
        assert_eq!(prepared.to_public_key().to_bytes().expect("public bytes"), public_before);

        let (_, migrated_again) =
            prepare_secret_key(prepared.clone(), Some(&passphrase)).expect("validate managed key");
        assert!(!migrated_again);
        assert_eq!(
            prepare_secret_key(prepared, Some(&SecretString::from("wrong password"))).unwrap_err(),
            PgpBackendError::IncorrectPassphrase
        );
    }

    #[test]
    fn compliant_v6_argon2_packets_validate_without_rewrite() {
        let passphrase = SecretString::from("v6 password");
        let key = compliant_v6_key(passphrase.expose_secret());
        assert!(all_protected_packets_are_managed(&key));
        let before = key.to_bytes().expect("serialize v6 key");

        let (prepared, migrated) =
            prepare_secret_key(key, Some(&passphrase)).expect("prepare v6 key");

        assert!(!migrated);
        assert_eq!(prepared.to_bytes().expect("serialize prepared v6 key"), before);
    }

    #[test]
    fn inconsistent_packet_passphrases_reject_import_without_writing_a_key() {
        let passphrase = SecretString::from("shared password");
        let mut key = nonmanaged_protected_key(passphrase.expose_secret());
        let mismatched = Password::from("different subkey password".to_string());
        let last = key.secret_subkeys.last_mut().expect("encryption subkey");
        last.key
            .remove_password(&Password::from(passphrase.expose_secret().to_string()))
            .expect("unlock subkey for fixture");
        last.key
            .set_password_with_s2k(&mismatched, nonmanaged_v4_s2k(1))
            .expect("reprotect subkey with a different password");
        let material = key.to_bytes().expect("serialize inconsistent fixture");
        let inspected = inspect_pgp_key_bytes(material).expect("inspect inconsistent fixture");
        let inspected_debug = format!("{inspected:?}");
        assert!(!inspected_debug.contains(passphrase.expose_secret()));
        assert!(!inspected_debug.contains("different subkey password"));
        assert!(inspected_debug.contains("<redacted>"));
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");

        let error = import_inspected_pgp_key(&backend, &inspected, Some(&passphrase), None)
            .expect_err("inconsistent packet passwords must reject the whole import");

        assert_eq!(error, crate::pgp::import::PgpImportError::IncorrectPassphrase);
        let error_text = format!("{error:?}: {error}");
        assert!(!error_text.contains(passphrase.expose_secret()));
        assert!(!error_text.contains("different subkey password"));
        assert!(backend.list_keys().expect("list keys").is_empty());
        assert!(asc_files(&backend.private_dir()).expect("private files").is_empty());
    }

    #[test]
    fn existing_legacy_record_migrates_atomically_and_compliant_record_is_not_rewritten() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");
        let passphrase = SecretString::from("legacy password");
        let key = nonmanaged_protected_key(passphrase.expose_secret());
        let fingerprint = backend.store_private_key(&key).expect("store legacy");
        let path = backend.private_key_path(&fingerprint);

        let before_wrong_password = fs::read(&path).expect("read legacy");
        assert_eq!(
            backend
                .prepare_private_key(&fingerprint, &SecretString::from("wrong password"))
                .unwrap_err(),
            PgpBackendError::IncorrectPassphrase
        );
        assert_eq!(fs::read(&path).expect("preserved legacy"), before_wrong_password);

        let first = backend.prepare_private_key(&fingerprint, &passphrase).expect("migrate");
        assert!(first.migrated);
        let after_migration = fs::read(&path).expect("read managed");
        assert_ne!(after_migration, before_wrong_password);
        let stored = parse_secret_key(&String::from_utf8(after_migration.clone()).unwrap())
            .expect("parse managed");
        assert!(all_protected_packets_are_managed(&stored));

        let second = backend.prepare_private_key(&fingerprint, &passphrase).expect("validate");
        assert!(!second.migrated);
        assert_eq!(fs::read(&path).expect("read unchanged"), after_migration);
    }

    #[test]
    fn atomic_private_write_faults_preserve_the_existing_record_and_clean_temporaries() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");
        let path = backend.private_key_path("AABBCCDD");
        fs::write(&path, b"existing protected private record").expect("existing record");

        for failed_stage in
            [AtomicWriteStage::Permissions, AtomicWriteStage::Sync, AtomicWriteStage::Rename]
        {
            let error = backend
                .atomic_write_with_hook(&path, b"replacement private record", true, |stage| {
                    if stage == failed_stage {
                        Err(PgpBackendError::ReprotectionFailed)
                    } else {
                        Ok(())
                    }
                })
                .expect_err("injected write failure");
            assert_eq!(error, PgpBackendError::ReprotectionFailed);
            assert_eq!(
                fs::read(&path).expect("preserved existing record"),
                b"existing protected private record"
            );
            assert!(
                fs::read_dir(backend.private_dir())
                    .expect("private directory")
                    .filter_map(Result::ok)
                    .all(|entry| !entry.file_name().to_string_lossy().ends_with(".tmp")),
                "a failed write must not leave a temporary private-key file"
            );
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

        let deletion = backend.delete_key(&generated.fingerprint).expect("delete key");

        assert!(deletion.had_private_key);
        assert!(deletion.private_key_absent);
        assert!(deletion.public_key_absent);
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
    fn deleting_managed_key_removes_secret_and_temporaries_without_touching_gpg_id() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");
        let passphrase = SecretString::from("protected password");
        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: "Protected Delete".to_string(),
                email: "protected-delete@example.com".to_string(),
                passphrase: Some(passphrase),
            })
            .expect("generate protected key");
        let store = temp.path().join("store");
        fs::create_dir_all(&store).expect("store");
        let gpg_id = store.join(".gpg-id");
        let gpg_id_contents = format!("{}\n", generated.fingerprint);
        fs::write(&gpg_id, &gpg_id_contents).expect("gpg-id");
        let temporary = backend.private_dir().join(format!(".{}.stray.tmp", generated.fingerprint));
        fs::write(&temporary, b"encrypted temporary").expect("temporary");

        let deletion = backend.delete_key(&generated.fingerprint).expect("delete");

        assert!(deletion.private_key_absent);
        assert!(deletion.public_key_absent);
        assert!(!temporary.exists());
        assert_eq!(fs::read_to_string(gpg_id).expect("unchanged gpg-id"), gpg_id_contents);
    }

    #[test]
    fn private_removal_failure_preserves_the_public_record() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");
        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: "Private Failure".to_string(),
                email: "private-failure@example.com".to_string(),
                passphrase: None,
            })
            .expect("generate key");
        let private_path = backend.private_key_path(&generated.fingerprint);
        fs::remove_file(&private_path).expect("replace private record");
        fs::create_dir(&private_path).expect("private removal failure fixture");

        backend
            .delete_key(&generated.fingerprint)
            .expect_err("removing a directory as a private record must fail");

        assert!(private_path.exists());
        assert!(backend.public_key_path(&generated.fingerprint).is_file());
    }

    #[test]
    fn public_cleanup_failure_reports_verified_private_absence() {
        let temp = tempdir().expect("tempdir");
        let backend = RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend");
        let generated = backend
            .generate_key(KeyGenerationRequest {
                name: "Public Failure".to_string(),
                email: "public-failure@example.com".to_string(),
                passphrase: None,
            })
            .expect("generate key");
        let public_path = backend.public_key_path(&generated.fingerprint);
        fs::remove_file(&public_path).expect("replace public record");
        fs::create_dir(&public_path).expect("public cleanup failure fixture");

        let deletion = backend.delete_key(&generated.fingerprint).expect("partial deletion");

        assert!(deletion.had_private_key);
        assert!(deletion.private_key_absent);
        assert!(!deletion.public_key_absent);
        assert!(deletion.public_cleanup_error.is_some());
        assert!(!backend.private_key_path(&generated.fingerprint).exists());
        assert!(public_path.exists());
    }

    #[test]
    fn deletion_and_preparation_of_one_fingerprint_are_serialized() {
        let temp = tempdir().expect("tempdir");
        let backend =
            Arc::new(RpgpBackend::from_config(&pure_rust_config(temp.path())).expect("backend"));
        let passphrase = SecretString::from("race password");
        let key = nonmanaged_protected_key(passphrase.expose_secret());
        let fingerprint = backend.store_private_key(&key).expect("store key");
        let barrier = Arc::new(std::sync::Barrier::new(3));

        std::thread::scope(|scope| {
            let prepare_backend = Arc::clone(&backend);
            let prepare_barrier = Arc::clone(&barrier);
            let prepare_fingerprint = fingerprint.clone();
            let prepare_passphrase = passphrase.clone();
            scope.spawn(move || {
                prepare_barrier.wait();
                let _ =
                    prepare_backend.prepare_private_key(&prepare_fingerprint, &prepare_passphrase);
            });

            let delete_backend = Arc::clone(&backend);
            let delete_barrier = Arc::clone(&barrier);
            let delete_fingerprint = fingerprint.clone();
            scope.spawn(move || {
                delete_barrier.wait();
                let deletion = delete_backend
                    .delete_key(&delete_fingerprint)
                    .expect("delete after or before preparation");
                assert!(deletion.private_key_absent);
            });
            barrier.wait();
        });

        assert!(!backend.private_key_path(&fingerprint).exists());
        assert!(!backend.public_key_path(&fingerprint).exists());
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

        let decrypted = backend.decrypt_file(&output, None).expect("decrypt");
        assert_eq!(decrypted.expose_secret(), "hunter2\nusername: bob");
    }
}
