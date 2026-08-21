import 'dart:convert';
import 'dart:io';

class VaultMetadata {
  const VaultMetadata({
    required this.recentPaths,
    required this.favoritePaths,
    this.storeRoot,
    this.removalTombstone = false,
  });

  const VaultMetadata.empty({this.storeRoot, this.removalTombstone = false})
    : recentPaths = const <String>[],
      favoritePaths = const <String>{};

  const VaultMetadata.removed()
    : recentPaths = const <String>[],
      favoritePaths = const <String>{},
      storeRoot = '',
      removalTombstone = true;

  final List<String> recentPaths;
  final Set<String> favoritePaths;
  final String? storeRoot;
  final bool removalTombstone;

  VaultMetadata copyWith({
    List<String>? recentPaths,
    Set<String>? favoritePaths,
    String? storeRoot,
    bool? removalTombstone,
  }) {
    return VaultMetadata(
      recentPaths: recentPaths ?? this.recentPaths,
      favoritePaths: favoritePaths ?? this.favoritePaths,
      storeRoot: storeRoot ?? this.storeRoot,
      removalTombstone: removalTombstone ?? this.removalTombstone,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'storeRoot': storeRoot,
      'removalTombstone': removalTombstone,
      'recentPaths': recentPaths,
      'favoritePaths': favoritePaths.toList()..sort(),
    };
  }

  static VaultMetadata fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const VaultMetadata.empty();
    }
    final recent = value['recentPaths'];
    final favorites = value['favoritePaths'];
    return VaultMetadata(
      storeRoot:
          value['storeRoot'] is String ? value['storeRoot'] as String : null,
      removalTombstone: value['removalTombstone'] == true,
      recentPaths:
          recent is List
              ? recent.whereType<String>().toList(growable: false)
              : const <String>[],
      favoritePaths:
          favorites is List
              ? favorites.whereType<String>().toSet()
              : const <String>{},
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
