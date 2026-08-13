//! Source-independent inspection of PGP key material.
//!
//! Import used to be classified by armor markers and by which GUI control the user picked, which
//! made a file synonymous with a private key and left binary OpenPGP exports unreadable. Everything
//! here works on bytes and on parsed packets instead, so pasted text and picked files go through
//! one path and the detected kind comes from the material.

use std::fmt::{Debug, Display, Formatter};
use std::fs;
use std::io::Cursor;
use std::path::Path;

use pgp::composed::{PublicOrSecret, SignedPublicKey, SignedSecretKey};
use pgp::packet;
use pgp::ser::Serialize as _;
use pgp::types::{KeyDetails, Password};
use secrecy::{ExposeSecret, SecretSlice, SecretString};

use crate::pgp::backend::PgpBackend;

pub type PgpImportResult<T> = Result<T, PgpImportError>;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum PgpKeyMaterialKind {
    Public,
    Private,
}

impl PgpKeyMaterialKind {
    pub fn as_str(self) -> &'static str {
        match self {
            PgpKeyMaterialKind::Public => "public",
            PgpKeyMaterialKind::Private => "private",
        }
    }
}

impl Display for PgpKeyMaterialKind {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// What the GUI needs to decide the next step. Deliberately free of key bytes so it can cross the
/// bridge and be logged.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct PgpImportInspection {
    pub kind: PgpKeyMaterialKind,
    /// Canonical primary-key fingerprint, the identity every later step keys off.
    pub fingerprint: String,
    pub identity: String,
    pub has_private_key: bool,
    /// True when any secret packet is locked. See [`unlock_target`] for why "any" rather than
    /// "the encryption subkey".
    pub requires_passphrase: bool,
    pub armored: bool,
}

/// Parsed key material plus the bytes it came from.
///
/// Move-only: the bytes are secret when the material is a private key, and cloning them would
/// widen the window in which they sit in memory. [`Debug`] is hand-written so the bytes cannot be
/// printed into a log or an error.
pub struct InspectedPgpKey {
    inspection: PgpImportInspection,
    key: PublicOrSecret,
    bytes: SecretSlice<u8>,
}

impl Debug for InspectedPgpKey {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InspectedPgpKey")
            .field("inspection", &self.inspection)
            .field("key", &"<redacted>")
            .field("bytes", &"<redacted>")
            .finish()
    }
}

impl InspectedPgpKey {
    pub fn inspection(&self) -> &PgpImportInspection {
        &self.inspection
    }

    pub fn kind(&self) -> PgpKeyMaterialKind {
        self.inspection.kind
    }

    pub fn fingerprint(&self) -> &str {
        &self.inspection.fingerprint
    }

    pub fn requires_passphrase(&self) -> bool {
        self.inspection.requires_passphrase
    }

    /// Raw material as supplied, for backends that import by piping bytes to an external `gpg`.
    pub fn material(&self) -> &[u8] {
        self.bytes.expose_secret()
    }

    pub fn public_key(&self) -> PgpImportResult<SignedPublicKey> {
        match &self.key {
            PublicOrSecret::Public(key) => Ok(key.clone()),
            PublicOrSecret::Secret(key) => Ok(key.to_public_key()),
        }
    }

    pub fn secret_key(&self) -> Option<&SignedSecretKey> {
        match &self.key {
            PublicOrSecret::Secret(key) => Some(key),
            PublicOrSecret::Public(_) => None,
        }
    }

    /// Confirms the passphrase unlocks this exact material.
    ///
    /// Callers must run this before mutating a keyring, so a typo cannot leave an unusable key
    /// behind.
    pub fn validate_passphrase(&self, passphrase: Option<&SecretString>) -> PgpImportResult<()> {
        let Some(secret_key) = self.secret_key() else {
            return Ok(());
        };
        validate_secret_key_passphrase(secret_key, passphrase)
    }

