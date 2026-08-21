// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get managedStoreConflictTitle => 'Store already exists';

  @override
  String managedStoreConflictDescription(String storeName) {
    return 'An app-managed copy named $storeName already exists. Choose how to import the selected folder.';
  }

  @override
  String get managedStoreReplaceLabel => 'Replace completely';

  @override
  String get managedStoreReplaceDescription =>
      'Replace the existing copy and remove files that are not in the selected folder.';

  @override
  String get noPasswordStoreConfigured => 'No password store is configured.';

  @override
  String get passwordStoreFolderNotFound => 'Password store folder not found.';

  @override
  String get chooseFolderAndImport => 'Choose folder and import';

  @override
  String get copyIntoAppStorage => 'Copy into app storage';

  @override
  String get copyIntoAppStorageDescription =>
      'Pars will copy the selected password store into app storage so every file remains accessible.';

  @override
  String get storeAvailable => 'Available';

  @override
  String get storeFolderNotFound => 'Folder not found';

  @override
  String get deleteAppCopy => 'Delete app copy';

  @override
  String passwordStoreKeyReference(String storeNames) {
    return 'Referenced by $storeNames (.gpg-id)';
  }

  @override
  String get localKeyMaterialMissing => 'Local key material is not installed';

  @override
  String get privateKeyMaterial => 'Private key';

  @override
  String get publicKeyMaterial => 'Public key';

  @override
  String get storeActionInProgress => 'Working…';

  @override
  String get storeImportCancelled => 'No folder was selected.';

  @override
  String get storeImportNoPasswords => 'No passwords were found.';

  @override
  String storeImportSucceeded(int passwordCount) {
    return 'Import complete: $passwordCount passwords.';
  }

  @override
  String get pgpPreparationInProgress => 'Protecting private key…';

  @override
  String get pgpPassphraseRequired => 'This private key needs its passphrase.';

  @override
  String get pgpPassphraseIncorrect =>
      'That passphrase did not unlock this key. Try again.';

  @override
  String get pgpUnsupportedProtection =>
      'This private key uses an unsupported protection format.';

  @override
  String get pgpReprotectionFailed =>
      'The private key could not be safely protected for local use.';

  @override
  String get deleteKeyAction => 'Delete key';

  @override
  String deleteKeyTitle(String keyType) {
    return 'Delete $keyType key';
  }

  @override
  String fingerprintValue(String fingerprint) {
    return 'Fingerprint: $fingerprint';
  }

  @override
  String deleteKeyDescription(String confirmation) {
    return 'This permanently removes local key material from this device, including the protected private key. Type $confirmation to delete it.';
  }

  @override
  String deleteKeyConfirmation(String confirmation) {
    return 'Type $confirmation to confirm';
  }

  @override
  String keyDeleted(String keyName) {
    return 'Deleted $keyName';
  }

  @override
  String keyDeleteFailed(String error) {
    return 'Key deletion failed: $error';
  }

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languageUnavailable => 'Language selection is unavailable.';

  @override
  String get languageSaveFailed => 'Could not save the language preference.';

  @override
  String get vaultTitle => 'Vault';

  @override
  String get manageTitle => 'Manage';

  @override
  String get retry => 'Retry';

  @override
  String get copy => 'Copy';

  @override
  String get close => 'Close';

  @override
  String get continueAction => 'Continue';

  @override
  String get save => 'Save';

  @override
  String get clear => 'Clear';

  @override
  String get setup => 'Setup';

  @override
  String get status => 'Status';

  @override
  String get create => 'Create';

  @override
  String get createPassword => 'Create password';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get importAction => 'Import';

  @override
  String get exportAction => 'Export';

  @override
  String get edit => 'Edit';

  @override
  String get move => 'Move';

  @override
  String get rename => 'Rename';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get select => 'Select';

  @override
  String get back => 'Back';

  @override
  String get details => 'Details';

  @override
  String get moreActions => 'More actions';

  @override
  String get searchVaultHint => 'Search by name or path';

  @override
  String get recentSection => 'Recent';

  @override
  String get favoritesSection => 'Favorites';

  @override
  String get searchResultsSection => 'Search results';

  @override
  String get browseSection => 'Browse';

  @override
  String browsePathSection(String path) {
    return 'Browse: $path';
  }

  @override
  String get noRecentEntries => 'No recent entries yet.';

  @override
  String get noFavoriteEntries => 'No favorite entries yet.';

  @override
  String get noSearchResults => 'No entries match this search.';

  @override
  String get noStoreEntries => 'No entries in this store.';

  @override
  String get noFolderEntries => 'No entries in this folder.';

  @override
  String get upOneLevel => 'Up';

  @override
  String get couldNotLoadVault => 'Could not load the vault.';

  @override
  String get gitClean => 'Clean';

  @override
  String get gitNeedPull => 'Pull needed';

  @override
  String get gitUncommitted => 'Uncommitted';

  @override
  String get gitSyncFailed => 'Sync failed';

  @override
  String copiedEntryPassword(String entryName) {
    return 'Copied $entryName password';
  }

  @override
  String get couldNotCopyPassword => 'Could not copy the password.';

  @override
  String get favoriteUpdateFailed => 'Could not update the favorite.';

  @override
  String entryCount(int count) {
    return '$count entries';
  }

  @override
  String get pgpPassphraseRequiredTitle => 'PGP passphrase required';

  @override
  String get pgpPassphraseLabel => 'PGP passphrase';

  @override
  String get unlockEntry => 'Unlock entry';

  @override
  String get decryptEntryFailedTitle => 'Could not decrypt entry';

  @override
  String get copyPassword => 'Copy password';

  @override
  String get reveal => 'Reveal';

  @override
  String get hide => 'Hide';

  @override
  String get favorite => 'Favorite';

  @override
  String get unfavorite => 'Unfavorite';

  @override
  String get openUrl => 'Open URL';

  @override
  String get qrCode => 'QR code';

  @override
  String get fields => 'Fields';

  @override
  String get rawNotes => 'Raw notes';

  @override
  String get passwordQrCode => 'Password QR code';

  @override
  String get closeQrCode => 'Close QR code';

  @override
  String copiedField(String fieldLabel) {
    return 'Copied $fieldLabel';
  }

  @override
  String get couldNotOpenUrl => 'Could not open the URL.';

  @override
  String get manageSubtitle =>
      'Maintain passwords in batches or one at a time.';

  @override
  String get generateAndSave => 'Generate and save';

  @override
  String get generateAndSaveDescription =>
      'Create one or many entries with generated passwords.';

  @override
  String get saveExistingPassword => 'Save existing password';

  @override
  String get saveExistingPasswordDescription =>
      'Manual entry for credentials you already have.';

  @override
  String get batchDelete => 'Batch delete';

  @override
  String get batchDeleteDescription =>
      'Preview full paths before removing selected entries.';

  @override
  String get regenerateSelected => 'Regenerate selected';

  @override
  String get regenerateSelectedDescription =>
      'Replace password lines while preserving fields and notes.';

  @override
  String get editEntries => 'Edit entries';

  @override
  String get editEntriesDescription =>
      'Update password lines and notes without changing the path.';

  @override
  String get moveEntry => 'Move entry';

  @override
  String get moveEntryDescription => 'Move one entry into another folder.';

  @override
  String get renameEntry => 'Rename entry';

  @override
  String get renameEntryDescription =>
      'Change one entry path with overwrite handling.';

  @override
  String get deleteEntry => 'Delete entry';

  @override
  String get deleteEntryDescription =>
      'Remove one entry after name confirmation.';

  @override
  String get noEntriesToManage => 'No entries to manage.';

  @override
  String get selectAtLeastOneEntry => 'Select at least one entry.';

  @override
  String get manageUnavailable => 'Manage operations are not available.';

  @override
  String get batchMove => 'Batch move';

  @override
  String get batchRename => 'Batch rename';

  @override
  String get destinationFolder => 'Destination folder';

  @override
  String get entryPath => 'Entry path';

  @override
  String get newEntryPath => 'New entry path';

  @override
  String get prefix => 'Prefix';

  @override
  String get suffix => 'Suffix';

  @override
  String get overwriteTarget => 'Overwrite if target exists';

  @override
  String get overwriteEntry => 'Overwrite if entry exists';

  @override
  String get moveSelected => 'Move selected';

  @override
  String get renameSelected => 'Rename selected';

  @override
  String get deleteSelected => 'Delete selected';

  @override
  String get regenerateBatch => 'Regenerate batch';

  @override
  String get noEntriesAvailable => 'No entries available';

  @override
  String get noEntriesToEdit => 'No entries to edit.';

  @override
  String get noSymbols => 'No symbols';

  @override
  String get confirmation => 'Confirmation';

  @override
  String get password => 'Password';

  @override
  String get commitAfterOperation => 'Commit after operation';

  @override
  String get saveGeneratedPassword => 'Save generated password';

  @override
  String get savePassword => 'Save password';

  @override
  String get saveEditedEntry => 'Save edited entry';

  @override
  String get replaceFirstLine => 'Replace first line';

  @override
  String get selectedPathPrefix => 'Selected';

  @override
  String get defaultPathPrefix => 'Default';

  @override
  String get changeAction => 'Change';

  @override
  String get chooseAction => 'Choose';

  @override
  String get noKeyRepository => 'No key repository available';

  @override
  String get noSshRepository => 'No SSH repository available';

  @override
  String get enterPassphrase => 'Enter a passphrase.';

  @override
  String get selectPrivatePgpKey => 'Select or import a private PGP key.';

  @override
  String get storeFolder => 'Store folder';

  @override
  String get remoteUrlField => 'Remote URL';

  @override
  String get commitMessageField => 'Commit message';

  @override
  String get remoteNameField => 'Remote name';

  @override
  String get gitOperationsUnavailable => 'Git operations are not available.';

  @override
  String get gitArgumentRequired => 'Enter at least one Git argument.';

  @override
  String get never => 'Never';

  @override
  String minutesShort(int count) {
    return '$count min';
  }

  @override
  String hoursShort(int count) {
    return '$count hour';
  }

  @override
  String get immediately => 'Immediately';

  @override
  String get untilAppExit => 'Until app exit';

  @override
  String importedKey(String keyName) {
    return 'Imported $keyName';
  }

  @override
  String importedKeyRememberFailed(String keyName) {
    return 'Imported $keyName, but remembering the passphrase failed.';
  }

  @override
  String get deleteLocalStore => 'Delete local store';

  @override
  String pathValue(String path) {
    return 'Path: $path';
  }

  @override
  String typeToConfirm(String value) {
    return 'Type $value to confirm';
  }

  @override
  String get entryField => 'Entry';

  @override
  String get batchSelection => 'Batch selection';

  @override
  String get securitySection => 'Security';

  @override
  String get securityPrivacySection => 'Security and privacy';

  @override
  String get vaultSyncSection => 'Vault and sync';

  @override
  String get autofillSection => 'Autofill';

  @override
  String get advancedSupportSection => 'Advanced and support';

  @override
  String get platformSection => 'Platform';

  @override
  String get gestureBiometricsTitle => 'Gesture lock and biometrics';

  @override
  String get lockOnResumeState => 'Lock on app resume';

  @override
  String get gestureConfiguredState => 'Gesture unlock configured';

  @override
  String get pgpSessionTimeoutTitle => 'PGP session timeout';

  @override
  String get keychainPassphraseTitle => 'KMS / Keychain passphrase';

  @override
  String get pgpPassphraseCachedState => 'PGP passphrase cached';

  @override
  String get optionalPassphraseCacheState =>
      'Optional encrypted passphrase cache';

  @override
  String get sshKeysTitle => 'SSH keys';

  @override
  String get githubAccessKeysDescription => 'GitHub access keys';

  @override
  String get gitSyncTitle => 'Git sync and remotes';

  @override
  String get gitSyncDescription => 'Pull, push, status, remotes';

  @override
  String get advancedGitArgsTitle => 'Advanced Git args';

  @override
  String get advancedGitArgsDescription => 'Arguments after git only';

  @override
  String get systemAutofillTitle => 'System Autofill';

  @override
  String get runtimeDiagnosticsTitle => 'Runtime diagnostics';

  @override
  String get runtimeDiagnosticsDescription =>
      'Bridge, core, crypto, Git, key storage';

  @override
  String get bridgeLoadedLabel => 'Bridge loaded';

  @override
  String get coreVersionLabel => 'Core version';

  @override
  String get nativeLibraryLabel => 'Native library';

  @override
  String get pgpBackendLabel => 'PGP backend';

  @override
  String get gitBackendLabel => 'Git backend';

  @override
  String get keyStorageBackendLabel => 'Key storage backend';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get replaceCachedPassphrase => 'Replace cached passphrase';

  @override
  String get noCachedPassphrase => 'No PGP passphrase is cached.';

  @override
  String cachedForKey(String keyName) {
    return 'Cached for $keyName';
  }

  @override
  String get updatePasswordStore => 'Update password store';

  @override
  String get featureUnavailableDescription =>
      'This repository does not provide the operations required for this feature. Use a bridge-backed repository to enable it.';

  @override
  String get changeGesture => 'Change gesture';

  @override
  String get requireUnlockOnResume => 'Require unlock on app resume';

  @override
  String get gestureFallbackDescription => 'Gesture unlock is used as fallback';

  @override
  String get biometricUnlock => 'Biometric unlock';

  @override
  String get enabledOnDevice => 'Enabled on this device';

  @override
  String get availableOnDevice => 'Available on this device';

  @override
  String get unavailableOnDevice => 'Unavailable on this device';

  @override
  String get gestureLock => 'Gesture lock';

  @override
  String get passwordStore => 'Password store';

  @override
  String get pgpKey => 'PGP key';

  @override
  String get sshKey => 'SSH key';

  @override
  String get autoLockTimeout => 'Auto-lock timeout';

  @override
  String get resetOnboarding => 'Reset onboarding';

  @override
  String get drawConfirmGesture =>
      'Draw and confirm a new local unlock gesture.';

  @override
  String get storePgpPassphrase => 'Store PGP passphrase';

  @override
  String get savedInSecureStorage =>
      'Saved in the platform secure storage provider';

  @override
  String get noPrivatePgpKeys => 'No private PGP keys';

  @override
  String get createPrivatePgpKeyFirst =>
      'Import or create a private PGP key before saving a passphrase.';

  @override
  String get rebuildPaths => 'Rebuild paths';

  @override
  String get readUrlFields => 'Read URL fields';

  @override
  String get clearUrlAliases => 'Clear URL aliases';

  @override
  String get clearAll => 'Clear all';

  @override
  String get readEncryptedUrlFieldsTitle => 'Read encrypted URL fields?';

  @override
  String readEncryptedUrlFieldsDescription(int count) {
    return 'This optional action decrypts all $count selected entries once and stores only normalized website aliases. Path-based Autofill does not require it.';
  }

  @override
  String get readSelectedEntries => 'Read selected entries';

  @override
  String get autofillRebuiltSuccess =>
      'Path-based Autofill data rebuilt without decrypting entries.';

  @override
  String get autofillAliasesCleared => 'Encrypted website aliases cleared.';

  @override
  String get autofillDataCleared => 'Autofill data cleared.';

  @override
  String get clearAutofillConfirmation =>
      'Remove all shared Autofill candidates for this store? This does not delete password entries.';

  @override
  String get openSystemPasswordSettings => 'Open system password settings.';

  @override
  String get autofillAliasesUpdated => 'Encrypted website aliases updated.';

  @override
  String get noEntriesToEnrich => 'There are no password entries to enrich.';

  @override
  String get autofillBridgeUnavailable => 'Autofill bridge unavailable';

  @override
  String get autofillNotRefreshed => 'Not refreshed';

  @override
  String get autofillReady => 'Ready';

  @override
  String get autofillNeedsRebuild => 'Needs rebuild';

  @override
  String get autofillBusy => 'Working…';

  @override
  String get autofillDisabled => 'Disabled';

  @override
  String get autofillUnavailableState => 'Unavailable';

  @override
  String autofillIndexedEntries(int count) {
    return '$count entries indexed';
  }

  @override
  String get unavailable => 'Unavailable';

  @override
  String get createOrImportKey => 'Create or import a key.';

  @override
  String get noPgpKeys => 'No PGP keys';

  @override
  String get noSshKeys => 'No SSH keys';

  @override
  String keyActionsTooltip(String keyType, String keyName) {
    return 'Actions for $keyType key $keyName';
  }

  @override
  String get exportPublic => 'Export public';

  @override
  String get exportPrivate => 'Export private';

  @override
  String get addToGpgId => 'Add to .gpg-id';

  @override
  String get importPgpKey => 'Import PGP key';

  @override
  String get importSshKey => 'Import SSH key';

  @override
  String get textSource => 'Text';

  @override
  String get fileSource => 'File';

  @override
  String get importSshKeyFile => 'Import SSH key file';

  @override
  String get nameField => 'Name';

  @override
  String get keyTextField => 'Key text';

  @override
  String get keyFileField => 'Key file';

  @override
  String get pastePgpKeyHelp => 'Paste a PGP public or private key.';

  @override
  String get pgpPassphraseUnlockHelp => 'Required to unlock this private key.';

  @override
  String get unlockAndImport => 'Unlock and import';

  @override
  String get exportPrivateKey => 'Export private key';

  @override
  String privateExportSensitive(String confirmation) {
    return 'Private key export is sensitive. Type $confirmation to export.';
  }

  @override
  String get exportedKey => 'Exported key';

  @override
  String get createImportCloneStore => 'Create, import, or clone a store.';

  @override
  String get removeFromApp => 'Remove from app';

  @override
  String get cloneAction => 'Clone';

  @override
  String get pull => 'Pull';

  @override
  String get push => 'Push';

  @override
  String get recoverPull => 'Recover pull';

  @override
  String get pushAfterCommit => 'Push after commit';

  @override
  String get commit => 'Commit';

  @override
  String get listRemotes => 'List remotes';

  @override
  String get addRemote => 'Add remote';

  @override
  String get updateRemote => 'Update remote';

  @override
  String get removeRemote => 'Remove remote';

  @override
  String get deleteLocalRepo => 'Delete local repo';

  @override
  String get gitArgsOnlyDescription =>
      'Only enter arguments after git. Shell syntax is not accepted.';

  @override
  String get runSelectedCommand => 'Run selected command';

  @override
  String exitCodeValue(String value) {
    return 'Exit: $value';
  }

  @override
  String get standardOutput => 'stdout';

  @override
  String get standardError => 'stderr';

  @override
  String get success => 'Success';

  @override
  String get failed => 'Failed';

  @override
  String get operationFailed => 'Operation failed. Try again or open Details.';

  @override
  String get actionSaved => 'Saved';

  @override
  String get actionEdited => 'Edited';

  @override
  String get actionDeleted => 'Deleted';

  @override
  String get actionMoved => 'Moved';

  @override
  String get actionRenamed => 'Renamed';

  @override
  String get actionRegenerated => 'Regenerated';

  @override
  String get actionUpdated => 'Updated';

  @override
  String get entryOverwroteExisting => ' (overwrote existing)';

  @override
  String get entryCommitted => ' and committed';

  @override
  String entryOperationSummary(
    String action,
    String path,
    String overwrite,
    String commit,
  ) {
    return '$action $path$overwrite$commit';
  }

  @override
  String batchOperationSummary(String action, int count, String commit) {
    return '$action $count entries$commit';
  }

  @override
  String batchFailureSuffix(int count) {
    return '; $count failed';
  }

  @override
  String postMutationCommitFailed(String mutationSummary) {
    return '$mutationSummary, but the optional Git commit failed. The vault mutation was not rolled back.';
  }

  @override
  String get diagnosticDetails => 'Diagnostic details';

  @override
  String get lockNow => 'Lock now';

  @override
  String get unlockPars => 'Unlock Pars';

  @override
  String get drawGestureToUnlock =>
      'Draw your gesture to open the local app session.';

  @override
  String get unlockWithBiometrics => 'Unlock with biometrics';

  @override
  String get gestureDidNotMatch => 'Gesture did not match';

  @override
  String get biometricUnlockFailed => 'Biometric unlock failed';

  @override
  String get resetGesture => 'Reset gesture';

  @override
  String get drawSameGesture => 'Draw the same gesture again.';

  @override
  String get drawAtLeastFourDots => 'Draw at least 4 dots.';

  @override
  String get startNewGesture => 'Start again with a new gesture.';

  @override
  String get useAtLeastFourDots => 'Use at least 4 dots.';

  @override
  String get gestureCapturedConfirm =>
      'Gesture captured. Confirm it once more.';

  @override
  String get gesturesDidNotMatch => 'Gestures did not match. Start again.';

  @override
  String get gestureConfirmed => 'Gesture confirmed.';

  @override
  String get gesturePatternInput => 'Gesture pattern input';

  @override
  String gestureDot(int number) {
    return 'Gesture dot $number';
  }

  @override
  String get clearGesture => 'Clear gesture';

  @override
  String get submitGesture => 'Submit gesture';

  @override
  String get rememberInKeychain => 'Remember in Keychain/KMS';

  @override
  String get rememberPassphraseDescription =>
      'Off by default. The passphrase stays in memory for this session unless you explicitly remember it.';

  @override
  String get inspectingKeyMaterial => 'Inspecting key material…';

  @override
  String get setGestureLock => 'Set gesture lock';

  @override
  String get enableBiometricUnlock => 'Enable biometric unlock';

  @override
  String get choosePgpKey => 'Choose PGP key';

  @override
  String get setupSshGithub => 'Set up SSH for GitHub';

  @override
  String get setupPasswordStore => 'Set up password store';

  @override
  String get reviewSetup => 'Review setup';

  @override
  String get gestureStepSubtitle =>
      'Use a 9-dot gesture as the local Pars unlock method.';

  @override
  String get biometricsStepSubtitle =>
      'Biometrics are optional and keep the gesture as fallback.';

  @override
  String get pgpStepSubtitle =>
      'Select, create, or import the key used to encrypt passwords.';

  @override
  String get sshStepSubtitle =>
      'SSH is optional and enables authenticated Git operations.';

  @override
  String get storeStepSubtitle =>
      'Choose how Pars should open or create your password store.';

  @override
  String get reviewStepSubtitle =>
      'Confirm required setup before opening the vault.';

  @override
  String get githubSshSettings => 'GitHub SSH settings';

  @override
  String onboardingProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get optional => 'Optional';

  @override
  String get gestureStep => 'Gesture';

  @override
  String get biometricsStep => 'Biometrics';

  @override
  String get pgpStep => 'PGP';

  @override
  String get sshStep => 'SSH';

  @override
  String get storeStep => 'Store';

  @override
  String get reviewStep => 'Review';

  @override
  String get skipBiometrics => 'Skip biometrics';

  @override
  String get finishSetup => 'Finish setup';

  @override
  String get noPgpKeysFound => 'No PGP keys found';

  @override
  String get createOrImportEncryptionKey =>
      'Create or import a key to encrypt entries.';

  @override
  String get usePgpKey => 'Use PGP key';

  @override
  String get createPgpKey => 'Create PGP key';

  @override
  String get createSshKey => 'Create SSH key';

  @override
  String get emailField => 'Email';

  @override
  String get passphraseField => 'Passphrase';

  @override
  String get noSshKeysConfigured => 'No SSH keys configured';

  @override
  String get sshOptionalDescription =>
      'SSH is optional and can be added later.';

  @override
  String get generateSshKey => 'Generate SSH key';

  @override
  String get githubSettings => 'GitHub settings';

  @override
  String get skipSsh => 'Skip SSH';

  @override
  String get createLocalStore => 'Create local store';

  @override
  String get importLocalStore => 'Import local store';

  @override
  String get cloneGitStore => 'Clone Git store';

  @override
  String get addSshBeforeClone => 'Add an SSH key before cloning a Git store.';

  @override
  String get noStoreRepository => 'No store repository available';

  @override
  String get configured => 'Configured';

  @override
  String get required => 'Required';

  @override
  String get enabled => 'Enabled';

  @override
  String get skipped => 'Skipped';

  @override
  String get notFound => 'Not found';

  @override
  String get gitMetadataNotFoundTitle => 'Git metadata not found';

  @override
  String get gitMetadataNotFoundMessage =>
      'The folder may be local-only, or Android may have hidden its .git data. Initializing creates new history and cannot recover existing history.';

  @override
  String get initializeGit => 'Initialize Git';

  @override
  String get continueWithoutGit => 'Continue without Git';

  @override
  String keyCount(int count) {
    return '$count key(s)';
  }

  @override
  String get storeFirstSetupSubtitle =>
      'Import or clone your password store. Create a new store only if you do not have one yet.';

  @override
  String get createStoreRecipientSubtitle =>
      'Choose a private PGP key only for the new store you are creating.';

  @override
  String get contextualRepairSubtitle =>
      'Repair only what this password store requires.';

  @override
  String get repairPasswordStore => 'Repair password store';

  @override
  String get createStoreNeedsPgpKey =>
      'Creating a new store requires choosing or importing a private PGP key first.';

  @override
  String get gitOptionalForLocalStore =>
      'Git is optional. The password store remains usable without it.';

  @override
  String get sshKeyRequiredForRemote => 'SSH key required for this remote';

  @override
  String get sshRequiredForThisClone =>
      'This SSH remote needs a key. HTTPS clones do not.';

  @override
  String get missingGpgIdTitle => 'Encryption recipients are missing';

  @override
  String get missingGpgIdMessage =>
      'Choose a private PGP key to create this store\'s missing .gpg-id. Existing recipient files are never replaced here.';

  @override
  String get requiredPgpKeyMissingTitle => 'Required private PGP key missing';

  @override
  String requiredPgpKeyMissingMessage(String recipients) {
    return 'Import private material matching one of these recipients: $recipients';
  }

  @override
  String get requiredPrivatePgpKey => 'A matching private PGP key is required.';

  @override
  String get pgpKeyDoesNotMatchStore =>
      'This private key does not match the password store recipients.';

  @override
  String get invalidGitMetadataTitle => 'Git metadata is invalid';

  @override
  String get invalidGitMetadataMessage =>
      'This password store contains unusable Git metadata. Disconnect it, then import or clone a valid copy.';

  @override
  String get disconnectStore => 'Disconnect password store';

  @override
  String get gitDisabledState => 'Git disabled · local password store';

  @override
  String get gitLocalState => 'Local Git · no remote';

  @override
  String get gitRemoteState => 'Git remote configured';

  @override
  String get storeIssues => 'Repair needed';

  @override
  String get sshKeysGitOnlyDescription =>
      'SSH keys are used only for SSH Git remotes. HTTPS and local-only stores do not require them.';

  @override
  String get storeRemovalInProgressTitle => 'Removing password store…';

  @override
  String get storeRemovalInProgressDescription =>
      'Pars is clearing local session and Autofill data before changing the configured store.';
}
