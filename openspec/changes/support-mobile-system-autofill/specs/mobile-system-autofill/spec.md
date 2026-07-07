# mobile-system-autofill Specification

## Purpose

Define mobile operating-system password autofill behavior for Pars on iOS and
Android.

## Requirements

### Requirement: Mobile apps SHALL register as system password autofill providers

The Android app SHALL declare an AutofillService and an Android Credential
Manager password provider. The iOS app SHALL ship a Credential Provider
extension and maintain credential identities for indexed entries.

#### Scenario: Android system settings can list Pars

- WHEN the installed Android app is inspected by system autofill settings
- THEN Pars is available as a password autofill provider

#### Scenario: iOS Password AutoFill can list Pars

- WHEN the installed iOS app is inspected by Password AutoFill settings
- THEN Pars is available as a credential provider

### Requirement: Autofill index SHALL persist matching metadata only

Autofill index data SHALL include entry path, display name, username-like
fields, service identifiers, ranking metadata, selected store identity, and
freshness metadata. It SHALL NOT include plaintext passwords, raw decrypted
notes, TOTP values, or full decrypted entry content.

#### Scenario: Refreshed index omits passwords

- GIVEN a password entry decrypts to a password and username field
- WHEN the autofill index is refreshed
- THEN the index stores matching metadata and username
- AND it does not store the password

### Requirement: Autofill matching SHALL prefer explicit service identifiers

Autofill matching SHALL rank exact Android package identifiers above exact
domain identifiers, exact domain identifiers above path or display-name
fallbacks, and favorite or recent entries above otherwise equivalent entries.
Android package matches SHALL require an `android-package` or `android_package`
field. Web matches SHALL use normalized hosts from `url`, `website`, or
`service` fields.

#### Scenario: Website request matches URL host

- GIVEN an indexed entry has `url: https://example.com/login`
- WHEN an autofill request is made for `example.com`
- THEN that entry is returned as an exact website candidate

#### Scenario: Android package requires explicit package field

- GIVEN an indexed entry path contains `bank`
- AND it has no Android package field
- WHEN an autofill request is made for package `com.example.bank`
- THEN the entry is not returned as an exact package match

### Requirement: Autofill SHALL authenticate before returning credentials

System autofill providers SHALL require platform local authentication before
decrypting and returning a selected credential. Failed or canceled
authentication SHALL return no credential.

#### Scenario: Authentication cancellation does not fill

- GIVEN a user selects an autofill candidate
- WHEN platform authentication is canceled
- THEN Pars does not decrypt the entry
- AND no username or password is returned to the requesting app or website

### Requirement: Autofill SHALL decrypt credentials only on demand

Autofill providers SHALL decrypt only the selected entry after successful
authentication. Decryption SHALL use the selected mobile PGP backend and the
key-bound cached PGP passphrase when available. If no usable passphrase or key
is available for the selected entry, autofill SHALL fail closed.

#### Scenario: Selected entry is decrypted after authentication

- GIVEN a selected entry is indexed
- AND a usable key-bound PGP passphrase is available
- WHEN local authentication succeeds
- THEN Pars decrypts that entry
- AND returns its username and password

#### Scenario: Missing passphrase fails closed

- GIVEN a selected entry requires a passphrase-protected private key
- AND no usable cached passphrase is available
- WHEN autofill tries to resolve the selected entry
- THEN no plaintext credential is returned

### Requirement: Settings SHALL control autofill setup and data

Settings SHALL show system autofill setup status where available, provide
actions to open platform autofill setup screens, refresh autofill data, and
clear autofill data.

#### Scenario: Clearing autofill data removes shared candidates

- GIVEN autofill data exists for the selected store
- WHEN the user clears autofill data from Settings
- THEN shared autofill index data is removed
- AND iOS credential identities are removed when running on iOS

## Needs Verification

- Android Credential Manager provider behavior depends on Android version and
  device services.
- iOS Credential Provider extension availability requires matching app group
  and keychain entitlements in Apple developer provisioning.
- End-to-end autofill fill flows require simulator or physical-device checks.