    /// Whether every encryption-capable secret packet is passphrase protected.
    ///
    /// `None` when the material has no private key. Distinct from [`Self::requires_passphrase`]:
    /// this asks whether the packets that actually decrypt entries are locked, which is what
    /// determines if the passphrase is really protecting anything.
    pub fn encryption_material_is_protected(&self) -> Option<bool> {
        let secret_key = self.secret_key()?;
        let mut encryption_packets = 0usize;
        let mut protected = 0usize;
        for subkey in &secret_key.secret_subkeys {
            if subkey.key.public_key().algorithm().can_encrypt() {
                encryption_packets += 1;
                if subkey.key.secret_params().is_encrypted() {
                    protected += 1;
                }
            }
        }
        if secret_key.primary_key.algorithm().can_encrypt() {
            encryption_packets += 1;
            if secret_key.primary_key.secret_params().is_encrypted() {
                protected += 1;
            }
        }
        if encryption_packets == 0 {
            return Some(false);
        }
        Some(protected == encryption_packets)
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum PgpImportError {
    /// Material that neither backend can safely inspect and import.
    UnsupportedMaterial(String),
    /// A legacy type-specific import asked for a kind the material does not have.
    KindMismatch {
        expected: PgpKeyMaterialKind,
        detected: PgpKeyMaterialKind,
    },
    PassphraseRequired,
    IncorrectPassphrase,
    UnsupportedProtection,
    ReprotectionFailed,
    Backend(String),
}

impl Display for PgpImportError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            PgpImportError::UnsupportedMaterial(message) => {
                write!(f, "unsupported PGP key material: {message}")
            }
            PgpImportError::KindMismatch { expected, detected } => write!(
                f,
                "expected {expected} PGP key material but the supplied material is {detected}"
            ),
            PgpImportError::PassphraseRequired => {
                write!(f, "this PGP private key is protected by a passphrase")
            }
            PgpImportError::IncorrectPassphrase => {
                write!(f, "the PGP private key passphrase is incorrect")
            }
            PgpImportError::UnsupportedProtection => {
                write!(f, "the PGP private key uses unsupported packet protection")
            }
            PgpImportError::ReprotectionFailed => {
                write!(f, "the PGP private key could not be safely re-protected")
            }
            PgpImportError::Backend(message) => write!(f, "PGP key import failed: {message}"),
        }
    }
}

impl std::error::Error for PgpImportError {}

impl PgpImportError {
    /// Stable identifier the bridge maps to a typed Flutter failure.
    pub fn kind_str(&self) -> &'static str {
        match self {
            PgpImportError::UnsupportedMaterial(_) => "unsupported_material",
            PgpImportError::KindMismatch { .. } => "kind_mismatch",
            PgpImportError::PassphraseRequired => "passphrase_required",
            PgpImportError::IncorrectPassphrase => "incorrect_passphrase",
            PgpImportError::UnsupportedProtection => "unsupported_protection",
            PgpImportError::ReprotectionFailed => "reprotection_failed",
            PgpImportError::Backend(_) => "backend_error",
        }
    }
}

/// Inspects key material that may be ASCII-armored or binary, public or private.
pub fn inspect_pgp_key_bytes(material: impl Into<Vec<u8>>) -> PgpImportResult<InspectedPgpKey> {
    let bytes = SecretSlice::from(material.into());
    let armored = !is_binary_material(bytes.expose_secret())?;
    let key = parse_single_key(bytes.expose_secret())?;
    let inspection = inspect_parsed_key(&key, armored)?;
    Ok(InspectedPgpKey { inspection, key, bytes })
}

/// Reads a key file as bytes so binary OpenPGP exports are not forced through UTF-8.
pub fn inspect_pgp_key_file(path: &Path) -> PgpImportResult<InspectedPgpKey> {
    let material = fs::read(path).map_err(|error| {
        // The path is caller-supplied, not secret; the contents never reach the message.
        PgpImportError::UnsupportedMaterial(format!(
            "failed to read key file {}: {error}",
            path.display()
        ))
    })?;
    inspect_pgp_key_bytes(material)
}

/// Confirms `passphrase` unlocks `secret_key` in memory.
///
/// Does not consult a GPG agent, and does not need a configured store, so the answer is the same
/// for system GPG and pure-Rust keyrings.
pub fn validate_secret_key_passphrase(
    secret_key: &SignedSecretKey,
    passphrase: Option<&SecretString>,
) -> PgpImportResult<()> {
    let Some(target) = unlock_target(secret_key) else {
        // Nothing is locked, so there is no passphrase to be right or wrong about.
        return Ok(());
    };

    let supplied = passphrase.map(ExposeSecret::expose_secret).filter(|value| !value.is_empty());
    let Some(supplied) = supplied else {
        return Err(PgpImportError::PassphraseRequired);
    };

    let password = Password::from(supplied.to_string());
    // `unlock` nests its results: the outer error is the decryption failure that means "wrong
    // passphrase", the inner one belongs to the closure. The unlocked material is dropped as soon
    // as the closure returns.
    let unlocked = match target {
        UnlockTarget::Primary(key) => key.unlock(&password, |_, _| Ok(())),
        UnlockTarget::Subkey(key) => key.unlock(&password, |_, _| Ok(())),
    };
    match unlocked {
        Ok(Ok(())) => Ok(()),
        Ok(Err(_)) | Err(_) => Err(PgpImportError::IncorrectPassphrase),
    }
}

