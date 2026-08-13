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
  });

  final KeyRecordType type;
  final String name;
  final String fingerprint;
  final String source;
  final bool hasPrivateKey;
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
