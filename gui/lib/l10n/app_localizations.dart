import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @managedStoreConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Store already exists'**
  String get managedStoreConflictTitle;

  /// No description provided for @managedStoreConflictDescription.
  ///
  /// In en, this message translates to:
  /// **'An app-managed copy named {storeName} already exists. Choose how to import the selected folder.'**
  String managedStoreConflictDescription(String storeName);

  /// No description provided for @managedStoreReplaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Replace completely'**
  String get managedStoreReplaceLabel;

  /// No description provided for @managedStoreReplaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Replace the existing copy and remove files that are not in the selected folder.'**
  String get managedStoreReplaceDescription;

  /// No description provided for @noPasswordStoreConfigured.
  ///
  /// In en, this message translates to:
  /// **'No password store is configured.'**
  String get noPasswordStoreConfigured;

  /// No description provided for @passwordStoreFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Password store folder not found.'**
  String get passwordStoreFolderNotFound;

  /// No description provided for @chooseFolderAndImport.
  ///
  /// In en, this message translates to:
  /// **'Choose folder and import'**
  String get chooseFolderAndImport;

  /// No description provided for @copyIntoAppStorage.
  ///
  /// In en, this message translates to:
  /// **'Copy into app storage'**
  String get copyIntoAppStorage;

  /// No description provided for @copyIntoAppStorageDescription.
  ///
  /// In en, this message translates to:
  /// **'Pars will copy the selected password store into app storage so every file remains accessible.'**
  String get copyIntoAppStorageDescription;

  /// No description provided for @storeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get storeAvailable;

  /// No description provided for @storeFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Folder not found'**
  String get storeFolderNotFound;

  /// No description provided for @deleteAppCopy.
  ///
  /// In en, this message translates to:
  /// **'Delete app copy'**
  String get deleteAppCopy;

  /// No description provided for @passwordStoreKeyReference.
  ///
  /// In en, this message translates to:
  /// **'Referenced by {storeNames} (.gpg-id)'**
  String passwordStoreKeyReference(String storeNames);

  /// No description provided for @localKeyMaterialMissing.
  ///
  /// In en, this message translates to:
  /// **'Local key material is not installed'**
  String get localKeyMaterialMissing;

  /// No description provided for @privateKeyMaterial.
  ///
  /// In en, this message translates to:
  /// **'Private key'**
  String get privateKeyMaterial;

  /// No description provided for @publicKeyMaterial.
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get publicKeyMaterial;

  /// No description provided for @storeActionInProgress.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get storeActionInProgress;

  /// No description provided for @storeImportCancelled.
  ///
  /// In en, this message translates to:
  /// **'No folder was selected.'**
  String get storeImportCancelled;

  /// No description provided for @storeImportNoPasswords.
  ///
  /// In en, this message translates to:
  /// **'No passwords were found.'**
  String get storeImportNoPasswords;

  /// No description provided for @storeImportSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Import complete: {passwordCount} passwords.'**
  String storeImportSucceeded(int passwordCount);

  /// No description provided for @pgpPreparationInProgress.
  ///
  /// In en, this message translates to:
  /// **'Protecting private key…'**
  String get pgpPreparationInProgress;

  /// No description provided for @pgpPassphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'This private key needs its passphrase.'**
  String get pgpPassphraseRequired;

  /// No description provided for @pgpPassphraseIncorrect.
  ///
  /// In en, this message translates to:
  /// **'That passphrase did not unlock this key. Try again.'**
  String get pgpPassphraseIncorrect;

  /// No description provided for @pgpUnsupportedProtection.
  ///
  /// In en, this message translates to:
  /// **'This private key uses an unsupported protection format.'**
  String get pgpUnsupportedProtection;

  /// No description provided for @pgpReprotectionFailed.
  ///
  /// In en, this message translates to:
  /// **'The private key could not be safely protected for local use.'**
  String get pgpReprotectionFailed;

  /// No description provided for @deleteKeyAction.
  ///
  /// In en, this message translates to:
  /// **'Delete key'**
  String get deleteKeyAction;

  /// No description provided for @deleteKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {keyType} key'**
  String deleteKeyTitle(String keyType);

  /// No description provided for @fingerprintValue.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint: {fingerprint}'**
  String fingerprintValue(String fingerprint);

  /// No description provided for @deleteKeyDescription.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes local key material from this device, including the protected private key. Type {confirmation} to delete it.'**
  String deleteKeyDescription(String confirmation);

  /// No description provided for @deleteKeyConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Type {confirmation} to confirm'**
  String deleteKeyConfirmation(String confirmation);

  /// No description provided for @keyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {keyName}'**
  String keyDeleted(String keyName);

  /// No description provided for @keyDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Key deletion failed: {error}'**
  String keyDeleteFailed(String error);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @languageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Language selection is unavailable.'**
  String get languageUnavailable;

  /// No description provided for @languageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the language preference.'**
  String get languageSaveFailed;

  /// No description provided for @vaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vaultTitle;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @setup.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get setup;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createPassword.
  ///
  /// In en, this message translates to:
  /// **'Create password'**
  String get createPassword;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @exportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @searchVaultHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or path'**
  String get searchVaultHint;

  /// No description provided for @favoritesSection.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesSection;

  /// No description provided for @searchResultsSection.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResultsSection;

  /// No description provided for @browseSection.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browseSection;

  /// No description provided for @browsePathSection.
  ///
  /// In en, this message translates to:
  /// **'Browse: {path}'**
  String browsePathSection(String path);

  /// No description provided for @noFavoriteEntries.
  ///
  /// In en, this message translates to:
  /// **'No favorite entries yet.'**
  String get noFavoriteEntries;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No entries match this search.'**
  String get noSearchResults;

  /// No description provided for @noStoreEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries in this store.'**
  String get noStoreEntries;

  /// No description provided for @noFolderEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries in this folder.'**
  String get noFolderEntries;

  /// No description provided for @upOneLevel.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get upOneLevel;

  /// No description provided for @couldNotLoadVault.
  ///
  /// In en, this message translates to:
  /// **'Could not load the vault.'**
  String get couldNotLoadVault;

  /// No description provided for @gitClean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get gitClean;

  /// No description provided for @gitNeedPull.
  ///
  /// In en, this message translates to:
  /// **'Pull needed'**
  String get gitNeedPull;

  /// No description provided for @gitUncommitted.
  ///
  /// In en, this message translates to:
  /// **'Uncommitted'**
  String get gitUncommitted;

  /// No description provided for @gitSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get gitSyncFailed;

  /// No description provided for @copiedEntryPassword.
  ///
  /// In en, this message translates to:
  /// **'Copied {entryName} password'**
  String copiedEntryPassword(String entryName);

  /// No description provided for @couldNotCopyPassword.
  ///
  /// In en, this message translates to:
  /// **'Could not copy the password.'**
  String get couldNotCopyPassword;

  /// No description provided for @favoriteUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the favorite.'**
  String get favoriteUpdateFailed;

  /// No description provided for @entryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String entryCount(int count);

  /// No description provided for @pgpPassphraseRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'PGP passphrase required'**
  String get pgpPassphraseRequiredTitle;

  /// No description provided for @pgpPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'PGP passphrase'**
  String get pgpPassphraseLabel;

  /// No description provided for @unlockEntry.
  ///
  /// In en, this message translates to:
  /// **'Unlock entry'**
  String get unlockEntry;

  /// No description provided for @decryptEntryFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not decrypt entry'**
  String get decryptEntryFailedTitle;

  /// No description provided for @copyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get copyPassword;

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get unfavorite;

  /// No description provided for @openUrl.
  ///
  /// In en, this message translates to:
  /// **'Open URL'**
  String get openUrl;

  /// No description provided for @qrCode.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get qrCode;

  /// No description provided for @fields.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get fields;

  /// No description provided for @rawNotes.
  ///
  /// In en, this message translates to:
  /// **'Raw notes'**
  String get rawNotes;

  /// No description provided for @passwordQrCode.
  ///
  /// In en, this message translates to:
  /// **'Password QR code'**
  String get passwordQrCode;

  /// No description provided for @closeQrCode.
  ///
  /// In en, this message translates to:
  /// **'Close QR code'**
  String get closeQrCode;

  /// No description provided for @copiedField.
  ///
  /// In en, this message translates to:
  /// **'Copied {fieldLabel}'**
  String copiedField(String fieldLabel);

  /// No description provided for @couldNotOpenUrl.
  ///
  /// In en, this message translates to:
  /// **'Could not open the URL.'**
  String get couldNotOpenUrl;

  /// No description provided for @generateAndSave.
  ///
  /// In en, this message translates to:
  /// **'Generate and save'**
  String get generateAndSave;

  /// No description provided for @generateAndSaveDescription.
  ///
  /// In en, this message translates to:
  /// **'Create one or many entries with generated passwords.'**
  String get generateAndSaveDescription;

  /// No description provided for @saveExistingPassword.
  ///
  /// In en, this message translates to:
  /// **'Save existing password'**
  String get saveExistingPassword;

  /// No description provided for @saveExistingPasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Manual entry for credentials you already have.'**
  String get saveExistingPasswordDescription;

  /// No description provided for @batchDelete.
  ///
  /// In en, this message translates to:
  /// **'Batch delete'**
  String get batchDelete;

  /// No description provided for @batchDeleteDescription.
  ///
  /// In en, this message translates to:
  /// **'Preview full paths before removing selected entries.'**
  String get batchDeleteDescription;

  /// No description provided for @regenerateSelected.
  ///
  /// In en, this message translates to:
  /// **'Regenerate selected'**
  String get regenerateSelected;

  /// No description provided for @regenerateSelectedDescription.
  ///
  /// In en, this message translates to:
  /// **'Replace password lines while preserving fields and notes.'**
  String get regenerateSelectedDescription;

  /// No description provided for @editEntries.
  ///
  /// In en, this message translates to:
  /// **'Edit entries'**
  String get editEntries;

  /// No description provided for @editEntriesDescription.
  ///
  /// In en, this message translates to:
  /// **'Update password lines and notes without changing the path.'**
  String get editEntriesDescription;

  /// No description provided for @moveEntry.
  ///
  /// In en, this message translates to:
  /// **'Move entry'**
  String get moveEntry;

  /// No description provided for @moveEntryDescription.
  ///
  /// In en, this message translates to:
  /// **'Move one entry into another folder.'**
  String get moveEntryDescription;

  /// No description provided for @renameEntry.
  ///
  /// In en, this message translates to:
  /// **'Rename entry'**
  String get renameEntry;

  /// No description provided for @renameEntryDescription.
  ///
  /// In en, this message translates to:
  /// **'Change one entry path with overwrite handling.'**
  String get renameEntryDescription;

  /// No description provided for @deleteEntry.
  ///
  /// In en, this message translates to:
  /// **'Delete entry'**
  String get deleteEntry;

  /// No description provided for @deleteEntryDescription.
  ///
  /// In en, this message translates to:
  /// **'Remove one entry after name confirmation.'**
  String get deleteEntryDescription;

  /// No description provided for @selectAtLeastOneEntry.
  ///
  /// In en, this message translates to:
  /// **'Select at least one entry.'**
  String get selectAtLeastOneEntry;

  /// No description provided for @manageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Manage operations are not available.'**
  String get manageUnavailable;

  /// No description provided for @batchMove.
  ///
  /// In en, this message translates to:
  /// **'Batch move'**
  String get batchMove;

  /// No description provided for @batchRename.
  ///
  /// In en, this message translates to:
  /// **'Batch rename'**
  String get batchRename;

  /// No description provided for @destinationFolder.
  ///
  /// In en, this message translates to:
  /// **'Destination folder'**
  String get destinationFolder;

  /// No description provided for @entryPath.
  ///
  /// In en, this message translates to:
  /// **'Entry path'**
  String get entryPath;

  /// No description provided for @newEntryPath.
  ///
  /// In en, this message translates to:
  /// **'New entry path'**
  String get newEntryPath;

  /// No description provided for @prefix.
  ///
  /// In en, this message translates to:
  /// **'Prefix'**
  String get prefix;

  /// No description provided for @suffix.
  ///
  /// In en, this message translates to:
  /// **'Suffix'**
  String get suffix;

  /// No description provided for @overwriteTarget.
  ///
  /// In en, this message translates to:
  /// **'Overwrite if target exists'**
  String get overwriteTarget;

  /// No description provided for @overwriteEntry.
  ///
  /// In en, this message translates to:
  /// **'Overwrite if entry exists'**
  String get overwriteEntry;

  /// No description provided for @moveSelected.
  ///
  /// In en, this message translates to:
  /// **'Move selected'**
  String get moveSelected;

  /// No description provided for @renameSelected.
  ///
  /// In en, this message translates to:
  /// **'Rename selected'**
  String get renameSelected;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get deleteSelected;

  /// No description provided for @regenerateBatch.
  ///
  /// In en, this message translates to:
  /// **'Regenerate batch'**
  String get regenerateBatch;

  /// No description provided for @noEntriesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No entries available'**
  String get noEntriesAvailable;

  /// No description provided for @noSymbols.
  ///
  /// In en, this message translates to:
  /// **'No symbols'**
  String get noSymbols;

  /// No description provided for @confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmation;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @commitAfterOperation.
  ///
  /// In en, this message translates to:
  /// **'Commit after operation'**
  String get commitAfterOperation;

  /// No description provided for @saveGeneratedPassword.
  ///
  /// In en, this message translates to:
  /// **'Save generated password'**
  String get saveGeneratedPassword;

  /// No description provided for @savePassword.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get savePassword;

  /// No description provided for @saveEditedEntry.
  ///
  /// In en, this message translates to:
  /// **'Save edited entry'**
  String get saveEditedEntry;

  /// No description provided for @replaceFirstLine.
  ///
  /// In en, this message translates to:
  /// **'Replace first line'**
  String get replaceFirstLine;

  /// No description provided for @selectedPathPrefix.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selectedPathPrefix;

  /// No description provided for @defaultPathPrefix.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultPathPrefix;

  /// No description provided for @changeAction.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAction;

  /// No description provided for @chooseAction.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get chooseAction;

  /// No description provided for @noKeyRepository.
  ///
  /// In en, this message translates to:
  /// **'No key repository available'**
  String get noKeyRepository;

  /// No description provided for @noSshRepository.
  ///
  /// In en, this message translates to:
  /// **'No SSH repository available'**
  String get noSshRepository;

  /// No description provided for @enterPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Enter a passphrase.'**
  String get enterPassphrase;

  /// No description provided for @selectPrivatePgpKey.
  ///
  /// In en, this message translates to:
  /// **'Select or import a private PGP key.'**
  String get selectPrivatePgpKey;

  /// No description provided for @storeFolder.
  ///
  /// In en, this message translates to:
  /// **'Store folder'**
  String get storeFolder;

  /// No description provided for @remoteUrlField.
  ///
  /// In en, this message translates to:
  /// **'Remote URL'**
  String get remoteUrlField;

  /// No description provided for @commitMessageField.
  ///
  /// In en, this message translates to:
  /// **'Commit message'**
  String get commitMessageField;

  /// No description provided for @remoteNameField.
  ///
  /// In en, this message translates to:
  /// **'Remote name'**
  String get remoteNameField;

  /// No description provided for @gitOperationsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Git operations are not available.'**
  String get gitOperationsUnavailable;

  /// No description provided for @gitArgumentRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one Git argument.'**
  String get gitArgumentRequired;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesShort(int count);

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'{count} hour'**
  String hoursShort(int count);

  /// No description provided for @immediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// No description provided for @untilAppExit.
  ///
  /// In en, this message translates to:
  /// **'Until app exit'**
  String get untilAppExit;

  /// No description provided for @importedKey.
  ///
  /// In en, this message translates to:
  /// **'Imported {keyName}'**
  String importedKey(String keyName);

  /// No description provided for @importedKeyRememberFailed.
  ///
  /// In en, this message translates to:
  /// **'Imported {keyName}, but remembering the passphrase failed.'**
  String importedKeyRememberFailed(String keyName);

  /// No description provided for @deleteLocalStore.
  ///
  /// In en, this message translates to:
  /// **'Delete local store'**
  String get deleteLocalStore;

  /// No description provided for @pathValue.
  ///
  /// In en, this message translates to:
  /// **'Path: {path}'**
  String pathValue(String path);

  /// No description provided for @typeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type {value} to confirm'**
  String typeToConfirm(String value);

  /// No description provided for @batchSelection.
  ///
  /// In en, this message translates to:
  /// **'Batch selection'**
  String get batchSelection;

  /// No description provided for @securitySection.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySection;

  /// No description provided for @securityPrivacySection.
  ///
  /// In en, this message translates to:
  /// **'Security and privacy'**
  String get securityPrivacySection;

  /// No description provided for @vaultSyncSection.
  ///
  /// In en, this message translates to:
  /// **'Vault and sync'**
  String get vaultSyncSection;

  /// No description provided for @autofillSection.
  ///
  /// In en, this message translates to:
  /// **'Autofill'**
  String get autofillSection;

  /// No description provided for @advancedSupportSection.
  ///
  /// In en, this message translates to:
  /// **'Advanced and support'**
  String get advancedSupportSection;

  /// No description provided for @platformSection.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platformSection;

  /// No description provided for @gestureBiometricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Gesture lock and biometrics'**
  String get gestureBiometricsTitle;

  /// No description provided for @lockOnResumeState.
  ///
  /// In en, this message translates to:
  /// **'Lock on app resume'**
  String get lockOnResumeState;

  /// No description provided for @gestureConfiguredState.
  ///
  /// In en, this message translates to:
  /// **'Gesture unlock configured'**
  String get gestureConfiguredState;

  /// No description provided for @pgpSessionTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'PGP session timeout'**
  String get pgpSessionTimeoutTitle;

  /// No description provided for @keychainPassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'KMS / Keychain passphrase'**
  String get keychainPassphraseTitle;

  /// No description provided for @pgpPassphraseCachedState.
  ///
  /// In en, this message translates to:
  /// **'PGP passphrase cached'**
  String get pgpPassphraseCachedState;

  /// No description provided for @optionalPassphraseCacheState.
  ///
  /// In en, this message translates to:
  /// **'Optional encrypted passphrase cache'**
  String get optionalPassphraseCacheState;

  /// No description provided for @sshKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH keys'**
  String get sshKeysTitle;

  /// No description provided for @githubAccessKeysDescription.
  ///
  /// In en, this message translates to:
  /// **'GitHub access keys'**
  String get githubAccessKeysDescription;

  /// No description provided for @gitSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Git sync and remotes'**
  String get gitSyncTitle;

  /// No description provided for @gitSyncDescription.
  ///
  /// In en, this message translates to:
  /// **'Pull, push, status, remotes'**
  String get gitSyncDescription;

  /// No description provided for @advancedGitArgsTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced Git args'**
  String get advancedGitArgsTitle;

  /// No description provided for @advancedGitArgsDescription.
  ///
  /// In en, this message translates to:
  /// **'Arguments after git only'**
  String get advancedGitArgsDescription;

  /// No description provided for @systemAutofillTitle.
  ///
  /// In en, this message translates to:
  /// **'System Autofill'**
  String get systemAutofillTitle;

  /// No description provided for @runtimeDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Runtime diagnostics'**
  String get runtimeDiagnosticsTitle;

  /// No description provided for @runtimeDiagnosticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Bridge, core, crypto, Git, key storage'**
  String get runtimeDiagnosticsDescription;

  /// No description provided for @bridgeLoadedLabel.
  ///
  /// In en, this message translates to:
  /// **'Bridge loaded'**
  String get bridgeLoadedLabel;

  /// No description provided for @coreVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Core version'**
  String get coreVersionLabel;

  /// No description provided for @nativeLibraryLabel.
  ///
  /// In en, this message translates to:
  /// **'Native library'**
  String get nativeLibraryLabel;

  /// No description provided for @pgpBackendLabel.
  ///
  /// In en, this message translates to:
  /// **'PGP backend'**
  String get pgpBackendLabel;

  /// No description provided for @gitBackendLabel.
  ///
  /// In en, this message translates to:
  /// **'Git backend'**
  String get gitBackendLabel;

  /// No description provided for @keyStorageBackendLabel.
  ///
  /// In en, this message translates to:
  /// **'Key storage backend'**
  String get keyStorageBackendLabel;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @replaceCachedPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Replace cached passphrase'**
  String get replaceCachedPassphrase;

  /// No description provided for @noCachedPassphrase.
  ///
  /// In en, this message translates to:
  /// **'No PGP passphrase is cached.'**
  String get noCachedPassphrase;

  /// No description provided for @cachedForKey.
  ///
  /// In en, this message translates to:
  /// **'Cached for {keyName}'**
  String cachedForKey(String keyName);

  /// No description provided for @updatePasswordStore.
  ///
  /// In en, this message translates to:
  /// **'Update password store'**
  String get updatePasswordStore;

  /// No description provided for @featureUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'This repository does not provide the operations required for this feature. Use a bridge-backed repository to enable it.'**
  String get featureUnavailableDescription;

  /// No description provided for @changeGesture.
  ///
  /// In en, this message translates to:
  /// **'Change gesture'**
  String get changeGesture;

  /// No description provided for @requireUnlockOnResume.
  ///
  /// In en, this message translates to:
  /// **'Require unlock on app resume'**
  String get requireUnlockOnResume;

  /// No description provided for @gestureFallbackDescription.
  ///
  /// In en, this message translates to:
  /// **'Gesture unlock is used as fallback'**
  String get gestureFallbackDescription;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricUnlock;

  /// No description provided for @enabledOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Enabled on this device'**
  String get enabledOnDevice;

  /// No description provided for @availableOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Available on this device'**
  String get availableOnDevice;

  /// No description provided for @unavailableOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Unavailable on this device'**
  String get unavailableOnDevice;

  /// No description provided for @gestureLock.
  ///
  /// In en, this message translates to:
  /// **'Gesture lock'**
  String get gestureLock;

  /// No description provided for @passwordStore.
  ///
  /// In en, this message translates to:
  /// **'Password store'**
  String get passwordStore;

  /// No description provided for @pgpKey.
  ///
  /// In en, this message translates to:
  /// **'PGP key'**
  String get pgpKey;

  /// No description provided for @sshKey.
  ///
  /// In en, this message translates to:
  /// **'SSH key'**
  String get sshKey;

  /// No description provided for @autoLockTimeout.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock timeout'**
  String get autoLockTimeout;

  /// No description provided for @resetOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Reset onboarding'**
  String get resetOnboarding;

  /// No description provided for @drawConfirmGesture.
  ///
  /// In en, this message translates to:
  /// **'Draw and confirm a new local unlock gesture.'**
  String get drawConfirmGesture;

  /// No description provided for @storePgpPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Store PGP passphrase'**
  String get storePgpPassphrase;

  /// No description provided for @savedInSecureStorage.
  ///
  /// In en, this message translates to:
  /// **'Saved in the platform secure storage provider'**
  String get savedInSecureStorage;

  /// No description provided for @noPrivatePgpKeys.
  ///
  /// In en, this message translates to:
  /// **'No private PGP keys'**
  String get noPrivatePgpKeys;

  /// No description provided for @createPrivatePgpKeyFirst.
  ///
  /// In en, this message translates to:
  /// **'Import or create a private PGP key before saving a passphrase.'**
  String get createPrivatePgpKeyFirst;

  /// No description provided for @rebuildPaths.
  ///
  /// In en, this message translates to:
  /// **'Rebuild paths'**
  String get rebuildPaths;

  /// No description provided for @readUrlFields.
  ///
  /// In en, this message translates to:
  /// **'Read URL fields'**
  String get readUrlFields;

  /// No description provided for @clearUrlAliases.
  ///
  /// In en, this message translates to:
  /// **'Clear URL aliases'**
  String get clearUrlAliases;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @readEncryptedUrlFieldsTitle.
  ///
  /// In en, this message translates to:
  /// **'Read encrypted URL fields?'**
  String get readEncryptedUrlFieldsTitle;

  /// No description provided for @readEncryptedUrlFieldsDescription.
  ///
  /// In en, this message translates to:
  /// **'This optional action decrypts all {count} selected entries once and stores only normalized website aliases. Path-based Autofill does not require it.'**
  String readEncryptedUrlFieldsDescription(int count);

  /// No description provided for @readSelectedEntries.
  ///
  /// In en, this message translates to:
  /// **'Read selected entries'**
  String get readSelectedEntries;

  /// No description provided for @autofillRebuiltSuccess.
  ///
  /// In en, this message translates to:
  /// **'Path-based Autofill data rebuilt without decrypting entries.'**
  String get autofillRebuiltSuccess;

  /// No description provided for @autofillAliasesCleared.
  ///
  /// In en, this message translates to:
  /// **'Encrypted website aliases cleared.'**
  String get autofillAliasesCleared;

  /// No description provided for @autofillDataCleared.
  ///
  /// In en, this message translates to:
  /// **'Autofill data cleared.'**
  String get autofillDataCleared;

  /// No description provided for @clearAutofillConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Remove all shared Autofill candidates for this store? This does not delete password entries.'**
  String get clearAutofillConfirmation;

  /// No description provided for @openSystemPasswordSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system password settings.'**
  String get openSystemPasswordSettings;

  /// No description provided for @autofillAliasesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Encrypted website aliases updated.'**
  String get autofillAliasesUpdated;

  /// No description provided for @noEntriesToEnrich.
  ///
  /// In en, this message translates to:
  /// **'There are no password entries to enrich.'**
  String get noEntriesToEnrich;

  /// No description provided for @autofillBridgeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Autofill bridge unavailable'**
  String get autofillBridgeUnavailable;

  /// No description provided for @autofillNotRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Not refreshed'**
  String get autofillNotRefreshed;

  /// No description provided for @autofillReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get autofillReady;

  /// No description provided for @autofillNeedsRebuild.
  ///
  /// In en, this message translates to:
  /// **'Needs rebuild'**
  String get autofillNeedsRebuild;

  /// No description provided for @autofillBusy.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get autofillBusy;

  /// No description provided for @autofillDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get autofillDisabled;

  /// No description provided for @autofillUnavailableState.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get autofillUnavailableState;

  /// No description provided for @autofillIndexedEntries.
  ///
  /// In en, this message translates to:
  /// **'{count} entries indexed'**
  String autofillIndexedEntries(int count);

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @createOrImportKey.
  ///
  /// In en, this message translates to:
  /// **'Create or import a key.'**
  String get createOrImportKey;

  /// No description provided for @noPgpKeys.
  ///
  /// In en, this message translates to:
  /// **'No PGP keys'**
  String get noPgpKeys;

  /// No description provided for @noSshKeys.
  ///
  /// In en, this message translates to:
  /// **'No SSH keys'**
  String get noSshKeys;

  /// No description provided for @keyActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions for {keyType} key {keyName}'**
  String keyActionsTooltip(String keyType, String keyName);

  /// No description provided for @exportPublic.
  ///
  /// In en, this message translates to:
  /// **'Export public'**
  String get exportPublic;

  /// No description provided for @exportPrivate.
  ///
  /// In en, this message translates to:
  /// **'Export private'**
  String get exportPrivate;

  /// No description provided for @addToGpgId.
  ///
  /// In en, this message translates to:
  /// **'Add to .gpg-id'**
  String get addToGpgId;

  /// No description provided for @importPgpKey.
  ///
  /// In en, this message translates to:
  /// **'Import PGP key'**
  String get importPgpKey;

  /// No description provided for @importSshKey.
  ///
  /// In en, this message translates to:
  /// **'Import SSH key'**
  String get importSshKey;

  /// No description provided for @textSource.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textSource;

  /// No description provided for @fileSource.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileSource;

  /// No description provided for @importSshKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Import SSH key file'**
  String get importSshKeyFile;

  /// No description provided for @nameField.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameField;

  /// No description provided for @keyTextField.
  ///
  /// In en, this message translates to:
  /// **'Key text'**
  String get keyTextField;

  /// No description provided for @keyFileField.
  ///
  /// In en, this message translates to:
  /// **'Key file'**
  String get keyFileField;

  /// No description provided for @pastePgpKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Paste a PGP public or private key.'**
  String get pastePgpKeyHelp;

  /// No description provided for @pgpPassphraseUnlockHelp.
  ///
  /// In en, this message translates to:
  /// **'Required to unlock this private key.'**
  String get pgpPassphraseUnlockHelp;

  /// No description provided for @unlockAndImport.
  ///
  /// In en, this message translates to:
  /// **'Unlock and import'**
  String get unlockAndImport;

  /// No description provided for @exportPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Export private key'**
  String get exportPrivateKey;

  /// No description provided for @privateExportSensitive.
  ///
  /// In en, this message translates to:
  /// **'Private key export is sensitive. Type {confirmation} to export.'**
  String privateExportSensitive(String confirmation);

  /// No description provided for @exportedKey.
  ///
  /// In en, this message translates to:
  /// **'Exported key'**
  String get exportedKey;

  /// No description provided for @createImportCloneStore.
  ///
  /// In en, this message translates to:
  /// **'Create, import, or clone a store.'**
  String get createImportCloneStore;

  /// No description provided for @removeFromApp.
  ///
  /// In en, this message translates to:
  /// **'Remove from app'**
  String get removeFromApp;

  /// No description provided for @cloneAction.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get cloneAction;

  /// No description provided for @pull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get pull;

  /// No description provided for @push.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get push;

  /// No description provided for @recoverPull.
  ///
  /// In en, this message translates to:
  /// **'Recover pull'**
  String get recoverPull;

  /// No description provided for @pushAfterCommit.
  ///
  /// In en, this message translates to:
  /// **'Push after commit'**
  String get pushAfterCommit;

  /// No description provided for @commit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get commit;

  /// No description provided for @listRemotes.
  ///
  /// In en, this message translates to:
  /// **'List remotes'**
  String get listRemotes;

  /// No description provided for @addRemote.
  ///
  /// In en, this message translates to:
  /// **'Add remote'**
  String get addRemote;

  /// No description provided for @updateRemote.
  ///
  /// In en, this message translates to:
  /// **'Update remote'**
  String get updateRemote;

  /// No description provided for @removeRemote.
  ///
  /// In en, this message translates to:
  /// **'Remove remote'**
  String get removeRemote;

  /// No description provided for @deleteLocalRepo.
  ///
  /// In en, this message translates to:
  /// **'Delete local repo'**
  String get deleteLocalRepo;

  /// No description provided for @gitArgsOnlyDescription.
  ///
  /// In en, this message translates to:
  /// **'Only enter arguments after git. Shell syntax is not accepted.'**
  String get gitArgsOnlyDescription;

  /// No description provided for @runSelectedCommand.
  ///
  /// In en, this message translates to:
  /// **'Run selected command'**
  String get runSelectedCommand;

  /// No description provided for @exitCodeValue.
  ///
  /// In en, this message translates to:
  /// **'Exit: {value}'**
  String exitCodeValue(String value);

  /// No description provided for @standardOutput.
  ///
  /// In en, this message translates to:
  /// **'stdout'**
  String get standardOutput;

  /// No description provided for @standardError.
  ///
  /// In en, this message translates to:
  /// **'stderr'**
  String get standardError;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed. Try again or open Details.'**
  String get operationFailed;

  /// No description provided for @actionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get actionSaved;

  /// No description provided for @actionEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get actionEdited;

  /// No description provided for @actionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get actionDeleted;

  /// No description provided for @actionMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get actionMoved;

  /// No description provided for @actionRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get actionRenamed;

  /// No description provided for @actionRegenerated.
  ///
  /// In en, this message translates to:
  /// **'Regenerated'**
  String get actionRegenerated;

  /// No description provided for @actionUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get actionUpdated;

  /// No description provided for @entryOverwroteExisting.
  ///
  /// In en, this message translates to:
  /// **' (overwrote existing)'**
  String get entryOverwroteExisting;

  /// No description provided for @entryCommitted.
  ///
  /// In en, this message translates to:
  /// **' and committed'**
  String get entryCommitted;

  /// No description provided for @entryOperationSummary.
  ///
  /// In en, this message translates to:
  /// **'{action} {path}{overwrite}{commit}'**
  String entryOperationSummary(
    String action,
    String path,
    String overwrite,
    String commit,
  );

  /// No description provided for @batchOperationSummary.
  ///
  /// In en, this message translates to:
  /// **'{action} {count} entries{commit}'**
  String batchOperationSummary(String action, int count, String commit);

  /// No description provided for @batchFailureSuffix.
  ///
  /// In en, this message translates to:
  /// **'; {count} failed'**
  String batchFailureSuffix(int count);

  /// No description provided for @postMutationCommitFailed.
  ///
  /// In en, this message translates to:
  /// **'{mutationSummary}, but the optional Git commit failed. The vault mutation was not rolled back.'**
  String postMutationCommitFailed(String mutationSummary);

  /// No description provided for @diagnosticDetails.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic details'**
  String get diagnosticDetails;

  /// No description provided for @lockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get lockNow;

  /// No description provided for @unlockPars.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pars'**
  String get unlockPars;

  /// No description provided for @drawGestureToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Draw your gesture to open the local app session.'**
  String get drawGestureToUnlock;

  /// No description provided for @unlockWithBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get unlockWithBiometrics;

  /// No description provided for @gestureDidNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Gesture did not match'**
  String get gestureDidNotMatch;

  /// No description provided for @biometricUnlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock failed'**
  String get biometricUnlockFailed;

  /// No description provided for @resetGesture.
  ///
  /// In en, this message translates to:
  /// **'Reset gesture'**
  String get resetGesture;

  /// No description provided for @drawSameGesture.
  ///
  /// In en, this message translates to:
  /// **'Draw the same gesture again.'**
  String get drawSameGesture;

  /// No description provided for @drawAtLeastFourDots.
  ///
  /// In en, this message translates to:
  /// **'Draw at least 4 dots.'**
  String get drawAtLeastFourDots;

  /// No description provided for @startNewGesture.
  ///
  /// In en, this message translates to:
  /// **'Start again with a new gesture.'**
  String get startNewGesture;

  /// No description provided for @useAtLeastFourDots.
  ///
  /// In en, this message translates to:
  /// **'Use at least 4 dots.'**
  String get useAtLeastFourDots;

  /// No description provided for @gestureCapturedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Gesture captured. Confirm it once more.'**
  String get gestureCapturedConfirm;

  /// No description provided for @gesturesDidNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Gestures did not match. Start again.'**
  String get gesturesDidNotMatch;

  /// No description provided for @gestureConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Gesture confirmed.'**
  String get gestureConfirmed;

  /// No description provided for @gesturePatternInput.
  ///
  /// In en, this message translates to:
  /// **'Gesture pattern input'**
  String get gesturePatternInput;

  /// No description provided for @gestureDot.
  ///
  /// In en, this message translates to:
  /// **'Gesture dot {number}'**
  String gestureDot(int number);

  /// No description provided for @clearGesture.
  ///
  /// In en, this message translates to:
  /// **'Clear gesture'**
  String get clearGesture;

  /// No description provided for @submitGesture.
  ///
  /// In en, this message translates to:
  /// **'Submit gesture'**
  String get submitGesture;

  /// No description provided for @rememberInKeychain.
  ///
  /// In en, this message translates to:
  /// **'Remember in Keychain/KMS'**
  String get rememberInKeychain;

  /// No description provided for @rememberPassphraseDescription.
  ///
  /// In en, this message translates to:
  /// **'Off by default. The passphrase stays in memory for this session unless you explicitly remember it.'**
  String get rememberPassphraseDescription;

  /// No description provided for @inspectingKeyMaterial.
  ///
  /// In en, this message translates to:
  /// **'Inspecting key material…'**
  String get inspectingKeyMaterial;

  /// No description provided for @setGestureLock.
  ///
  /// In en, this message translates to:
  /// **'Set gesture lock'**
  String get setGestureLock;

  /// No description provided for @enableBiometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric unlock'**
  String get enableBiometricUnlock;

  /// No description provided for @choosePgpKey.
  ///
  /// In en, this message translates to:
  /// **'Choose PGP key'**
  String get choosePgpKey;

  /// No description provided for @setupSshGithub.
  ///
  /// In en, this message translates to:
  /// **'Set up SSH for GitHub'**
  String get setupSshGithub;

  /// No description provided for @setupPasswordStore.
  ///
  /// In en, this message translates to:
  /// **'Set up password store'**
  String get setupPasswordStore;

  /// No description provided for @reviewSetup.
  ///
  /// In en, this message translates to:
  /// **'Review setup'**
  String get reviewSetup;

  /// No description provided for @gestureStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use a 9-dot gesture as the local Pars unlock method.'**
  String get gestureStepSubtitle;

  /// No description provided for @biometricsStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Biometrics are optional and keep the gesture as fallback.'**
  String get biometricsStepSubtitle;

  /// No description provided for @pgpStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select, create, or import the key used to encrypt passwords.'**
  String get pgpStepSubtitle;

  /// No description provided for @sshStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SSH is optional and enables authenticated Git operations.'**
  String get sshStepSubtitle;

  /// No description provided for @storeStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how Pars should open or create your password store.'**
  String get storeStepSubtitle;

  /// No description provided for @reviewStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm required setup before opening the vault.'**
  String get reviewStepSubtitle;

  /// No description provided for @githubSshSettings.
  ///
  /// In en, this message translates to:
  /// **'GitHub SSH settings'**
  String get githubSshSettings;

  /// No description provided for @onboardingProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingProgress(int current, int total);

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @gestureStep.
  ///
  /// In en, this message translates to:
  /// **'Gesture'**
  String get gestureStep;

  /// No description provided for @biometricsStep.
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get biometricsStep;

  /// No description provided for @pgpStep.
  ///
  /// In en, this message translates to:
  /// **'PGP'**
  String get pgpStep;

  /// No description provided for @sshStep.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get sshStep;

  /// No description provided for @storeStep.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get storeStep;

  /// No description provided for @reviewStep.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewStep;

  /// No description provided for @skipBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Skip biometrics'**
  String get skipBiometrics;

  /// No description provided for @finishSetup.
  ///
  /// In en, this message translates to:
  /// **'Finish setup'**
  String get finishSetup;

  /// No description provided for @noPgpKeysFound.
  ///
  /// In en, this message translates to:
  /// **'No PGP keys found'**
  String get noPgpKeysFound;

  /// No description provided for @createOrImportEncryptionKey.
  ///
  /// In en, this message translates to:
  /// **'Create or import a key to encrypt entries.'**
  String get createOrImportEncryptionKey;

  /// No description provided for @usePgpKey.
  ///
  /// In en, this message translates to:
  /// **'Use PGP key'**
  String get usePgpKey;

  /// No description provided for @createPgpKey.
  ///
  /// In en, this message translates to:
  /// **'Create PGP key'**
  String get createPgpKey;

  /// No description provided for @createSshKey.
  ///
  /// In en, this message translates to:
  /// **'Create SSH key'**
  String get createSshKey;

  /// No description provided for @emailField.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailField;

  /// No description provided for @passphraseField.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphraseField;

  /// No description provided for @noSshKeysConfigured.
  ///
  /// In en, this message translates to:
  /// **'No SSH keys configured'**
  String get noSshKeysConfigured;

  /// No description provided for @sshOptionalDescription.
  ///
  /// In en, this message translates to:
  /// **'SSH is optional and can be added later.'**
  String get sshOptionalDescription;

  /// No description provided for @generateSshKey.
  ///
  /// In en, this message translates to:
  /// **'Generate SSH key'**
  String get generateSshKey;

  /// No description provided for @githubSettings.
  ///
  /// In en, this message translates to:
  /// **'GitHub settings'**
  String get githubSettings;

  /// No description provided for @skipSsh.
  ///
  /// In en, this message translates to:
  /// **'Skip SSH'**
  String get skipSsh;

  /// No description provided for @createLocalStore.
  ///
  /// In en, this message translates to:
  /// **'Create local store'**
  String get createLocalStore;

  /// No description provided for @importLocalStore.
  ///
  /// In en, this message translates to:
  /// **'Import local store'**
  String get importLocalStore;

  /// No description provided for @cloneGitStore.
  ///
  /// In en, this message translates to:
  /// **'Clone Git store'**
  String get cloneGitStore;

  /// No description provided for @addSshBeforeClone.
  ///
  /// In en, this message translates to:
  /// **'Add an SSH key before cloning a Git store.'**
  String get addSshBeforeClone;

  /// No description provided for @noStoreRepository.
  ///
  /// In en, this message translates to:
  /// **'No store repository available'**
  String get noStoreRepository;

  /// No description provided for @configured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get configured;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skipped;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// No description provided for @gitMetadataNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Git metadata not found'**
  String get gitMetadataNotFoundTitle;

  /// No description provided for @gitMetadataNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'The folder may be local-only, or Android may have hidden its .git data. Initializing creates new history and cannot recover existing history.'**
  String get gitMetadataNotFoundMessage;

  /// No description provided for @initializeGit.
  ///
  /// In en, this message translates to:
  /// **'Initialize Git'**
  String get initializeGit;

  /// No description provided for @continueWithoutGit.
  ///
  /// In en, this message translates to:
  /// **'Continue without Git'**
  String get continueWithoutGit;

  /// No description provided for @keyCount.
  ///
  /// In en, this message translates to:
  /// **'{count} key(s)'**
  String keyCount(int count);

  /// No description provided for @storeFirstSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import or clone your password store. Create a new store only if you do not have one yet.'**
  String get storeFirstSetupSubtitle;

  /// No description provided for @createStoreRecipientSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a private PGP key only for the new store you are creating.'**
  String get createStoreRecipientSubtitle;

  /// No description provided for @contextualRepairSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Repair only what this password store requires.'**
  String get contextualRepairSubtitle;

  /// No description provided for @repairPasswordStore.
  ///
  /// In en, this message translates to:
  /// **'Repair password store'**
  String get repairPasswordStore;

  /// No description provided for @createStoreNeedsPgpKey.
  ///
  /// In en, this message translates to:
  /// **'Creating a new store requires choosing or importing a private PGP key first.'**
  String get createStoreNeedsPgpKey;

  /// No description provided for @gitOptionalForLocalStore.
  ///
  /// In en, this message translates to:
  /// **'Git is optional. The password store remains usable without it.'**
  String get gitOptionalForLocalStore;

  /// No description provided for @sshKeyRequiredForRemote.
  ///
  /// In en, this message translates to:
  /// **'SSH key required for this remote'**
  String get sshKeyRequiredForRemote;

  /// No description provided for @sshRequiredForThisClone.
  ///
  /// In en, this message translates to:
  /// **'This SSH remote needs a key. HTTPS clones do not.'**
  String get sshRequiredForThisClone;

  /// No description provided for @missingGpgIdTitle.
  ///
  /// In en, this message translates to:
  /// **'Encryption recipients are missing'**
  String get missingGpgIdTitle;

  /// No description provided for @missingGpgIdMessage.
  ///
  /// In en, this message translates to:
  /// **'Choose a private PGP key to create this store\'s missing .gpg-id. Existing recipient files are never replaced here.'**
  String get missingGpgIdMessage;

  /// No description provided for @requiredPgpKeyMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Required private PGP key missing'**
  String get requiredPgpKeyMissingTitle;

  /// No description provided for @requiredPgpKeyMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'Import private material matching one of these recipients: {recipients}'**
  String requiredPgpKeyMissingMessage(String recipients);

  /// No description provided for @requiredPrivatePgpKey.
  ///
  /// In en, this message translates to:
  /// **'A matching private PGP key is required.'**
  String get requiredPrivatePgpKey;

  /// No description provided for @pgpKeyDoesNotMatchStore.
  ///
  /// In en, this message translates to:
  /// **'This private key does not match the password store recipients.'**
  String get pgpKeyDoesNotMatchStore;

  /// No description provided for @invalidGitMetadataTitle.
  ///
  /// In en, this message translates to:
  /// **'Git metadata is invalid'**
  String get invalidGitMetadataTitle;

  /// No description provided for @invalidGitMetadataMessage.
  ///
  /// In en, this message translates to:
  /// **'This password store contains unusable Git metadata. Disconnect it, then import or clone a valid copy.'**
  String get invalidGitMetadataMessage;

  /// No description provided for @disconnectStore.
  ///
  /// In en, this message translates to:
  /// **'Disconnect password store'**
  String get disconnectStore;

  /// No description provided for @gitDisabledState.
  ///
  /// In en, this message translates to:
  /// **'Git disabled · local password store'**
  String get gitDisabledState;

  /// No description provided for @gitLocalState.
  ///
  /// In en, this message translates to:
  /// **'Local Git · no remote'**
  String get gitLocalState;

  /// No description provided for @gitRemoteState.
  ///
  /// In en, this message translates to:
  /// **'Git remote configured'**
  String get gitRemoteState;

  /// No description provided for @storeIssues.
  ///
  /// In en, this message translates to:
  /// **'Repair needed'**
  String get storeIssues;

  /// No description provided for @sshKeysGitOnlyDescription.
  ///
  /// In en, this message translates to:
  /// **'SSH keys are used only for SSH Git remotes. HTTPS and local-only stores do not require them.'**
  String get sshKeysGitOnlyDescription;

  /// No description provided for @storeRemovalInProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Removing password store…'**
  String get storeRemovalInProgressTitle;

  /// No description provided for @storeRemovalInProgressDescription.
  ///
  /// In en, this message translates to:
  /// **'Pars is clearing local session and Autofill data before changing the configured store.'**
  String get storeRemovalInProgressDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