/// Re-encodes key material as binary OpenPGP packets.
///
/// Exists so tests can build binary fixtures from an armored export without depending on `pgp`
/// directly.
pub fn pgp_key_material_to_binary(material: &[u8]) -> PgpImportResult<Vec<u8>> {
    let key = parse_single_key(material)?;
    match key {
        PublicOrSecret::Public(key) => key.to_bytes(),
        PublicOrSecret::Secret(key) => key.to_bytes(),
    }
    .map_err(|error| PgpImportError::UnsupportedMaterial(error.to_string()))
}

/// Outcome of a completed import: the material as inspected, plus what the backend confirmed.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct PgpImportOutcome {
    pub inspection: PgpImportInspection,
    /// Backend-confirmed fingerprint. Equals `inspection.fingerprint` on every supported backend.
    pub fingerprint: String,
    /// Backend-confirmed display identity, which is what the GUI shows.
    pub identity: String,
    pub imported_private_key: bool,
}

/// Imports inspected material into `backend`, validating any passphrase first.
///
/// The ordering is the point: inspect, then validate, and only then mutate. An absent or incorrect
/// passphrase returns before the backend is touched, so a typo cannot leave an unusable key in the
/// keyring. After import the key is confirmed by its canonical fingerprint, which is what makes the
/// result correct for both new and duplicate imports.
pub fn import_inspected_pgp_key(
    backend: &dyn PgpBackend,
    key: &InspectedPgpKey,
    passphrase: Option<&SecretString>,
    expected_kind: Option<PgpKeyMaterialKind>,
) -> PgpImportResult<PgpImportOutcome> {
    if let Some(expected) = expected_kind {
        let detected = key.kind();
        if expected != detected {
            return Err(PgpImportError::KindMismatch { expected, detected });
        }
    }
    let imported =
        backend.import_key_with_passphrase(key, passphrase).map_err(import_backend_error)?;
    let fingerprint = if imported.fingerprint.trim().is_empty() {
        key.fingerprint()
    } else {
        &imported.fingerprint
    }
    .to_string();

    // Never build a key-bound session from an unconfirmed fingerprint: read the identity back from
    // the backend that now owns the key.
    let details = backend
        .inspect_fingerprint(&fingerprint)
        .map_err(|error| PgpImportError::Backend(error.to_string()))?;

    Ok(PgpImportOutcome {
        inspection: key.inspection().clone(),
        fingerprint: details.fingerprint,
        identity: details.identity,
        imported_private_key: imported.imported_private_key || details.has_private_key,
    })
}

fn import_backend_error(error: crate::pgp::backend::PgpBackendError) -> PgpImportError {
    use crate::pgp::backend::PgpBackendError;

    match error {
        PgpBackendError::PassphraseRequired => PgpImportError::PassphraseRequired,
        PgpBackendError::IncorrectPassphrase => PgpImportError::IncorrectPassphrase,
        PgpBackendError::UnsupportedProtection => PgpImportError::UnsupportedProtection,
        PgpBackendError::ReprotectionFailed => PgpImportError::ReprotectionFailed,
        other => PgpImportError::Backend(other.to_string()),
    }
}

/// Inspects pasted text and imports it in one step.
pub fn import_pgp_key_text(
    backend: &dyn PgpBackend,
    armored_text: String,
    passphrase: Option<&SecretString>,
    expected_kind: Option<PgpKeyMaterialKind>,
) -> PgpImportResult<PgpImportOutcome> {
    let key = inspect_pgp_key_bytes(armored_text.into_bytes())?;
    import_inspected_pgp_key(backend, &key, passphrase, expected_kind)
}

