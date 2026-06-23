import 'dart:io';

import '../bridge/frb_generated/api.dart' as frb;
import '../bridge/pars_bridge_api.dart';
import '../models/key_record.dart';
import '../models/password_entry.dart';
import 'git_repository.dart';
import 'key_repository.dart';
import 'settings_repository.dart';
import 'store_lifecycle.dart';
import 'vault_repository.dart';

class BridgeRepositoryException implements Exception {
  const BridgeRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BridgeBackedRepository
    implements
        VaultRepository,
        SettingsRepository,
        KeyRepository,
        GitRepository {
  BridgeBackedRepository({
    required this.bridge,
    required this.configPath,
    this.pgpExecutable,
  }) : _lifecycle = StoreLifecycleSnapshot.empty(configPath);

  factory BridgeBackedRepository.defaultInstance() {
    return BridgeBackedRepository(
      bridge: const FrbParsBridgeApi(),
      configPath: defaultConfigPath(),
    );
  }

  final ParsBridgeApi bridge;
  final String configPath;
  final String? pgpExecutable;

  StoreLifecycleSnapshot _lifecycle;
  List<PasswordEntry> _entries = const <PasswordEntry>[];
  RepoGitStatus _gitStatus = RepoGitStatus.syncFailed;

  @override
  StoreLifecycleSnapshot get lifecycle => _lifecycle;

  @override
  List<StoreStatus> get stores => _lifecycle.stores;

  @override
  String get currentRepoName {
    final store = _lifecycle.selectedStore;
    if (store == null) {
      return 'No store selected';
    }
    return store.name;
  }

  @override
  RepoGitStatus get gitStatus => _gitStatus;

  @override
  List<PasswordEntry> get entries => _entries;

  @override
  List<KeyRecord> get keys => const <KeyRecord>[];

  @override
  Future<void> refresh() async {
    final stateResponse = await bridge.inspectAppState(
      request: frb.InspectAppStateRequest(
        configPath: configPath,
        pgpExecutable: pgpExecutable,
      ),
    );
    _throwIfFailure(stateResponse.error);
    final state = stateResponse.state;
    if (state == null) {
      throw const BridgeRepositoryException('Bridge did not return app state.');
    }
    _lifecycle = StoreLifecycleSnapshot.fromBridge(state);

    final selected = _lifecycle.selectedStore;
    if (selected == null || !selected.exists) {
      _entries = const <PasswordEntry>[];
      _gitStatus = RepoGitStatus.syncFailed;
      return;
    }

    final entriesResponse = await bridge.listEntries(
      request: frb.ListEntriesRequest(
        root: selected.root,
        target: null,
        recursive: true,
      ),
    );
    _throwIfFailure(entriesResponse.error);
    _entries = entriesResponse.entries
        .map((entry) => _passwordEntryFromBridge(entry, selected))
        .toList(growable: false);

    final gitResponse = await bridge.gitStatus(
      request: frb.GitRequest(root: selected.root),
    );
    _gitStatus = _gitStatusFromBridge(gitResponse);
  }

  @override
  List<PasswordEntry> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) =>
              entry.displayName.toLowerCase().contains(normalized) ||
              entry.path.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  Future<void> selectStore(String root) async {
    final response = await bridge.selectStore(
      request: frb.SelectStoreRequest(configPath: configPath, root: root),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool setDefault,
    required bool initializeGit,
  }) async {
    final response = await bridge.createLocalStore(
      request: frb.CreateLocalStoreRequest(
        configPath: configPath,
        name: name,
        root: root,
        pgpKeys: pgpKeys,
        setDefault: setDefault,
        initializeGit: initializeGit,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<void> importLocalStore({
    required String root,
    required bool setDefault,
  }) async {
    final response = await bridge.importLocalStore(
      request: frb.ImportLocalStoreRequest(
        configPath: configPath,
        root: root,
        setDefault: setDefault,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    required bool setDefault,
  }) async {
    final response = await bridge.cloneStore(
      request: frb.CloneStoreRequest(
        configPath: configPath,
        remoteUrl: remoteUrl,
        root: root,
        setDefault: setDefault,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<void> removeStore({required String root}) async {
    final response = await bridge.removeStore(
      request: frb.RemoveStoreRequest(configPath: configPath, root: root),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {
    final response = await bridge.deleteLocalStore(
      request: frb.DeleteLocalStoreRequest(
        configPath: configPath,
        root: root,
        confirmation: confirmation,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  static String defaultConfigPath() {
    final explicit = Platform.environment['PARS_CONFIG'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit;
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.trim().isNotEmpty) {
      return '$home/.config/pars/pars_config.toml';
    }
    return 'pars_config.toml';
  }

  PasswordEntry _passwordEntryFromBridge(
    frb.EntrySummaryDto entry,
    StoreStatus store,
  ) {
    final isDirectory = entry.entryType == 'Directory';
    return PasswordEntry(
      path: entry.path,
      displayName: entry.name,
      repoName: store.name,
      encryptedContent: '',
      isDirectory: isDirectory,
      childCount: entry.childCount,
    );
  }

  RepoGitStatus _gitStatusFromBridge(frb.GitCommandResponse response) {
    if (response.error != null) {
      return RepoGitStatus.syncFailed;
    }
    final output = response.output;
    if (output == null || !output.success) {
      return RepoGitStatus.syncFailed;
    }
    if (output.stdout.contains('behind')) {
      return RepoGitStatus.needPull;
    }
    final lines = output.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.any((line) => !line.startsWith('##'))) {
      return RepoGitStatus.uncommitted;
    }
    return RepoGitStatus.clean;
  }

  void _throwIfFailure(frb.BridgeFailure? failure) {
    if (failure != null) {
      throw BridgeRepositoryException(failure.message);
    }
  }
}
