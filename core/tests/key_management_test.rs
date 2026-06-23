use std::fs;

use pars_core::key_management::{
    add_pgp_key_to_gpg_id, detect_imported_key_material, export_ssh_private_key,
    export_ssh_public_key, generate_ssh_ed25519_key, import_ssh_private_key_text, list_ssh_keys,
    ImportedKeyKind, PrivateKeyConfirmation,
};

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
