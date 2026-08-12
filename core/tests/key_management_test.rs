use std::fs;

use pars_core::key_management::{
    add_pgp_key_to_gpg_id, delete_ssh_key, detect_imported_key_material, export_ssh_private_key,
    export_ssh_public_key, generate_ssh_ed25519_key, import_ssh_private_key_text, list_ssh_keys,
    ImportedKeyKind, PrivateKeyConfirmation,
};
use pars_core::pgp::import::inspect_pgp_key_bytes;
use serial_test::serial;

const PGP_PUBLIC: &str =
    "-----BEGIN PGP PUBLIC KEY BLOCK-----\nabc\n-----END PGP PUBLIC KEY BLOCK-----";
const PGP_PRIVATE: &str =
    "-----BEGIN PGP PRIVATE KEY BLOCK-----\nsecret\n-----END PGP PRIVATE KEY BLOCK-----";
const SSH_PRIVATE: &str =
    "-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n-----END OPENSSH PRIVATE KEY-----";

#[test]
fn detects_key_material_without_echoing_invalid_private_text() {
    assert_eq!(detect_imported_key_material(PGP_PUBLIC).unwrap(), ImportedKeyKind::PgpPublic);
    assert_eq!(detect_imported_key_material(PGP_PRIVATE).unwrap(), ImportedKeyKind::PgpPrivate);
    assert_eq!(detect_imported_key_material(SSH_PRIVATE).unwrap(), ImportedKeyKind::SshPrivate);

    let invalid = "-----BEGIN OPENSSH PRIVATE KEY-----\nnot actually complete";
    let err = detect_imported_key_material(invalid).unwrap_err();
    assert!(!err.to_string().contains("not actually complete"));
}

#[test]
fn legacy_detection_stays_marker_based_for_unparseable_material() {
    // This function still classifies by armor markers on purpose: it also handles SSH keys, which
    // the OpenPGP packet inspector cannot parse. PGP import moved to
    // `pars_core::pgp::import`, which does parse packets and rejects the blobs below.
    for (material, expected) in
        [(PGP_PUBLIC, ImportedKeyKind::PgpPublic), (PGP_PRIVATE, ImportedKeyKind::PgpPrivate)]
    {
        assert_eq!(detect_imported_key_material(material).unwrap(), expected);
        assert!(
            inspect_pgp_key_bytes(material.as_bytes().to_vec()).is_err(),
            "packet inspection must reject material that only looks like a key"
        );
    }
}

#[test]
fn generates_lists_and_exports_ssh_ed25519_keys() {
    let temp = tempfile::tempdir().unwrap();
    let key = generate_ssh_ed25519_key(temp.path(), "github-mobile").unwrap();

    assert_eq!(key.name, "github-mobile");
    assert!(key.has_private_key);
    assert!(key.fingerprint.starts_with("SHA256:"));

    let keys = list_ssh_keys(temp.path()).unwrap();
    assert_eq!(keys.len(), 1);
    assert_eq!(keys[0], key);

    let public = export_ssh_public_key(temp.path(), "github-mobile").unwrap();
    assert!(public.armored_text.starts_with("ssh-ed25519 "));

    let private = export_ssh_private_key(
        temp.path(),
        "github-mobile",
        PrivateKeyConfirmation::new("github-mobile", "EXPORT PRIVATE KEY github-mobile"),
    )
    .unwrap();
    assert!(private.armored_text.contains("BEGIN OPENSSH PRIVATE KEY"));
}

#[test]
#[serial]
fn generates_ssh_ed25519_keys_without_external_ssh_keygen() {
    let ssh_dir = tempfile::tempdir().unwrap();
    let empty_path = tempfile::tempdir().unwrap();
    let original_path = std::env::var_os("PATH");
    std::env::set_var("PATH", empty_path.path());

    let generated = generate_ssh_ed25519_key(ssh_dir.path(), "mobile-key");

    if let Some(path) = original_path {
        std::env::set_var("PATH", path);
    } else {
        std::env::remove_var("PATH");
    }

    let key = generated.unwrap();
    assert_eq!(key.name, "mobile-key");
    assert!(key.fingerprint.starts_with("SHA256:"));
    assert!(ssh_dir.path().join("mobile-key").is_file());
    assert!(ssh_dir.path().join("mobile-key.pub").is_file());
}

#[test]
fn deletes_ssh_private_and_public_key_files() {
    let temp = tempfile::tempdir().unwrap();
    generate_ssh_ed25519_key(temp.path(), "github-mobile").unwrap();

    delete_ssh_key(temp.path(), "github-mobile").unwrap();

    assert!(!temp.path().join("github-mobile").exists());
    assert!(!temp.path().join("github-mobile.pub").exists());
    assert!(list_ssh_keys(temp.path()).unwrap().is_empty());
}

#[test]
fn deleting_missing_ssh_key_reports_error() {
    let temp = tempfile::tempdir().unwrap();

    let err = delete_ssh_key(temp.path(), "missing-key").unwrap_err();

    assert!(err.to_string().contains("missing-key"));
}

#[test]
fn ssh_private_export_requires_strong_confirmation() {
    let temp = tempfile::tempdir().unwrap();
    generate_ssh_ed25519_key(temp.path(), "github-mobile").unwrap();

    let err = export_ssh_private_key(
        temp.path(),
        "github-mobile",
        PrivateKeyConfirmation::new("github-mobile", "github-mobile"),
    )
    .unwrap_err();

    assert!(err.to_string().contains("confirmation"));
}

#[test]
fn imports_ssh_private_key_text_and_derives_public_key() {
    let source = tempfile::tempdir().unwrap();
    let dest = tempfile::tempdir().unwrap();
    generate_ssh_ed25519_key(source.path(), "source-key").unwrap();
    let private_text = fs::read_to_string(source.path().join("source-key")).unwrap();

    let imported = import_ssh_private_key_text(dest.path(), "imported-key", &private_text).unwrap();

    assert_eq!(imported.name, "imported-key");
    assert!(dest.path().join("imported-key").is_file());
    assert!(dest.path().join("imported-key.pub").is_file());
    assert!(imported.fingerprint.starts_with("SHA256:"));
}

#[test]
fn appends_selected_pgp_key_to_root_gpg_id_once() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join(".gpg-id"), "alice@example.com\n").unwrap();

    add_pgp_key_to_gpg_id(temp.path(), "A991D3B4A70291EF").unwrap();
    add_pgp_key_to_gpg_id(temp.path(), "A991D3B4A70291EF").unwrap();

    let gpg_id = fs::read_to_string(temp.path().join(".gpg-id")).unwrap();
    assert_eq!(gpg_id, "alice@example.com\nA991D3B4A70291EF\n");
}

#[cfg(unix)]
#[test]
fn adding_pgp_key_reports_the_inaccessible_gpg_id_path() {
    use std::os::unix::fs::PermissionsExt;

    let temp = tempfile::tempdir().unwrap();
    let gpg_id_path = temp.path().join(".gpg-id");
    fs::write(&gpg_id_path, "alice@example.com\n").unwrap();
    fs::set_permissions(&gpg_id_path, fs::Permissions::from_mode(0o000)).unwrap();

    let result = add_pgp_key_to_gpg_id(temp.path(), "A991D3B4A70291EF");

    // Restore access before TempDir cleanup, even if the assertion below fails.
    fs::set_permissions(&gpg_id_path, fs::Permissions::from_mode(0o600)).unwrap();
    let message = result.unwrap_err().to_string();
    assert!(message.contains("failed to read PGP recipients file"), "{message}");
    assert!(message.contains(&gpg_id_path.display().to_string()), "{message}");
}
