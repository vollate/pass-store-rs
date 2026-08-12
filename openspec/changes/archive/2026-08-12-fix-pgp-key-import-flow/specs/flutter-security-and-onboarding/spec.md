## ADDED Requirements

### Requirement: Settings and Onboarding SHALL share a source-independent PGP import flow

Settings and Onboarding SHALL offer the same PGP import flow with Text and File
as source choices. The flow SHALL use bridge inspection to determine public or
private key kind and passphrase protection, SHALL use a native file picker for
the File source, and SHALL complete using the canonical key record returned by
the bridge. A protected private-key import SHALL not complete until its
passphrase is validated. Successful validation SHALL start an in-memory PGP
session bound to the imported fingerprint and SHALL persist the passphrase only
when the user explicitly opts into Keychain/KMS storage.

#### Scenario: Both GUI surfaces offer Text and File

- **WHEN** the user opens PGP import from Settings or Onboarding
- **THEN** the import flow offers Text and File source choices
- **AND** selecting File opens the native key-file picker inside the import flow

#### Scenario: Source does not determine public or private kind

- **GIVEN** supported public or private PGP material is supplied from Text or
  File
- **WHEN** the GUI inspects the selected material
- **THEN** it follows the public/private kind returned by the bridge
- **AND** it does not assume every file is a private key

#### Scenario: Protected private import requests and validates passphrase

- **GIVEN** inspection identifies passphrase-protected private PGP material
- **WHEN** the user submits the selected text or file
- **THEN** the flow presents an obscured PGP passphrase field
- **AND** import completion remains blocked until validation succeeds

#### Scenario: Incorrect passphrase stays in the import flow

- **GIVEN** a protected private-key passphrase step is visible
- **WHEN** the user enters an incorrect passphrase
- **THEN** the flow shows a sanitized inline validation error
- **AND** it does not advance Onboarding or report Settings import success
- **AND** it does not start or cache a PGP session

#### Scenario: Correct passphrase starts a key-bound session

- **GIVEN** protected private key material imports as fingerprint `ABC`
- **WHEN** the user enters the correct passphrase
- **THEN** the security repository starts an in-memory PGP session for
  fingerprint `ABC`
- **AND** Onboarding selects `ABC` before advancing or Settings refreshes the
  visible key list

#### Scenario: Remembering an imported passphrase is explicit

- **GIVEN** the protected private-key passphrase step is visible
- **WHEN** the user successfully imports the key without selecting Remember in
  Keychain/KMS
- **THEN** the passphrase is not written to durable storage
- **WHEN** the user explicitly selects Remember in Keychain/KMS
- **THEN** the saved passphrase cache is associated with the imported
  fingerprint

#### Scenario: Public and unprotected private imports skip passphrase UI

- **GIVEN** inspection identifies a public key or an unprotected private key
- **WHEN** import succeeds
- **THEN** the flow does not request or persist a PGP passphrase
- **AND** it completes with the returned canonical key record

#### Scenario: Secure-storage failure does not expose the passphrase

- **GIVEN** a protected private key was imported and its in-memory session
  started
- **WHEN** optional Keychain/KMS persistence fails
- **THEN** the GUI reports that remembering the passphrase failed without
  rolling back the imported key
- **AND** clears the passphrase field
- **AND** no error or notification contains the passphrase
