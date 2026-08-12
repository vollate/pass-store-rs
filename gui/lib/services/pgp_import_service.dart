import '../models/key_record.dart';
import '../models/pgp_key_import.dart';
import 'key_repository.dart';
import 'security_repository.dart';

/// What happened to the passphrase after a successful protected-key import.
enum PgpPassphraseStorageOutcome {
  /// Public or unprotected material: no passphrase was involved.
  notApplicable,

  /// Session started, nothing written to durable storage.
  sessionOnly,

  /// Session started and the passphrase saved to the Keychain/KMS.
  remembered,

  /// Session started, but durable storage failed. The key is still imported.
  rememberFailed,
}

/// Outcome of an import plus the security work that followed it.
class PgpImportCompletion {
  const PgpImportCompletion({
    required this.key,
    required this.inspection,
    required this.storage,
    this.storageError,
  });

  final KeyRecord key;
  final PgpKeyInspection inspection;
  final PgpPassphraseStorageOutcome storage;

  /// Sanitized reason durable storage failed. Never contains the passphrase.
  final String? storageError;

  bool get rememberFailed =>
      storage == PgpPassphraseStorageOutcome.rememberFailed;
}

/// Imports a PGP key and applies this app's passphrase policy to the result.
///
/// Shared by Settings and Onboarding so both surfaces behave identically: the bridge validates and
/// imports, and this decides what happens to the validated passphrase.
///
/// A protected import starts an in-memory session bound to the *returned* fingerprint, never the
/// one the caller guessed. Durable storage happens only when [remember] is true, and a storage
/// failure does not roll back the imported key or the active session — the user can retry from
/// Settings.
Future<PgpImportCompletion> importPgpKeyWithSecurity({
  required KeyRepository keyRepository,
  required SecurityRepository securityRepository,
  required PgpImportSource source,
  required String value,
  String? passphrase,
  bool remember = false,
}) async {
  final result = switch (source) {
    PgpImportSource.text => await keyRepository.importPgpKeyText(
      value,
      passphrase: passphrase,
    ),
    PgpImportSource.file => await keyRepository.importPgpKeyFile(
      value,
      passphrase: passphrase,
    ),
  };

  final needsPassphrase =
      result.inspection.requiresPassphrase &&
      passphrase != null &&
      passphrase.isNotEmpty;
  if (!needsPassphrase) {
    return PgpImportCompletion(
      key: result.key,
      inspection: result.inspection,
      storage: PgpPassphraseStorageOutcome.notApplicable,
    );
  }

  // Bind the session to the fingerprint the backend confirmed.
  final fingerprint = result.key.fingerprint;
  await securityRepository.startPgpSession(
    fingerprint: fingerprint,
    passphrase: passphrase,
  );

  if (!remember) {
    return PgpImportCompletion(
      key: result.key,
      inspection: result.inspection,
      storage: PgpPassphraseStorageOutcome.sessionOnly,
    );
  }

  try {
    if (!securityRepository.pgpPassphraseStorageEnabled) {
      await securityRepository.setPgpPassphraseStorageEnabled(true);
    }
    await securityRepository.savePgpPassphrase(
      fingerprint: fingerprint,
      passphrase: passphrase,
    );
    return PgpImportCompletion(
      key: result.key,
      inspection: result.inspection,
      storage: PgpPassphraseStorageOutcome.remembered,
    );
  } catch (error) {
    // The key is imported and the session is live; only remembering failed.
    return PgpImportCompletion(
      key: result.key,
      inspection: result.inspection,
      storage: PgpPassphraseStorageOutcome.rememberFailed,
      storageError: error.toString(),
    );
  }
}