/// Reads, inspects, and imports a key file without its bytes leaving Rust.
pub fn import_pgp_key_file(
    backend: &dyn PgpBackend,
    path: &Path,
    passphrase: Option<&SecretString>,
    expected_kind: Option<PgpKeyMaterialKind>,
) -> PgpImportResult<PgpImportOutcome> {
    let key = inspect_pgp_key_file(path)?;
    import_inspected_pgp_key(backend, &key, passphrase, expected_kind)
}

enum UnlockTarget<'a> {
    Primary(&'a packet::SecretKey),
    Subkey(&'a packet::SecretSubkey),
}

/// Picks the packet to validate a passphrase against.
///
/// Only ever returns a *locked* packet. An unprotected packet has `SecretParams::Plain`, and
/// `unlock` accepts any password against it, so validating there would wave through a typo.
/// Encryption-capable packets come first because that is the material used to read entries.
fn unlock_target(secret_key: &SignedSecretKey) -> Option<UnlockTarget<'_>> {
    let locked_encryption_subkey = secret_key.secret_subkeys.iter().find(|subkey| {
        subkey.key.secret_params().is_encrypted() && subkey.key.algorithm().can_encrypt()
    });
    if let Some(subkey) = locked_encryption_subkey {
        return Some(UnlockTarget::Subkey(&subkey.key));
    }

    let primary_is_locked = secret_key.primary_key.secret_params().is_encrypted();
    if primary_is_locked && secret_key.primary_key.algorithm().can_encrypt() {
        return Some(UnlockTarget::Primary(&secret_key.primary_key));
    }

    if let Some(subkey) =
        secret_key.secret_subkeys.iter().find(|subkey| subkey.key.secret_params().is_encrypted())
    {
        return Some(UnlockTarget::Subkey(&subkey.key));
    }
    if primary_is_locked {
        return Some(UnlockTarget::Primary(&secret_key.primary_key));
    }
    None
}

fn inspect_parsed_key(key: &PublicOrSecret, armored: bool) -> PgpImportResult<PgpImportInspection> {
    match key {
        PublicOrSecret::Public(public_key) => Ok(PgpImportInspection {
            kind: PgpKeyMaterialKind::Public,
            fingerprint: format_fingerprint(public_key),
            identity: public_key_identity(public_key),
            has_private_key: false,
            requires_passphrase: false,
            armored,
        }),
        PublicOrSecret::Secret(secret_key) => Ok(PgpImportInspection {
            kind: PgpKeyMaterialKind::Private,
            fingerprint: format_fingerprint(&secret_key.primary_key),
            identity: public_key_identity(&secret_key.to_public_key()),
            has_private_key: true,
            requires_passphrase: secret_key_is_protected(secret_key),
            armored,
        }),
    }
}

/// True when any secret packet is locked.
///
/// Not "the encryption subkey is locked": pure-Rust keys generated before this change protect only
/// the primary key, and reporting those as unprotected would skip the passphrase step for a key the
/// user did set a passphrase on.
fn secret_key_is_protected(secret_key: &SignedSecretKey) -> bool {
    secret_key.primary_key.secret_params().is_encrypted()
        || secret_key.secret_subkeys.iter().any(|subkey| subkey.key.secret_params().is_encrypted())
}

fn parse_single_key(material: &[u8]) -> PgpImportResult<PublicOrSecret> {
    if material.iter().all(|byte| byte.is_ascii_whitespace()) {
        return Err(PgpImportError::UnsupportedMaterial("key material is empty".to_string()));
    }
    reject_multiple_armor_blocks(material)?;

    // `from_reader_many` detects armor versus binary for us, so one call covers every supported
    // source. Bindings are intentionally not verified here: `gpg` accepts material that rPGP is
    // stricter about, and the pure-Rust backend verifies before it stores anything.
    let (keys, _headers) = PublicOrSecret::from_reader_many(Cursor::new(material))
        .map_err(|error| PgpImportError::UnsupportedMaterial(error.to_string()))?;

    let mut keys = keys.into_iter();
    let first = keys
        .next()
        .ok_or_else(|| {
            PgpImportError::UnsupportedMaterial(
                "no OpenPGP key found in the supplied material".to_string(),
            )
        })?
        .map_err(|error| PgpImportError::UnsupportedMaterial(error.to_string()))?;

    if keys.next().is_some() {
        return Err(multiple_keys_error());
    }
    Ok(first)
}

