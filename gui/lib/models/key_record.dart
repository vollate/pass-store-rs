enum KeyRecordType { pgp, ssh }

class KeyRecord {
  const KeyRecord({
    required this.type,
    required this.name,
    required this.fingerprint,
    required this.source,
    required this.hasPrivateKey,
    this.hasLocalKeyMaterial = true,
    this.referencedByStores = const <String>[],
    this.encrypted = false,
  });

  final KeyRecordType type;
  final String name;
  final String fingerprint;
  final String source;
  final bool hasPrivateKey;

  /// An SSH key that needs its passphrase before Git can use it.
  final bool encrypted;
  final bool hasLocalKeyMaterial;
  final List<String> referencedByStores;

  String get typeLabel {
    switch (type) {
      case KeyRecordType.pgp:
        return 'PGP';
      case KeyRecordType.ssh:
        return 'SSH';
    }
  }
}
