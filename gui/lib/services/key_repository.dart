import '../models/key_record.dart';
import '../models/pgp_key_import.dart';

bool pgpIdentityMatchesRecipient({
  required String fingerprint,
  required String identity,
  required String recipient,
}) {
  final requiredCompact =
      recipient.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  final fingerprintCompact =
      fingerprint.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (requiredCompact.isEmpty) return false;
  if (fingerprintCompact == requiredCompact ||
      fingerprintCompact.endsWith(requiredCompact)) {
    return true;
  }
  final normalizedIdentity = identity.trim();
  return normalizedIdentity.toLowerCase() == recipient.trim().toLowerCase() ||
      normalizedIdentity.toLowerCase().contains(
        '<${recipient.trim().toLowerCase()}>',
      );
}

bool pgpIdentityMatchesAnyRecipient({
  required String fingerprint,
  required String identity,
  required Iterable<String> recipients,
}) => recipients.any(
  (recipient) => pgpIdentityMatchesRecipient(
    fingerprint: fingerprint,
    identity: identity,
    recipient: recipient,
  ),
);

/// Result of a completed PGP import: the imported key plus what inspection found.
class PgpImportResult {
  const PgpImportResult({required this.key, required this.inspection});

  final KeyRecord key;
  final PgpKeyInspection inspection;
}

class PgpPrivateKeyPreparation {
  const PgpPrivateKeyPreparation({
    required this.fingerprint,
    required this.migrated,
  });

  final String fingerprint;
  final bool migrated;
}

abstract interface class KeyRepository {
  List<KeyRecord> get keys;

  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  });

  /// Inspects pasted PGP key material without importing it.
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText);

  /// Inspects a local key file. Its bytes are read in Rust and never enter Dart.
  Future<PgpKeyInspection> inspectPgpKeyFile(String path);

  /// Imports pasted PGP key material of either kind.
  ///
  /// [passphrase] is required only when inspection reported `requiresPassphrase`; it is validated
  /// against the material before any keyring is mutated.
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  });

  /// Imports a PGP key file of either kind, including binary OpenPGP exports.
  Future<PgpImportResult> importPgpKeyFile(String path, {String? passphrase});

  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  });

  Future<void> initializeStoreRecipients(List<String> fingerprints);

  Future<KeyRecord> generateSshKey(String name);

  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  });

  Future<KeyRecord> importSshPrivateKeyFile({
    required String name,
    required String path,
  });

  Future<String> exportSshPublicKey(String name);

  Future<String> exportSshPrivateKey({
    required String name,
    required String confirmation,
  });

  Future<void> deleteSshKey(String name);

  Future<Uri> githubSshSettingsUri();
}