/// Rejects material holding more than one armored block.
///
/// rPGP stops at the first `-----END-----`, so without this a file containing several exports would
/// import its first key and silently drop the rest.
fn reject_multiple_armor_blocks(material: &[u8]) -> PgpImportResult<()> {
    const HEADER: &[u8] = b"-----BEGIN PGP ";
    let blocks = material.windows(HEADER.len()).filter(|window| *window == HEADER).count();
    if blocks > 1 {
        return Err(multiple_keys_error());
    }
    Ok(())
}

fn multiple_keys_error() -> PgpImportError {
    PgpImportError::UnsupportedMaterial(
        "the supplied material contains more than one OpenPGP key; import one key at a time"
            .to_string(),
    )
}

/// Mirrors rPGP's own armor sniffing: a set high bit on the first meaningful byte marks a binary
/// packet tag, anything else is treated as ASCII armor.
fn is_binary_material(material: &[u8]) -> PgpImportResult<bool> {
    let first = material
        .iter()
        .find(|byte| !byte.is_ascii_whitespace())
        .ok_or_else(|| PgpImportError::UnsupportedMaterial("key material is empty".to_string()))?;
    Ok(first & 0x80 != 0)
}

pub(crate) fn format_fingerprint(key: &impl KeyDetails) -> String {
    format!("{:X}", key.fingerprint())
}

pub(crate) fn public_key_identity(key: &SignedPublicKey) -> String {
    key.details.users.first().and_then(|user| user.id.as_str()).unwrap_or("OpenPGP key").to_string()
}

#[cfg(test)]
mod tests {
    use pgp::composed::{EncryptionCaps, KeyType, SecretKeyParamsBuilder, SubkeyParamsBuilder};
    use pgp::crypto::ecc_curve::ECCCurve;

    use super::*;

    const PASSPHRASE: &str = "correct horse battery staple";

    /// Builds a key with independently chosen primary and subkey protection.
    ///
    /// Fixtures are generated rather than checked in so the diff stays reviewable and no single
    /// rPGP serialization gets pinned forever.
    fn generate_secret_key(
        primary_passphrase: Option<&str>,
        subkey_passphrase: Option<&str>,
    ) -> SignedSecretKey {
        let mut encryption_key = SubkeyParamsBuilder::default();
        encryption_key
            .key_type(KeyType::ECDH(ECCCurve::Curve25519Legacy))
            .can_sign(false)
            .can_encrypt(EncryptionCaps::All)
            .can_authenticate(false)
            .passphrase(subkey_passphrase.map(str::to_string));

        let mut key_params = SecretKeyParamsBuilder::default();
        key_params
            .key_type(KeyType::Ed25519Legacy)
            .can_certify(true)
            .can_sign(false)
            .can_encrypt(EncryptionCaps::None)
            .primary_user_id("Inspect Example <inspect@example.com>".to_string())
            .passphrase(primary_passphrase.map(str::to_string))
            .subkeys(vec![encryption_key.build().expect("subkey params")]);

        key_params
            .build()
            .expect("key params")
            .generate(rand08::thread_rng())
            .expect("generate key")
    }

    fn armored_private(key: &SignedSecretKey) -> Vec<u8> {
        key.to_armored_string(None.into()).expect("armor private key").into_bytes()
    }

    fn armored_public(key: &SignedSecretKey) -> Vec<u8> {
        key.to_public_key().to_armored_string(None.into()).expect("armor public key").into_bytes()
    }

    fn binary_private(key: &SignedSecretKey) -> Vec<u8> {
        key.to_bytes().expect("binary private key")
    }

    fn binary_public(key: &SignedSecretKey) -> Vec<u8> {
        key.to_public_key().to_bytes().expect("binary public key")
    }

    #[test]
    fn inspects_armored_public_key_material() {
        let key = generate_secret_key(None, None);
        let inspected = inspect_pgp_key_bytes(armored_public(&key)).expect("inspect");

        let inspection = inspected.inspection();
        assert_eq!(inspection.kind, PgpKeyMaterialKind::Public);
        assert_eq!(inspection.fingerprint, format_fingerprint(&key.primary_key));
        assert!(inspection.identity.contains("inspect@example.com"));
        assert!(!inspection.has_private_key);
        assert!(!inspection.requires_passphrase);
        assert!(inspection.armored);
    }

