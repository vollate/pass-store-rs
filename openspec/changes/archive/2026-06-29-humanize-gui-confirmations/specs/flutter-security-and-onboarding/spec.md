## MODIFIED Requirements

### Requirement: Settings SHALL allow deleting existing PGP and SSH keys

Settings key management SHALL expose delete actions for existing PGP and SSH
keys. Before deleting key material, the UI SHALL require confirmation using a
human-readable key label displayed in the key list, SHALL show the exact phrase
the user must type before submission, and SHALL show machine identifiers such as
PGP fingerprints as read-only context rather than requiring them as typed
confirmation text. Deletion failures SHALL be shown to the user without
removing the key from the visible list.

Sources: `gui/lib/screens/settings/settings_screen.dart`,
`gui/test/mobile_gui_smoke_test.dart`,
`gui/lib/services/key_repository.dart`

#### Scenario: Delete PGP key from settings

- GIVEN Settings displays a PGP key with name `Alice` and fingerprint `ABC`
- WHEN the user chooses delete for that key
- AND confirms deletion by typing `Alice`
- THEN Settings calls the PGP key delete operation for fingerprint `ABC`
- AND refreshes the visible key list after deletion succeeds

#### Scenario: PGP key delete dialog does not require fingerprint input

- GIVEN a PGP key deletion confirmation dialog is open for fingerprint `ABC`
- WHEN the dialog renders its confirmation instructions
- THEN the required typed confirmation text is the key's human-readable name
- AND the fingerprint `ABC` is displayed only as key context

#### Scenario: Delete SSH key from settings

- GIVEN Settings displays an SSH key named `mobile-key`
- WHEN the user chooses delete for that key
- AND confirms deletion by typing `mobile-key`
- THEN Settings calls the SSH key delete operation for name `mobile-key`
- AND refreshes the visible key list after deletion succeeds

#### Scenario: Delete key cancellation preserves the key

- GIVEN a key deletion confirmation dialog is open
- WHEN the user cancels the dialog or enters incorrect confirmation text
- THEN Settings does not call the key delete operation
- AND the key remains visible
