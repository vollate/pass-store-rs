use std::collections::BTreeMap;
use std::fmt::{Display, Formatter};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::Result;
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};

use crate::config::cli::PgpBackendKind;
use crate::constants::default_constants::PGP_EXECUTABLE;
use crate::gui::{KeyExportResult, KeyImportResult, PgpKeySummary};
use crate::pgp::import::InspectedPgpKey;
use crate::util::fs_util::get_dir_gpg_id_content;

pub type PgpBackendResult<T> = Result<T, PgpBackendError>;

#[derive(Debug, Serialize, Deserialize, Eq, PartialEq, Clone)]
#[serde(default)]
pub struct PgpBackendConfig {
    pub backend: PgpBackendKind,
    pub bundled_gpg_path: Option<String>,
    pub system_gpg_path: Option<String>,
    pub pure_rust_enabled: bool,
    pub keyring_home: Option<String>,
}

impl Default for PgpBackendConfig {
    fn default() -> Self {
        Self {
            backend: PgpBackendKind::SystemGpg,
            bundled_gpg_path: None,
            system_gpg_path: None,
            pure_rust_enabled: false,
            keyring_home: None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct KeyGenerationRequest {
    pub name: String,
    pub email: String,
    pub passphrase: Option<SecretString>,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct PgpKeyDetails {
    pub identity: String,
    pub fingerprint: String,
    pub has_private_key: bool,
    pub public_key_algorithm: Option<String>,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum PgpBackendError {
    InvalidConfig(String),
    UnsupportedBackend(String),
    InvalidGpgId(String),
    CommandFailed(String),
}

impl Display for PgpBackendError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            PgpBackendError::InvalidConfig(message) => write!(f, "invalid PGP config: {message}"),
            PgpBackendError::UnsupportedBackend(message) => {
                write!(f, "unsupported PGP backend: {message}")
            }
            PgpBackendError::InvalidGpgId(message) => write!(f, "invalid .gpg-id: {message}"),
            PgpBackendError::CommandFailed(message) => write!(f, "PGP command failed: {message}"),
        }
    }
}

impl std::error::Error for PgpBackendError {}

pub trait PgpBackend {
    fn decrypt_file(
        &self,
        encrypted_path: &Path,
        passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<SecretString>;

    fn encrypt_content(
        &self,
        plaintext: &SecretString,
        output_path: &Path,
        recipients: &[String],
    ) -> PgpBackendResult<()>;

    fn generate_key(&self, request: KeyGenerationRequest) -> PgpBackendResult<KeyImportResult>;

    /// Imports already-inspected key material.
    ///
    /// Takes bytes rather than text so binary OpenPGP exports are not forced through UTF-8, and
    /// takes the inspected form so the caller has already established the key's kind, canonical
    /// fingerprint, and passphrase validity before any keyring is touched.
    fn import_key(&self, key: &InspectedPgpKey) -> PgpBackendResult<KeyImportResult>;

    fn export_public_key(&self, fingerprint: &str) -> PgpBackendResult<KeyExportResult>;

    fn export_private_key(
        &self,
        fingerprint: &str,
        passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<KeyExportResult>;

    fn delete_key(&self, fingerprint: &str) -> PgpBackendResult<()>;

    fn list_keys(&self) -> PgpBackendResult<Vec<PgpKeySummary>>;

    fn inspect_fingerprint(&self, identity: &str) -> PgpBackendResult<PgpKeyDetails>;

    fn validate_gpg_id(
        &self,
        store_root: &Path,
        target_path: &Path,
    ) -> PgpBackendResult<Vec<String>>;
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct SystemGpgBackend {
    executable: String,
    keyring_home: Option<PathBuf>,
}

impl SystemGpgBackend {
    pub fn new(executable: impl Into<String>) -> Self {
        Self { executable: executable.into(), keyring_home: None }
    }

    pub fn from_config(config: &PgpBackendConfig) -> PgpBackendResult<Self> {
        match config.backend {
            PgpBackendKind::Bundled => {
                let executable = config.bundled_gpg_path.clone().ok_or_else(|| {
                    PgpBackendError::InvalidConfig(
                        "bundled backend requires bundled_gpg_path".to_string(),
                    )
                })?;
                Ok(Self {
                    executable,
                    keyring_home: config.keyring_home.clone().map(PathBuf::from),
                })
            }
            PgpBackendKind::SystemGpg => {
                let executable =
                    config.system_gpg_path.clone().unwrap_or_else(|| PGP_EXECUTABLE.to_string());
                Ok(Self {
                    executable,
                    keyring_home: config.keyring_home.clone().map(PathBuf::from),
                })
            }
            PgpBackendKind::PureRust => Err(PgpBackendError::UnsupportedBackend(
                "pure Rust OpenPGP backend is tracked for a future milestone".to_string(),
            )),
        }
    }

    pub fn executable(&self) -> &str {
        &self.executable
    }

    fn command(&self) -> Command {
        let mut command = Command::new(&self.executable);
        if let Some(home) = &self.keyring_home {
            command.env("GNUPGHOME", home);
        }
        command
    }

    fn run_with_input(&self, args: &[&str], input: &[u8]) -> PgpBackendResult<String> {
        let mut child = self
            .command()
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|err| PgpBackendError::CommandFailed(err.to_string()))?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(input)
                .map_err(|err| PgpBackendError::CommandFailed(err.to_string()))?;
        }

        let output = child
            .wait_with_output()
            .map_err(|err| PgpBackendError::CommandFailed(err.to_string()))?;
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        } else {
            Err(PgpBackendError::CommandFailed(
                String::from_utf8_lossy(&output.stderr).into_owned(),
            ))
        }
    }

    fn run_capture(&self, args: &[&str]) -> PgpBackendResult<String> {
        let output = self
            .command()
            .args(args)
            .output()
            .map_err(|err| PgpBackendError::CommandFailed(err.to_string()))?;
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        } else {
            Err(PgpBackendError::CommandFailed(
                String::from_utf8_lossy(&output.stderr).into_owned(),
            ))
        }
    }
}

impl PgpBackend for SystemGpgBackend {
    fn decrypt_file(
        &self,
        encrypted_path: &Path,
        passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<SecretString> {
        let path = encrypted_path
            .to_str()
            .ok_or_else(|| PgpBackendError::CommandFailed("encrypted path must be UTF-8".into()))?;
        match passphrase {
            Some(passphrase) if !passphrase.expose_secret().is_empty() => self
                .run_with_input(
                    &[
                        "--batch",
                        "--pinentry-mode",
                        "loopback",
                        "--passphrase-fd",
                        "0",
                        "--decrypt",
                        path,
                    ],
                    passphrase.expose_secret().as_bytes(),
                )
                .map(SecretString::from),
            _ => self.run_capture(&["--decrypt", path]).map(SecretString::from),
        }
    }

    fn encrypt_content(
        &self,
        plaintext: &SecretString,
        output_path: &Path,
        recipients: &[String],
    ) -> PgpBackendResult<()> {
        let output = output_path
            .to_str()
            .ok_or_else(|| PgpBackendError::CommandFailed("output path must be UTF-8".into()))?;
        let mut args = vec!["--batch", "--yes", "--encrypt"];
        for recipient in recipients {
            args.push("--recipient");
            args.push(recipient);
        }
        args.push("--output");
        args.push(output);
        self.run_with_input(&args, plaintext.expose_secret().as_bytes()).map(|_| ())
    }

    fn generate_key(&self, request: KeyGenerationRequest) -> PgpBackendResult<KeyImportResult> {
        let passphrase = request.passphrase.as_ref().map(|value| value.expose_secret());
        let protection = match passphrase {
            Some(value) if !value.is_empty() => format!("Passphrase: {value}\n"),
            _ => "%no-protection\n".to_string(),
        };
        let batch = format!(
            "%echo Generating Pars key\nKey-Type: default\nSubkey-Type: default\nName-Real: {}\nName-Email: {}\nExpire-Date: 0\n{}%commit\n%echo done\n",
            request.name, request.email, protection
        );
        self.run_with_input(&["--batch", "--gen-key"], batch.as_bytes())?;
        let details = self.inspect_fingerprint(&request.email)?;
        Ok(KeyImportResult { fingerprint: details.fingerprint, imported_private_key: true })
    }

    fn import_key(&self, key: &InspectedPgpKey) -> PgpBackendResult<KeyImportResult> {
        // `gpg --import` writes its report to stderr and says nothing useful on stdout, and a
        // duplicate import produces a different status sequence than a new one. So rather than
        // parse that output, confirm the key by looking up the fingerprint the caller inspected.
        self.run_with_input(&["--batch", "--import"], key.material())?;
        let expected = key.fingerprint();
        let details = self.inspect_fingerprint(expected).map_err(|error| {
            PgpBackendError::CommandFailed(format!(
                "PGP key {expected} was imported but could not be confirmed in the keyring: {error}"
            ))
        })?;
        Ok(KeyImportResult {
            fingerprint: details.fingerprint,
            imported_private_key: details.has_private_key,
        })
    }

    fn export_public_key(&self, fingerprint: &str) -> PgpBackendResult<KeyExportResult> {
        let armored_text = self.run_capture(&["--armor", "--export", fingerprint])?;
        Ok(KeyExportResult { armored_text })
    }

    fn export_private_key(
        &self,
        fingerprint: &str,
        passphrase: Option<&SecretString>,
    ) -> PgpBackendResult<KeyExportResult> {
        let armored_text = match passphrase {
            Some(passphrase) => self.run_with_input(
                &[
                    "--batch",
                    "--pinentry-mode",
                    "loopback",
                    "--passphrase-fd",
                    "0",
                    "--armor",
                    "--export-secret-keys",
                    fingerprint,
                ],
                passphrase.expose_secret().as_bytes(),
            )?,
            None => {
                self.run_capture(&["--batch", "--armor", "--export-secret-keys", fingerprint])?
            }
        };
        Ok(KeyExportResult { armored_text })
    }

    fn delete_key(&self, fingerprint: &str) -> PgpBackendResult<()> {
        let normalized = fingerprint.trim();
        if normalized.is_empty() {
            return Err(PgpBackendError::CommandFailed(
                "PGP key fingerprint is required".to_string(),
            ));
        }
        let details = self.inspect_fingerprint(normalized)?;
        if details.has_private_key {
            self.run_capture(&["--batch", "--yes", "--delete-secret-keys", &details.fingerprint])?;
        }
        self.run_capture(&["--batch", "--yes", "--delete-keys", &details.fingerprint])?;
        Ok(())
    }

    fn list_keys(&self) -> PgpBackendResult<Vec<PgpKeySummary>> {
        let public = self.run_capture(&["--list-keys", "--with-colons"])?;
        let private =
            self.run_capture(&["--list-secret-keys", "--with-colons"]).unwrap_or_default();
        Ok(parse_key_listing(&public, &private))
    }

    fn inspect_fingerprint(&self, identity: &str) -> PgpBackendResult<PgpKeyDetails> {
        let public = self.run_capture(&["--list-keys", "--with-colons", identity])?;
        let secret_keys = self.run_capture(&["--list-secret-keys", "--with-colons", identity]).ok();
        let has_private_key =
            secret_keys.as_deref().is_some_and(|listing| listing.contains("sec:"));
        let (identity, fingerprint, algorithm) = parse_key_details(&public).ok_or_else(|| {
            PgpBackendError::CommandFailed(format!("no key found for identity: {identity}"))
        })?;
        Ok(PgpKeyDetails {
            identity,
            fingerprint,
            has_private_key,
            public_key_algorithm: algorithm,
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

        Ok(recipients)
    }
}

fn parse_key_listing(public_listing: &str, private_listing: &str) -> Vec<PgpKeySummary> {
    let private_fingerprints = fingerprints_by_uid(private_listing);
    fingerprints_by_uid(public_listing)
        .into_iter()
        .map(|(identity, fingerprint)| {
            let has_private_key = private_fingerprints.values().any(|value| value == &fingerprint);
            PgpKeySummary { identity, fingerprint, has_private_key }
        })
        .collect()
}

fn parse_key_details(listing: &str) -> Option<(String, String, Option<String>)> {
    let mut fingerprint = None::<String>;
    let mut algorithm = None::<String>;

    for line in listing.lines() {
        let fields = line.split(':').collect::<Vec<_>>();
        match fields.first().copied() {
            Some("pub") => algorithm = fields.get(3).map(|value| (*value).to_string()),
            Some("fpr") => fingerprint = fields.get(9).map(|value| (*value).to_string()),
            Some("uid") => {
                if let (Some(identity), Some(fingerprint)) = (fields.get(9), fingerprint.take()) {
                    return Some(((*identity).to_string(), fingerprint, algorithm));
                }
            }
            _ => {}
        }
    }

    None
}

fn fingerprints_by_uid(listing: &str) -> BTreeMap<String, String> {
    let mut keys = BTreeMap::new();
    let mut pending_fingerprint = None::<String>;

    for line in listing.lines() {
        let fields = line.split(':').collect::<Vec<_>>();
        match fields.first().copied() {
            Some("fpr") => pending_fingerprint = fields.get(9).map(|value| value.to_string()),
            Some("uid") => {
                if let (Some(identity), Some(fingerprint)) =
                    (fields.get(9), pending_fingerprint.take())
                {
                    keys.insert((*identity).to_string(), fingerprint);
                }
            }
            _ => {}
        }
    }

    keys
}
