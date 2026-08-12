## MODIFIED Requirements

### Requirement: Bridge key methods SHALL cover PGP and SSH key operations

The bridge SHALL expose key listing, PGP key-material inspection from text and
file sources, source-independent PGP import with exact-key passphrase
validation, PGP key generate/export, `.gpg-id` append, SSH key
generate/import/export, and a GitHub SSH settings URL. PGP inspection and import
responses SHALL return typed key kind, protection state, canonical fingerprint,
and sanitized failures needed by Flutter without returning secret material.

Sources: `bridge/src/api.rs`, `core/src/key_management.rs`,
`bridge/tests/bridge_smoke_test.rs`

#### Scenario: GitHub SSH settings returns fixed URL

- WHEN `open_github_ssh_settings` is called
- THEN the response URL is `https://github.com/settings/keys`

#### Scenario: PGP file inspection reads key bytes in Rust

- GIVEN a selected local file contains supported armored or binary PGP key
  material
- WHEN Flutter requests PGP file inspection
- THEN the bridge reads and inspects the file without returning its key bytes to
  Flutter
- AND returns typed key metadata

#### Scenario: PGP import response identifies the imported key

- GIVEN inspected PGP material has canonical fingerprint `ABC`
- WHEN the corresponding text or file import succeeds
- THEN the response contains a key record for fingerprint `ABC`
- AND identifies whether public or private material was imported

#### Scenario: PGP passphrase failure is typed and sanitized

- GIVEN a protected private PGP key is submitted with an incorrect passphrase
- WHEN the bridge validates the import request
- THEN the response contains a passphrase validation failure kind
- AND contains neither the passphrase nor private key material

### Requirement: Bridge tooling config SHALL mark secret fields

Bridge tooling config SHALL identify secret fields so request/response payload
logging can avoid passwords, PGP passphrases, content, armored key text, and
private key fields.

Sources: `gui/bridge/bridge_config.toml`

#### Scenario: Secret fields are configured

- WHEN bridge tooling config is inspected
- THEN `secret_fields` includes `password`, `passphrase`, `content`,
  `armored_text`, and `private_key`