    #[test]
    fn inspects_binary_public_key_material() {
        let key = generate_secret_key(None, None);
        let inspected = inspect_pgp_key_bytes(binary_public(&key)).expect("inspect");

        let inspection = inspected.inspection();
        assert_eq!(inspection.kind, PgpKeyMaterialKind::Public);
        assert!(!inspection.armored);
        assert_eq!(inspection.fingerprint, format_fingerprint(&key.primary_key));
    }

    #[test]
    fn inspects_armored_unprotected_private_key_material() {
        let key = generate_secret_key(None, None);
        let inspected = inspect_pgp_key_bytes(armored_private(&key)).expect("inspect");

        let inspection = inspected.inspection();
        assert_eq!(inspection.kind, PgpKeyMaterialKind::Private);
        assert!(inspection.has_private_key);
        assert!(!inspection.requires_passphrase);
        assert!(inspection.armored);
    }

    #[test]
    fn inspects_binary_protected_private_key_material() {
        let key = generate_secret_key(Some(PASSPHRASE), Some(PASSPHRASE));
        let inspected = inspect_pgp_key_bytes(binary_private(&key)).expect("inspect");

        let inspection = inspected.inspection();
        assert_eq!(inspection.kind, PgpKeyMaterialKind::Private);
        assert!(inspection.has_private_key);
        assert!(inspection.requires_passphrase);
        assert!(!inspection.armored);
    }

    #[test]
    fn source_encoding_does_not_change_detected_kind_or_fingerprint() {
        let key = generate_secret_key(Some(PASSPHRASE), Some(PASSPHRASE));
        let expected = format_fingerprint(&key.primary_key);

        for (material, kind, armored) in [
            (armored_public(&key), PgpKeyMaterialKind::Public, true),
            (binary_public(&key), PgpKeyMaterialKind::Public, false),
            (armored_private(&key), PgpKeyMaterialKind::Private, true),
            (binary_private(&key), PgpKeyMaterialKind::Private, false),
        ] {
            let inspection = inspect_pgp_key_bytes(material).expect("inspect").inspection().clone();
            assert_eq!(inspection.kind, kind);
            assert_eq!(inspection.armored, armored);
            assert_eq!(inspection.fingerprint, expected);
        }
    }

    #[test]
    fn detects_protection_when_only_the_primary_key_is_locked() {
        // Pure-Rust keys generated before this change look exactly like this. Reporting them as
        // unprotected would skip the passphrase step for a key that has one.
        let key = generate_secret_key(Some(PASSPHRASE), None);
        let inspected = inspect_pgp_key_bytes(armored_private(&key)).expect("inspect");

        assert!(inspected.requires_passphrase());
    }

    #[test]
    fn rejects_empty_and_unparseable_key_material() {
        for material in ["", "   \n\t ", "not a key at all"] {
            let error = inspect_pgp_key_bytes(material.as_bytes().to_vec())
                .expect_err("unparseable material should fail");
            assert!(
                matches!(error, PgpImportError::UnsupportedMaterial(_)),
                "{material:?} produced {error:?}"
            );
        }

        let armored_but_not_a_key =
            "-----BEGIN PGP PUBLIC KEY BLOCK-----\nabc\n-----END PGP PUBLIC KEY BLOCK-----";
        let error = inspect_pgp_key_bytes(armored_but_not_a_key.as_bytes().to_vec())
            .expect_err("non-parseable armor should fail");
        assert!(matches!(error, PgpImportError::UnsupportedMaterial(_)), "{error:?}");
    }

    #[test]
    fn rejects_material_containing_more_than_one_key() {
        let first = generate_secret_key(None, None);
        let second = generate_secret_key(None, None);

        // Armored: rPGP would stop at the first END marker, so the guard has to catch this.
        let mut armored = armored_public(&first);
        armored.extend_from_slice(&armored_public(&second));
        let error = inspect_pgp_key_bytes(armored).expect_err("multiple armored keys should fail");
        assert!(matches!(error, PgpImportError::UnsupportedMaterial(_)), "{error:?}");

        // Binary: the packet iterator yields both, so the second-key check catches it.
        let mut binary = binary_public(&first);
        binary.extend_from_slice(&binary_public(&second));
        let error = inspect_pgp_key_bytes(binary).expect_err("multiple binary keys should fail");
        assert!(matches!(error, PgpImportError::UnsupportedMaterial(_)), "{error:?}");
    }

