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
    this.sshDir,
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
  final String? sshDir;

  StoreLifecycleSnapshot _lifecycle;
  List<PasswordEntry> _entries = const <PasswordEntry>[];
  List<KeyRecord> _keys = const <KeyRecord>[];
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
  List<KeyRecord> get keys => _keys;

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

    final keyResponse = await bridge.listKeys(
      request: frb.ListKeysRequest(
        configPath: configPath,
        pgpExecutable: pgpExecutable,
        sshDir: sshDir,
      ),
    );
    _throwIfFailure(keyResponse.error);
    _keys = keyResponse.keys.map(_keyRecordFromBridge).toList(growable: false);

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

  @override
  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  }) async {
    final response = await bridge.generatePgpKey(
      request: frb.GeneratePgpKeyRequest(
        configPath: configPath,
        pgpExecutable: pgpExecutable,
        name: name,
        email: email,
        passphrase: passphrase,
      ),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async {
    final response = await bridge.importPgpPublicKey(
      request: frb.ImportKeyTextRequest(
        configPath: configPath,
        sshDir: sshDir,
        armoredText: armoredText,
      ),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async {
    final response = await bridge.importPgpPrivateKeyText(
      request: frb.ImportKeyTextRequest(
        configPath: configPath,
        sshDir: sshDir,
        armoredText: armoredText,
      ),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyFile(String path) async {
    final response = await bridge.importPgpPrivateKeyFile(
      request: frb.ImportKeyFileRequest(
        configPath: configPath,
        sshDir: sshDir,
        path: path,
      ),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<String> exportPgpPublicKey(String fingerprint) async {
    final response = await bridge.exportPgpPublicKey(
      request: frb.ExportPgpKeyRequest(
        configPath: configPath,
        pgpExecutable: pgpExecutable,
        fingerprint: fingerprint,
      ),
    );
    return _exportText(response);
  }

  @override
  Future<String> exportPgpPrivateKey({
    required String fingerprint,
    required String confirmation,
  }) async {
    final response = await bridge.exportPgpPrivateKey(
      request: frb.ExportPgpKeyRequest(
        configPath: configPath,
        pgpExecutable: pgpExecutable,
        fingerprint: fingerprint,
        confirmation: confirmation,
      ),
    );
    return _exportText(response);
  }

  @override
  Future<void> addPgpKeyToSelectedStore(String fingerprint) async {
    final root = _lifecycle.selectedStoreRoot;
    if (root == null) {
      throw const BridgeRepositoryException('No selected password store.');
    }
    final response = await bridge.addPgpKeyToGpgId(
      request: frb.AddPgpKeyToGpgIdRequest(
        root: root,
        fingerprint: fingerprint,
      ),
    );
    _throwIfFailure(response.error);
  }

  @override
  Future<KeyRecord> generateSshKey(String name) async {
    final response = await bridge.generateSshKey(
      request: frb.GenerateSshKeyRequest(sshDir: _requiredSshDir(), name: name),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) async {
    final response = await bridge.importSshPrivateKeyText(
      request: frb.ImportKeyTextRequest(
        configPath: configPath,
        sshDir: _requiredSshDir(),
        name: name,
        armoredText: privateKey,
      ),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<KeyRecord> importSshPrivateKeyFile({
    required String name,
    required String path,
  }) async {
    final response = await bridge.importSshPrivateKeyFile(
      request: frb.ImportKeyFileRequest(
        configPath: configPath,
        sshDir: _requiredSshDir(),
        name: name,
        path: path,
      ),
    );
    return _keyFromMutation(response);
  }

  @override
  Future<String> exportSshPublicKey(String name) async {
    final response = await bridge.exportSshPublicKey(
      request: frb.ExportSshKeyRequest(sshDir: _requiredSshDir(), name: name),
    );
    return _exportText(response);
  }

  @override
  Future<String> exportSshPrivateKey({
    required String name,
    required String confirmation,
  }) async {
    final response = await bridge.exportSshPrivateKey(
      request: frb.ExportSshKeyRequest(
        sshDir: _requiredSshDir(),
        name: name,
        confirmation: confirmation,
      ),
    );
    return _exportText(response);
  }

  @override
  Future<Uri> githubSshSettingsUri() async {
    final response = await bridge.openGithubSshSettings(
      request: const frb.OpenGithubSshSettingsRequest(),
    );
    _throwIfFailure(response.error);
    final url = response.url;
    if (url == null) {
      throw const BridgeRepositoryException('Bridge did not return a URL.');
    }
    return Uri.parse(url);
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

  KeyRecord _keyRecordFromBridge(frb.KeyRecordDto key) {
    return KeyRecord(
      type: key.keyType == 'ssh' ? KeyRecordType.ssh : KeyRecordType.pgp,
      name: key.name,
      fingerprint: key.fingerprint,
      source: key.source,
      hasPrivateKey: key.hasPrivateKey,
    );
  }

  KeyRecord _keyFromMutation(frb.KeyMutationResponse response) {
    _throwIfFailure(response.error);
    final key = response.key;
    if (key == null) {
      throw const BridgeRepositoryException('Bridge did not return a key.');
    }
    return _keyRecordFromBridge(key);
  }

  String _exportText(frb.KeyExportResponse response) {
    _throwIfFailure(response.error);
    final export = response.export_;
    if (export == null) {
      throw const BridgeRepositoryException('Bridge did not return key text.');
    }
    return export.armoredText;
  }

  String _requiredSshDir() {
    final dir = sshDir;
    if (dir == null || dir.trim().isEmpty) {
      throw const BridgeRepositoryException(
        'SSH key directory is not configured.',
      );
    }
    return dir;
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
