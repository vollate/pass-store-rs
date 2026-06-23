enum BridgeFailureCategory {
  configError,
  storeError,
  pgpError,
  gitError,
  clipboardError,
  validationError,
  conflict,
  unsupportedPlatform,
  unknown,
}

abstract interface class ParsBridgeApi {
  Future<Map<String, Object?>> loadConfig(Map<String, Object?> request);

  Future<Map<String, Object?>> saveConfig(Map<String, Object?> request);

  Future<Map<String, Object?>> listStores(Map<String, Object?> request);

  Future<Map<String, Object?>> listEntries(Map<String, Object?> request);

  Future<Map<String, Object?>> readEntry(Map<String, Object?> request);

  Future<Map<String, Object?>> copyEntryPassword(Map<String, Object?> request);

  Future<Map<String, Object?>> insertEntry(Map<String, Object?> request);

  Future<Map<String, Object?>> generateEntry(Map<String, Object?> request);

  Future<Map<String, Object?>> editEntry(Map<String, Object?> request);

  Future<Map<String, Object?>> moveEntry(Map<String, Object?> request);

  Future<Map<String, Object?>> deleteEntry(Map<String, Object?> request);

  Future<Map<String, Object?>> gitStatus(Map<String, Object?> request);

  Future<Map<String, Object?>> gitPull(Map<String, Object?> request);

  Future<Map<String, Object?>> gitPush(Map<String, Object?> request);

  Future<Map<String, Object?>> gitCommit(Map<String, Object?> request);

  Future<Map<String, Object?>> runGitArgs(Map<String, Object?> request);
}

class BridgeFailure implements Exception {
  const BridgeFailure({
    required this.category,
    required this.message,
    this.conflictKind,
    this.path,
  });

  factory BridgeFailure.fromJson(Map<String, Object?> json) {
    return BridgeFailure(
      category: _categoryFromRustName(json['category'] as String?),
      message: json['message'] as String? ?? 'Unknown bridge failure',
      conflictKind: json['conflict_kind'] as String?,
      path: json['path'] as String?,
    );
  }

  final BridgeFailureCategory category;
  final String message;
  final String? conflictKind;
  final String? path;

  static BridgeFailureCategory _categoryFromRustName(String? category) {
    switch (category) {
      case 'ConfigError':
        return BridgeFailureCategory.configError;
      case 'StoreError':
        return BridgeFailureCategory.storeError;
      case 'PgpError':
        return BridgeFailureCategory.pgpError;
      case 'GitError':
        return BridgeFailureCategory.gitError;
      case 'ClipboardError':
        return BridgeFailureCategory.clipboardError;
      case 'ValidationError':
        return BridgeFailureCategory.validationError;
      case 'Conflict':
        return BridgeFailureCategory.conflict;
      case 'UnsupportedPlatform':
        return BridgeFailureCategory.unsupportedPlatform;
      default:
        return BridgeFailureCategory.unknown;
    }
  }

  @override
  String toString() => 'BridgeFailure(${category.name}): $message';
}
