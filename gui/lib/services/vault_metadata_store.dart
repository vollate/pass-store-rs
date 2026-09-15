import 'dart:convert';
import 'dart:io';

class VaultMetadata {
  static const int currentVersion = 2;

  const VaultMetadata({
    this.storeRoot,
    this.removalTombstone = false,
    this.version = currentVersion,
  });

  const VaultMetadata.empty({
    this.storeRoot,
    this.removalTombstone = false,
    this.version = currentVersion,
  });

  const VaultMetadata.removed()
    : storeRoot = '',
      removalTombstone = true,
      version = currentVersion;

  final String? storeRoot;
  final bool removalTombstone;
  final int version;

  VaultMetadata copyWith({
    String? storeRoot,
    bool? removalTombstone,
    int? version,
  }) {
    return VaultMetadata(
      storeRoot: storeRoot ?? this.storeRoot,
      removalTombstone: removalTombstone ?? this.removalTombstone,
      version: version ?? this.version,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': currentVersion,
      'storeRoot': storeRoot,
      'removalTombstone': removalTombstone,
    };
  }

  static VaultMetadata fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const VaultMetadata.empty();
    }
    return VaultMetadata(
      version: value['version'] is int ? value['version'] as int : 1,
      storeRoot:
          value['storeRoot'] is String ? value['storeRoot'] as String : null,
      removalTombstone: value['removalTombstone'] == true,
    );
  }
}

abstract interface class VaultMetadataStore {
  Future<VaultMetadata> load();

  Future<void> save(VaultMetadata metadata);

  Future<void> markStoreRemoved();

  Future<bool> wasStoreRemoved();

  Future<void> clearStoreRemovedMarker();
}

class InMemoryVaultMetadataStore implements VaultMetadataStore {
  VaultMetadata _metadata;
  bool _storeRemoved = false;

  InMemoryVaultMetadataStore([VaultMetadata? metadata])
    : _metadata = metadata ?? const VaultMetadata.empty();

  @override
  Future<VaultMetadata> load() async => _metadata;

  @override
  Future<void> save(VaultMetadata metadata) async {
    _metadata = metadata;
  }

  @override
  Future<void> markStoreRemoved() async {
    _storeRemoved = true;
  }

  @override
  Future<bool> wasStoreRemoved() async => _storeRemoved;

  @override
  Future<void> clearStoreRemovedMarker() async {
    _storeRemoved = false;
  }
}

class FileVaultMetadataStore implements VaultMetadataStore {
  FileVaultMetadataStore(this.file);

  factory FileVaultMetadataStore.forConfigPath(String configPath) {
    return FileVaultMetadataStore(File('$configPath.vault_metadata.json'));
  }

  final File file;

  File get _removalMarker => File('${file.path}.store-removed');

  @override
  Future<VaultMetadata> load() async {
    if (!await file.exists()) {
      return const VaultMetadata.empty();
    }
    try {
      return VaultMetadata.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const VaultMetadata.empty();
    }
  }

  @override
  Future<void> save(VaultMetadata metadata) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(metadata.toJson()));
  }

  @override
  Future<void> markStoreRemoved() async {
    final parent = _removalMarker.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await _removalMarker.writeAsString('removed');
  }

  @override
  Future<bool> wasStoreRemoved() => _removalMarker.exists();

  @override
  Future<void> clearStoreRemovedMarker() async {
    if (await _removalMarker.exists()) await _removalMarker.delete();
  }
}
