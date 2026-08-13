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

  /// No description provided for @managedStoreMergeLabel.
  ///
  /// In en, this message translates to:
  /// **'Merge and overwrite'**
  String get managedStoreMergeLabel;

  /// No description provided for @managedStoreMergeDescription.
  ///
  /// In en, this message translates to:
  /// **'Overwrite matching files and keep files that exist only in the current copy.'**
  String get managedStoreMergeDescription;

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

  /// No description provided for @pgpKeyDeletePartial.
  ///
  /// In en, this message translates to:
  /// **'The protected private key was deleted, but its public listing could not be removed.'**
  String get pgpKeyDeletePartial;

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
