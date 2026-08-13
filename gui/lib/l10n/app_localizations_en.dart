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
  String get managedStoreMergeLabel => 'Merge and overwrite';

  @override
  String get managedStoreMergeDescription =>
      'Overwrite matching files and keep files that exist only in the current copy.';

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
  String get pgpKeyDeletePartial =>
      'The protected private key was deleted, but its public listing could not be removed.';

  @override
  String keyDeleteFailed(String error) {
    return 'Key deletion failed: $error';
  }

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';
}