    #[test]
    fn validates_correct_protected_private_key_passphrase() {
        let key = generate_secret_key(Some(PASSPHRASE), Some(PASSPHRASE));
        let inspected = inspect_pgp_key_bytes(armored_private(&key)).expect("inspect");

        inspected
            .validate_passphrase(Some(&SecretString::from(PASSPHRASE)))
            .expect("correct passphrase should validate");
    }

    #[test]
    fn rejects_incorrect_protected_private_key_passphrase() {
        let key = generate_secret_key(Some(PASSPHRASE), Some(PASSPHRASE));
        let inspected = inspect_pgp_key_bytes(armored_private(&key)).expect("inspect");

        let error = inspected
            .validate_passphrase(Some(&SecretString::from("wrong passphrase")))
            .expect_err("incorrect passphrase should fail");
        assert_eq!(error, PgpImportError::IncorrectPassphrase);
    }

    #[test]
    fn rejects_absent_protected_private_key_passphrase() {
        let key = generate_secret_key(Some(PASSPHRASE), Some(PASSPHRASE));
        let inspected = inspect_pgp_key_bytes(armored_private(&key)).expect("inspect");

        assert_eq!(
            inspected.validate_passphrase(None).expect_err("absent passphrase should fail"),
            PgpImportError::PassphraseRequired
        );
        // An empty string is a user submitting the form without typing anything, not a passphrase.
        assert_eq!(
            inspected
                .validate_passphrase(Some(&SecretString::from("")))
                .expect_err("empty passphrase should fail"),
            PgpImportError::PassphraseRequired
        );
    }

    #[test]
    fn validates_passphrase_against_a_locked_primary_when_the_subkey_is_unprotected() {
        // The unprotected subkey would accept any password, so validation must not use it.
        let key = generate_secret_key(Some(PASSPHRASE), None);
        let inspected = inspect_pgp_key_bytes(armored_private(&key)).expect("inspect");

        inspected
            .validate_passphrase(Some(&SecretString::from(PASSPHRASE)))
            .expect("correct passphrase should validate");
        assert_eq!(
            inspected
                .validate_passphrase(Some(&SecretString::from("wrong passphrase")))
                .expect_err("incorrect passphrase should still be rejected"),
            PgpImportError::IncorrectPassphrase
        );
    }

    #[test]
    fn unprotected_and_public_material_validates_without_a_passphrase() {
        let key = generate_secret_key(None, None);

        inspect_pgp_key_bytes(armored_private(&key))
            .expect("inspect")
            .validate_passphrase(None)
            .expect("unprotected private key needs no passphrase");
        inspect_pgp_key_bytes(armored_public(&key))
            .expect("inspect")
            .validate_passphrase(None)
            .expect("public key needs no passphrase");
    }

    #[test]
    fn converts_armored_material_to_binary_without_changing_identity() {
        let key = generate_secret_key(None, None);
        let binary = pgp_key_material_to_binary(&armored_public(&key)).expect("to binary");

        let inspected = inspect_pgp_key_bytes(binary).expect("inspect");
        assert!(!inspected.inspection().armored);
        assert_eq!(inspected.fingerprint(), format_fingerprint(&key.primary_key));
    }

    #[test]
    fn errors_and_debug_output_never_contain_secret_inputs() {
        let key = generate_secret_key(Some(PASSPHRASE), Some(PASSPHRASE));
        let private_material = armored_private(&key);
        let inspected = inspect_pgp_key_bytes(private_material.clone()).expect("inspect");

        let armored_text = String::from_utf8(private_material).expect("armor is utf8");
        let secret_body = armored_text
            .lines()
            .find(|line| line.len() > 20 && !line.starts_with("-----"))
            .expect("armored body line");

        let mut rendered = vec![format!("{inspected:?}")];
        for error in [
            inspected.validate_passphrase(None).err(),
            inspected.validate_passphrase(Some(&SecretString::from("wrong passphrase"))).err(),
            inspect_pgp_key_bytes(b"not a key".to_vec()).err(),
        ]
        .into_iter()
        .flatten()
        {
            rendered.push(format!("{error}"));
            rendered.push(format!("{error:?}"));
        }

        for text in rendered {
            assert!(!text.contains(PASSPHRASE), "leaked passphrase in: {text}");
            assert!(!text.contains("wrong passphrase"), "leaked passphrase in: {text}");
            assert!(!text.contains(secret_body), "leaked private key material in: {text}");
            assert!(!text.contains("PRIVATE KEY BLOCK"), "leaked private key material in: {text}");
        }
    }
}
