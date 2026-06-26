import 'dart:io';
import 'dart:math';

import '../bridge/frb_generated/api.dart' as frb;
import '../bridge/pars_bridge_api.dart';
import '../models/key_record.dart';
import '../models/password_entry.dart';
import 'git_repository.dart';
import 'key_repository.dart';
import 'runtime_diagnostics.dart';
import 'security_repository.dart';
import 'settings_repository.dart';
import 'store_lifecycle.dart';
import 'vault_metadata_store.dart';
import 'vault_repository.dart';

class BridgeRepositoryException implements Exception {
  const BridgeRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BridgeBackedRepository
    implements
        ManageRepository,
        SettingsRepository,
        KeyRepository,
        RuntimeDiagnosticsRepository,
        GitOperationsRepository,
        AppManagedPathRepository {
  BridgeBackedRepository({
    required this.bridge,
    required this.configPath,
    this.pgpExecutable,
    this.pgpBackendLabel,
    this.sshDir,
    this.managedStoreBaseDir,
    VaultMetadataStore? metadataStore,
  }) : _metadataStore =
           metadataStore ?? FileVaultMetadataStore.forConfigPath(configPath),
       _lifecycle = StoreLifecycleSnapshot.empty(configPath);

  factory BridgeBackedRepository.defaultInstance({
    String? pgpExecutable,
    String? pgpBackendLabel,
    String? sshDir,
    String? managedStoreBaseDir,
  }) {
    return BridgeBackedRepository(
      bridge: const FrbParsBridgeApi(),
      configPath: defaultConfigPath(),
      pgpExecutable: pgpExecutable,
      pgpBackendLabel: pgpBackendLabel,
      sshDir: sshDir,
      managedStoreBaseDir: managedStoreBaseDir,
    );
  }

  final ParsBridgeApi bridge;
  final String configPath;
  final String? pgpExecutable;
  final String? pgpBackendLabel;
  final String? sshDir;
  final String? managedStoreBaseDir;
  final VaultMetadataStore _metadataStore;

  StoreLifecycleSnapshot _lifecycle;
  List<PasswordEntry> _entries = const <PasswordEntry>[];
  List<KeyRecord> _keys = const <KeyRecord>[];
  RepoGitStatus _gitStatus = RepoGitStatus.syncFailed;
  VaultMetadata _metadata = const VaultMetadata.empty();

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
  bool get usesAppManagedPaths =>
      managedStoreBaseDir != null && managedStoreBaseDir!.trim().isNotEmpty;

  @override
  String storeRootForName(String name) {
    return _joinFilesystemPath(
      _requiredManagedStoreBaseDir(),
      _slugPathSegment(name),
    );
  }

  @override
  String storeRootForRemote(String remoteUrl) {
    final withoutQuery = remoteUrl.trim().split('?').first.split('#').first;
    final normalized = withoutQuery.replaceAll(RegExp(r'/+$'), '');
    final lastSegment = normalized.split(RegExp(r'[:/\\]')).last;
    final withoutGitSuffix = lastSegment.replaceFirst(
      RegExp(r'\.git$', caseSensitive: false),
      '',
    );
    return _joinFilesystemPath(
      _requiredManagedStoreBaseDir(),
      _slugPathSegment(withoutGitSuffix),
    );
  }

  @override
  RuntimeDiagnostics runtimeDiagnostics(SecurityRepository securityRepository) {
    return RuntimeDiagnostics(
      bridgeLoaded: true,
      coreVersion: 'pars-core 0.2.5',
      pgpBackend: pgpBackendLabel ?? _pgpBackendLabel(),
      gitBackend: 'System git command',
      keyStorageBackend: keyStorageBackendLabel(securityRepository),
      nativeLibrary: 'pars_bridge',
    );
  }

  @override
  Future<void> refresh() async {
    final stateResponse = await bridge.inspectAppState(
      request: frb.InspectAppStateRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
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
        pgpExecutable: _optionalPgpExecutable(),
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

    _metadata = await _metadataStore.load();
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
  List<PasswordEntry> browseEntries(String? directoryPath) {
    final parent = _normalizedBrowseParent(directoryPath);
    final browsed = entries
        .where((entry) => entry.parentPath == parent)
        .toList(growable: false);
    return _sortBrowseEntries(browsed);
  }

  @override
  List<PasswordEntry> recentEntries() {
    final byPath = <String, PasswordEntry>{
      for (final entry in entries)
        if (!entry.isDirectory) entry.path: entry,
    };
    final recent = _metadata.recentPaths
        .map((path) => byPath[path])
        .whereType<PasswordEntry>()
        .toList(growable: false);
    if (recent.isNotEmpty) {
      return recent;
    }
    return entries.where((entry) => !entry.isDirectory).toList(growable: false);
  }

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    final response = await bridge.readEntry(request: _entryRequest(entry));
    _throwIfFailure(response.error);
    final secret = response.secret;
    if (secret == null) {
      throw const BridgeRepositoryException('Bridge did not return an entry.');
    }
    await _rememberEntry(entry.path);
    return _secretFromBridge(secret);
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async {
    final response = await bridge.copyEntryPassword(
      request: _entryRequest(entry),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return a copied password.',
      );
    }
    await _rememberEntry(entry.path);
    return result.password;
  }

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {
    final favorites = _metadata.favoritePaths.toSet();
    if (!favorites.add(entry.path)) {
      favorites.remove(entry.path);
    }
    await _saveMetadata(_metadata.copyWith(favoritePaths: favorites));
  }

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async {
    final response = await bridge.generateEntry(
      request: frb.GenerateEntryRequest(
        configPath: configPath,
        root: _requiredStoreRoot(),
        path: path,
        length: length,
        noSymbols: noSymbols,
        overwrite: overwrite,
        pgpExecutable: _pgpExecutable(),
      ),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return a generated entry result.',
      );
    }
    await refresh();
    return EntryOperationResult(
      path: result.entryPath,
      overwroteExisting: result.overwroteExisting,
    );
  }

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async {
    final response = await bridge.insertEntry(
      request: frb.InsertEntryRequest(
        configPath: configPath,
        root: _requiredStoreRoot(),
        path: path,
        content: content,
        overwrite: overwrite,
        pgpExecutable: _pgpExecutable(),
      ),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return a saved entry result.',
      );
    }
    await refresh();
    return EntryOperationResult(
      path: result.entryPath,
      overwroteExisting: result.overwroteExisting,
    );
  }

