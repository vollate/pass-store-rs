import '../models/key_record.dart';

abstract interface class KeyRepository {
  List<KeyRecord> get keys;

  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  });

  Future<KeyRecord> importPgpPublicKeyText(String armoredText);

  Future<KeyRecord> importPgpPrivateKeyText(String armoredText);

  Future<KeyRecord> importPgpPrivateKeyFile(String path);

  Future<String> exportPgpPublicKey(String fingerprint);

  Future<String> exportPgpPrivateKey({
    required String fingerprint,
    required String confirmation,
  });

  Future<void> deletePgpKey(String fingerprint);

  Future<void> addPgpKeyToSelectedStore(String fingerprint);

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
