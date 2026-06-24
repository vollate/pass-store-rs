import 'dart:convert';
import 'dart:io';

class VaultMetadata {
  const VaultMetadata({required this.recentPaths, required this.favoritePaths});

  const VaultMetadata.empty()
    : recentPaths = const <String>[],
      favoritePaths = const <String>{};

  final List<String> recentPaths;
  final Set<String> favoritePaths;

  VaultMetadata copyWith({
    List<String>? recentPaths,
    Set<String>? favoritePaths,
  }) {
    return VaultMetadata(
      recentPaths: recentPaths ?? this.recentPaths,
      favoritePaths: favoritePaths ?? this.favoritePaths,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
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
}

class InMemoryVaultMetadataStore implements VaultMetadataStore {
  VaultMetadata _metadata;

  InMemoryVaultMetadataStore([VaultMetadata? metadata])
    : _metadata = metadata ?? const VaultMetadata.empty();

  @override
  Future<VaultMetadata> load() async => _metadata;

  @override
  Future<void> save(VaultMetadata metadata) async {
    _metadata = metadata;
  }
}

class FileVaultMetadataStore implements VaultMetadataStore {
  FileVaultMetadataStore(this.file);

  factory FileVaultMetadataStore.forConfigPath(String configPath) {
    return FileVaultMetadataStore(File('$configPath.vault_metadata.json'));
  }

  final File file;

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
}
