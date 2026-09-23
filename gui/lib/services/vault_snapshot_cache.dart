import 'dart:convert';
import 'dart:io';

import '../models/password_entry.dart';
import 'store_lifecycle.dart';

/// First-paint snapshot of the vault, persisted so startup can render the list
/// before the bridge finishes rescanning the store.
class VaultSnapshot {
  static const int currentVersion = 1;

  const VaultSnapshot({
    required this.lifecycle,
    required this.entries,
    required this.gitStatus,
  });

  final StoreLifecycleSnapshot lifecycle;
  final List<PasswordEntry> entries;
  final RepoGitStatus gitStatus;

  Map<String, Object?> toJson() {
    final store = lifecycle.store;
    return <String, Object?>{
      'version': currentVersion,
      'configPath': lifecycle.configPath,
      'configExists': lifecycle.configExists,
      'onboardingState': lifecycle.onboardingState.name,
      'issues': lifecycle.issues,
      'gitStatus': gitStatus.name,
      'store':
          store == null
              ? null
              : <String, Object?>{
                'name': store.name,
                'root': store.root,
                'exists': store.exists,
                'hasGpgId': store.hasGpgId,
                'pgpRecipients': store.pgpRecipients,
                'pgpKeyMissing': store.pgpKeyMissing,
                'issues': store.issues,
                'gitMode': store.gitMode.name,
              },
      'entries': entries
          .map(
            (entry) => <String, Object?>{
              'path': entry.path,
              'displayName': entry.displayName,
              'repoName': entry.repoName,
              'isDirectory': entry.isDirectory,
              'childCount': entry.childCount,
            },
          )
          .toList(growable: false),
    };
  }

  /// Returns null when the payload is absent, from another version, or
  /// malformed, so a bad cache degrades to a normal cold scan.
  static VaultSnapshot? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    if (value['version'] != currentVersion) return null;
    final configPath = value['configPath'];
    if (configPath is! String) return null;

    final storeJson = value['store'];
    StoreStatus? store;
    if (storeJson is Map<String, Object?>) {
      final name = storeJson['name'];
      final root = storeJson['root'];
      if (name is! String || root is! String) return null;
      store = StoreStatus(
        name: name,
        root: root,
        exists: storeJson['exists'] == true,
        hasGpgId: storeJson['hasGpgId'] == true,
        pgpRecipients: _stringList(storeJson['pgpRecipients']),
        pgpKeyMissing: storeJson['pgpKeyMissing'] == true,
        issues: _stringList(storeJson['issues']),
        gitMode: _enumByName(
          StoreGitMode.values,
          storeJson['gitMode'],
          StoreGitMode.disabled,
        ),
      );
    }

    final entriesJson = value['entries'];
    final entries = <PasswordEntry>[];
    if (entriesJson is List) {
      for (final raw in entriesJson) {
        if (raw is! Map<String, Object?>) continue;
        final path = raw['path'];
        final displayName = raw['displayName'];
        final repoName = raw['repoName'];
        if (path is! String || displayName is! String || repoName is! String) {
          continue;
        }
        entries.add(
          PasswordEntry(
            path: path,
            displayName: displayName,
            repoName: repoName,
            encryptedContent: '',
            isDirectory: raw['isDirectory'] == true,
            childCount: raw['childCount'] is int ? raw['childCount'] as int : 0,
          ),
        );
      }
    }

    return VaultSnapshot(
      lifecycle: StoreLifecycleSnapshot(
        configPath: configPath,
        configExists: value['configExists'] == true,
        onboardingState: _enumByName(
          StoreOnboardingState.values,
          value['onboardingState'],
          StoreOnboardingState.storeMissing,
        ),
        issues: _stringList(value['issues']),
        store: store,
      ),
      entries: List<PasswordEntry>.unmodifiable(entries),
      gitStatus: _enumByName(
        RepoGitStatus.values,
        value['gitStatus'],
        RepoGitStatus.disabled,
      ),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

abstract interface class VaultSnapshotCache {
  Future<VaultSnapshot?> load();

  Future<void> save(VaultSnapshot snapshot);

  Future<void> clear();
}

class InMemoryVaultSnapshotCache implements VaultSnapshotCache {
  InMemoryVaultSnapshotCache([this._snapshot]);

  VaultSnapshot? _snapshot;

  @override
  Future<VaultSnapshot?> load() async => _snapshot;

  @override
  Future<void> save(VaultSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<void> clear() async => _snapshot = null;
}

class FileVaultSnapshotCache implements VaultSnapshotCache {
  FileVaultSnapshotCache(this.file);

  factory FileVaultSnapshotCache.forConfigPath(String configPath) {
    return FileVaultSnapshotCache(File('$configPath.vault_cache.json'));
  }

  final File file;

  @override
  Future<VaultSnapshot?> load() async {
    try {
      if (!await file.exists()) return null;
      return VaultSnapshot.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(VaultSnapshot snapshot) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }
}