  @override
  Future<EntryOperationResult> editEntry({
    required String path,
    required String content,
  }) async {
    final response = await bridge.editEntry(
      request: frb.EditEntryRequest(
        configPath: configPath,
        root: _requiredStoreRoot(),
        path: path,
        content: content,
        pgpExecutable: _pgpExecutable(),
      ),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return an edited entry result.',
      );
    }
    await refresh();
    return EntryOperationResult(
      path: result.path,
      overwroteExisting: true,
      action: 'Edited',
    );
  }

  @override
  Future<EntryOperationResult> replaceEntryPassword({
    required PasswordEntry entry,
    required String password,
  }) async {
    final secret = await readEntry(entry);
    final result = await editEntry(
      path: entry.path,
      content: _entryContent(password, secret.fields, secret.rawNotes),
    );
    return result.copyWith(action: 'Replaced password for');
  }

  @override
  Future<EntryOperationResult> moveEntry({
    required String fromPath,
    required String toPath,
    required bool overwrite,
  }) async {
    final response = await bridge.moveEntry(
      request: frb.MoveEntryRequest(
        root: _requiredStoreRoot(),
        fromPath: fromPath,
        toPath: toPath,
        overwrite: overwrite,
      ),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return a moved entry result.',
      );
    }
    await refresh();
    return EntryOperationResult(
      path: result.path,
      overwroteExisting: overwrite,
      action: 'Moved',
    );
  }

  @override
  Future<EntryOperationResult> deleteEntry({
    required String path,
    required bool recursive,
  }) async {
    final response = await bridge.deleteEntry(
      request: frb.DeleteEntryRequest(
        root: _requiredStoreRoot(),
        path: path,
        recursive: recursive,
      ),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return a deleted entry result.',
      );
    }
    await refresh();
    return EntryOperationResult(
      path: result.deletedPath,
      overwroteExisting: false,
      action: 'Deleted',
    );
  }

  @override
  Future<BatchOperationResult> batchMoveEntries({
    required List<PasswordEntry> entries,
    required String destinationDirectory,
    required bool overwrite,
  }) async {
    final destination = destinationDirectory.trim();
    return _runBatch('Moved', entries, (entry) {
      final target = _joinEntryPath(destination, _basename(entry.path));
      return moveEntry(
        fromPath: entry.path,
        toPath: target,
        overwrite: overwrite,
      );
    });
  }

  @override
  Future<BatchOperationResult> batchRenameEntries({
    required List<PasswordEntry> entries,
    required String prefix,
    required String suffix,
    required bool overwrite,
  }) async {
    return _runBatch('Renamed', entries, (entry) {
      final parent = _dirname(entry.path);
      final name = '${prefix.trim()}${_basename(entry.path)}${suffix.trim()}';
      return moveEntry(
        fromPath: entry.path,
        toPath: _joinEntryPath(parent, name),
        overwrite: overwrite,
      );
    });
  }

  @override
  Future<BatchOperationResult> batchDeleteEntries({
    required List<PasswordEntry> entries,
  }) async {
    return _runBatch('Deleted', entries, (entry) {
      return deleteEntry(path: entry.path, recursive: entry.isDirectory);
    });
  }

  @override
  Future<BatchOperationResult> batchRegenerateEntries({
    required List<PasswordEntry> entries,
    required int length,
    required bool noSymbols,
  }) async {
    return _runBatch('Regenerated', entries, (entry) async {
      final password = _generatePassword(length: length, noSymbols: noSymbols);
      return replaceEntryPassword(entry: entry, password: password);
    });
  }

  @override
  Future<GitOperationResult> commitChanges(String message) async {
    return commit(message.trim().isEmpty ? 'Update password store' : message);
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
        initializeGit: initializeGit && !usesAppManagedPaths,
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
        pgpExecutable: _optionalPgpExecutable(),
        name: name,
        email: email,
        passphrase: passphrase,
      ),
    );
    return _recordKeyMutation(response);
  }

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async {
    final response = await bridge.importPgpPublicKey(
      request: frb.ImportKeyTextRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        sshDir: sshDir,
        armoredText: armoredText,
      ),
    );
    return _recordKeyMutation(response);
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async {
    final response = await bridge.importPgpPrivateKeyText(
      request: frb.ImportKeyTextRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        sshDir: sshDir,
        armoredText: armoredText,
      ),
    );
    return _recordKeyMutation(response);
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyFile(String path) async {
    final response = await bridge.importPgpPrivateKeyFile(
      request: frb.ImportKeyFileRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        sshDir: sshDir,
        path: path,
      ),
    );
    return _recordKeyMutation(response);
  }

  @override
  Future<String> exportPgpPublicKey(String fingerprint) async {
    final response = await bridge.exportPgpPublicKey(
      request: frb.ExportPgpKeyRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
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
        pgpExecutable: _optionalPgpExecutable(),
        fingerprint: fingerprint,
        confirmation: confirmation,
      ),
    );
    return _exportText(response);
  }

  @override
  Future<void> deletePgpKey(String fingerprint) async {
    final response = await bridge.deletePgpKey(
      request: frb.DeletePgpKeyRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        fingerprint: fingerprint,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
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
    return _recordKeyMutation(response);
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
    return _recordKeyMutation(response);
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
    return _recordKeyMutation(response);
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
  Future<void> deleteSshKey(String name) async {
    final response = await bridge.deleteSshKey(
      request: frb.DeleteSshKeyRequest(sshDir: _requiredSshDir(), name: name),
    );
    _throwIfFailure(response.error);
    await refresh();
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

  @override
  Future<GitOperationResult> refreshGitStatus() async {
    final response = await bridge.gitStatus(
      request: frb.GitRequest(root: _requiredStoreRoot()),
    );
    _gitStatus = _gitStatusFromBridge(response);
    return _gitResultFromBridge(response);
  }

  @override
  Future<GitOperationResult> pull() async {
    final response = await bridge.gitPull(
      request: frb.GitRequest(root: _requiredStoreRoot()),
    );
    final result = _gitResultFromBridge(response);
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> push() async {
    final response = await bridge.gitPush(
      request: frb.GitRequest(root: _requiredStoreRoot()),
    );
    final result = _gitResultFromBridge(response);
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> commit(String message) async {
    final response = await bridge.gitCommit(
      request: frb.GitCommitRequest(
        root: _requiredStoreRoot(),
        message: message.trim().isEmpty ? 'Update password store' : message,
      ),
    );
    final result = _gitResultFromBridge(response);
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> runArgs(List<String> args) async {
    final response = await bridge.runGitArgs(
      request: frb.GitArgsRequest(root: _requiredStoreRoot(), args: args),
    );
    return _gitResultFromBridge(response);
  }

  @override
  Future<List<GitRemote>> listRemotes() async {
    final result = await runArgs(const <String>['remote', '-v']);
    return _parseRemotes(result.stdout);
  }

  @override
  Future<GitOperationResult> addRemote({
    required String name,
    required String url,
  }) {
    return runArgs(<String>['remote', 'add', name.trim(), url.trim()]);
  }

  @override
  Future<GitOperationResult> editRemote({
    required String name,
    required String url,
  }) {
    return runArgs(<String>['remote', 'set-url', name.trim(), url.trim()]);
  }

  @override
  Future<GitOperationResult> removeRemote(String name) {
    return runArgs(<String>['remote', 'remove', name.trim()]);
  }

  @override
  Future<GitOperationResult> autoPullOnOpen() async {
    final store = _lifecycle.selectedStore;
    if (store == null || !store.hasGitRemote) {
      return const GitOperationResult(
        command: 'git pull',
        stdout: 'Skipped: no selected git remote.',
        stderr: '',
        exitCode: 0,
        success: true,
      );
    }
    return pull();
  }

  @override
  Future<GitOperationResult> recoverByPull() {
    return pull();
  }

  @override
  Future<GitOperationResult> deleteLocalRepo({
    required String confirmation,
  }) async {
    final root = _requiredStoreRoot();
    await deleteLocalStore(root: root, confirmation: confirmation);
    return const GitOperationResult(
      command: 'delete local repo',
      stdout: 'Deleted local repository.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
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

  Future<BatchOperationResult> _runBatch(
    String action,
    List<PasswordEntry> entries,
    Future<EntryOperationResult> Function(PasswordEntry entry) operation,
  ) async {
    final affected = <String>[];
    final failures = <BatchOperationFailure>[];
    for (final entry in entries) {
      try {
        final result = await operation(entry);
        affected.add(result.path);
      } catch (error) {
        failures.add(
          BatchOperationFailure(path: entry.path, message: error.toString()),
        );
      }
    }
    return BatchOperationResult(
      action: action,
      affectedPaths: affected,
      failures: failures,
    );
  }

  String _entryContent(
    String password,
    List<ParsedSecretField> fields,
    String rawNotes,
  ) {
    final lines = <String>[password];
    for (final field in fields) {
      lines.add('${field.key}: ${field.value}');
    }
    final notes = rawNotes.trim();
    if (notes.isNotEmpty) {
      lines.add(notes);
    }
    return lines.join('\n');
  }

  String _generatePassword({required int length, required bool noSymbols}) {
    const letters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
    const numbers = '23456789';
    const symbols = '!@#%^*-_=+?';
    final alphabet = '$letters$numbers${noSymbols ? '' : symbols}';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _basename(String path) {
    final index = path.lastIndexOf('/');
    return index == -1 ? path : path.substring(index + 1);
  }

  String _dirname(String path) {
    final index = path.lastIndexOf('/');
    return index == -1 ? '' : path.substring(0, index);
  }

  String _joinEntryPath(String parent, String child) {
    final trimmedParent = parent.trim();
    final trimmedChild = child.trim();
    if (trimmedParent.isEmpty) {
      return trimmedChild;
    }
    return '$trimmedParent/$trimmedChild';
  }

  String _joinFilesystemPath(String parent, String child) {
    final trimmedParent = parent.trim();
    final trimmedChild = child.trim();
    final separator = Platform.pathSeparator;
    if (trimmedParent.endsWith(separator)) {
      return '$trimmedParent$trimmedChild';
    }
    return '$trimmedParent$separator$trimmedChild';
  }

  String _slugPathSegment(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'password-store' : slug;
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
      isFavorite: _metadata.favoritePaths.contains(entry.path),
      lastUsedLabel: _lastUsedLabel(entry.path),
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

  KeyRecord _recordKeyMutation(frb.KeyMutationResponse response) {
    final key = _keyFromMutation(response);
    _upsertKey(key);
    return key;
  }

  void _upsertKey(KeyRecord key) {
    _keys = <KeyRecord>[
      for (final existing in _keys)
        if (!_matchesKeyIdentity(existing, key)) existing,
      key,
    ];
  }

  bool _matchesKeyIdentity(KeyRecord existing, KeyRecord key) {
    if (existing.type != key.type) {
      return false;
    }
    if (existing.fingerprint == key.fingerprint) {
      return true;
    }
    return key.type == KeyRecordType.ssh && existing.name == key.name;
  }

  SecretContent _secretFromBridge(frb.EntrySecretDto secret) {
    return SecretContent(
      password: secret.password,
      fields: secret.fields
          .map(
            (field) => ParsedSecretField(
              key: field.key,
              label: field.label,
              value: field.value,
            ),
          )
          .toList(growable: false),
      rawNotes: secret.rawNotes,
    );
  }

  frb.EntryRequest _entryRequest(PasswordEntry entry) {
    return frb.EntryRequest(
      configPath: configPath,
      root: _requiredStoreRoot(),
      path: entry.path,
      pgpExecutable: pgpExecutable,
    );
  }

  String _requiredStoreRoot() {
    final root = _lifecycle.selectedStoreRoot;
    if (root == null) {
      throw const BridgeRepositoryException('No selected password store.');
    }
    return root;
  }

  String _pgpExecutable() {
    final executable = pgpExecutable?.trim();
    return executable == null || executable.isEmpty ? 'gpg' : executable;
  }

  String? _optionalPgpExecutable() {
    final executable = pgpExecutable?.trim();
    return executable == null || executable.isEmpty ? null : executable;
  }

  String _pgpBackendLabel() {
    final executable = pgpExecutable?.trim();
    if (executable == null || executable.isEmpty) {
      return 'System GPG from PATH';
    }
    return 'System GPG at $executable';
  }

  String _normalizedBrowseParent(String? directoryPath) {
    final path = directoryPath?.trim();
    if (path == null || path.isEmpty) {
      return currentRepoName;
    }
    return path;
  }

  List<PasswordEntry> _sortBrowseEntries(List<PasswordEntry> entries) {
    final sorted = entries.toList();
    sorted.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
    });
    return sorted;
  }

  String? _lastUsedLabel(String path) {
    final index = _metadata.recentPaths.indexOf(path);
    if (index == -1) {
      return null;
    }
    return index == 0 ? 'Recent' : 'Recent ${index + 1}';
  }

  Future<void> _rememberEntry(String path) async {
    final recent = <String>[
      path,
      ..._metadata.recentPaths.where((recentPath) => recentPath != path),
    ].take(20).toList(growable: false);
    await _saveMetadata(_metadata.copyWith(recentPaths: recent));
  }

  Future<void> _saveMetadata(VaultMetadata metadata) async {
    _metadata = metadata;
    await _metadataStore.save(metadata);
    _entries = _entries.map(_decorateEntry).toList(growable: false);
  }

  PasswordEntry _decorateEntry(PasswordEntry entry) {
    return PasswordEntry(
      path: entry.path,
      displayName: entry.displayName,
      repoName: entry.repoName,
      encryptedContent: entry.encryptedContent,
      isDirectory: entry.isDirectory,
      childCount: entry.childCount,
      isFavorite: _metadata.favoritePaths.contains(entry.path),
      lastUsedLabel: _lastUsedLabel(entry.path),
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

  String _requiredManagedStoreBaseDir() {
    final dir = managedStoreBaseDir;
    if (dir == null || dir.trim().isEmpty) {
      throw const BridgeRepositoryException(
        'Managed store directory is not configured.',
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

  GitOperationResult _gitResultFromBridge(frb.GitCommandResponse response) {
    _throwIfFailure(response.error);
    final output = response.output;
    if (output == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return git output.',
      );
    }
    return GitOperationResult(
      command: output.command,
      stdout: output.stdout,
      stderr: output.stderr,
      exitCode: output.exitCode,
      success: output.success,
    );
  }

  List<GitRemote> _parseRemotes(String stdout) {
    final byName = <String, ({String fetchUrl, String pushUrl})>{};
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 3) {
        continue;
      }
      final name = parts[0];
      final url = parts[1];
      final kind = parts[2];
      final existing = byName[name] ?? (fetchUrl: '', pushUrl: '');
      byName[name] =
          kind == '(push)'
              ? (fetchUrl: existing.fetchUrl, pushUrl: url)
              : (fetchUrl: url, pushUrl: existing.pushUrl);
    }
    return byName.entries
        .map(
          (entry) => GitRemote(
            name: entry.key,
            fetchUrl: entry.value.fetchUrl,
            pushUrl:
                entry.value.pushUrl.isEmpty
                    ? entry.value.fetchUrl
                    : entry.value.pushUrl,
          ),
        )
        .toList(growable: false);
  }

  void _throwIfFailure(frb.BridgeFailure? failure) {
    if (failure != null) {
      throw BridgeRepositoryException(failure.message);
    }
  }
}
