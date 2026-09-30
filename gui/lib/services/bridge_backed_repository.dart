import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../bridge/frb_generated/api.dart' as frb;
import '../bridge/pars_bridge_api.dart';
import '../models/key_record.dart';
import '../models/password_entry.dart';
import '../models/pgp_key_import.dart';
import '../models/git_sync.dart';
import 'autofill_repository.dart';
import 'git_credential_store.dart';
import 'git_preferences.dart';
import 'git_repository.dart';
import 'path_picker_service.dart';
import 'selected_ssh_key.dart';
import 'key_repository.dart';
import 'runtime_diagnostics.dart';
import 'security_repository.dart';
import 'settings_repository.dart';
import 'store_lifecycle.dart';
import 'vault_metadata_store.dart';
import 'vault_repository.dart';
import 'vault_snapshot_cache.dart';

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
        AppManagedPathRepository,
        StoreLifecycleChangeSource {
  BridgeBackedRepository({
    required this.bridge,
    required this.configPath,
    this.pgpExecutable,
    this.pgpBackendLabel,
    this.sshDir,
    this.managedStoreBaseDir,
    this.securityRepository,
    this.autofillRepository,
    VaultMetadataStore? metadataStore,
    VaultSnapshotCache? snapshotCache,
    GitCredentialStore? gitCredentials,
  }) : _metadataStore =
           metadataStore ?? FileVaultMetadataStore.forConfigPath(configPath),
       _snapshotCache =
           snapshotCache ?? FileVaultSnapshotCache.forConfigPath(configPath),
       _gitCredentials = gitCredentials ?? GitCredentialStore(null),
       _lifecycle = StoreLifecycleSnapshot.empty(configPath);

  factory BridgeBackedRepository.defaultInstance({
    String? pgpExecutable,
    String? pgpBackendLabel,
    String? sshDir,
    String? managedStoreBaseDir,
    SecurityRepository? securityRepository,
    AutofillRepository? autofillRepository,
  }) {
    return BridgeBackedRepository(
      bridge: const FrbParsBridgeApi(),
      configPath: defaultConfigPath(),
      pgpExecutable: pgpExecutable,
      pgpBackendLabel: pgpBackendLabel,
      sshDir: sshDir,
      managedStoreBaseDir: managedStoreBaseDir,
      securityRepository: securityRepository,
      autofillRepository: autofillRepository,
    );
  }

  final ParsBridgeApi bridge;
  final String configPath;
  final String? pgpExecutable;
  final String? pgpBackendLabel;
  final String? sshDir;
  final String? managedStoreBaseDir;
  final SecurityRepository? securityRepository;
  final AutofillRepository? autofillRepository;
  final VaultMetadataStore _metadataStore;
  final VaultSnapshotCache _snapshotCache;
  final GitCredentialStore _gitCredentials;

  StoreLifecycleSnapshot _lifecycle;
  List<PasswordEntry> _entries = const <PasswordEntry>[];
  List<KeyRecord> _keys = const <KeyRecord>[];
  RepoGitStatus _gitStatus = RepoGitStatus.disabled;
  GitStatusSummary? _statusSummary;
  GitSyncConflict? _lastConflict;
  bool _lastSyncFailed = false;
  bool _lastRemoteCheckFailed = false;
  bool _launchCheckDone = false;
  GitPreferences _gitPreferences = const GitPreferences();
  HttpsCredentials? _pendingHttps;
  ({String passphrase, bool persist})? _pendingSshPassphrase;
  int _refreshEpoch = 0;
  Future<void> _storeSideEffectTail = Future<void>.value();
  bool _storeRemovalInProgress = false;
  final ValueNotifier<int> _lifecycleRevision = ValueNotifier<int>(0);
  String? _publishedLifecycleIdentity;

  @override
  StoreLifecycleSnapshot get lifecycle => _lifecycle;

  @override
  ValueListenable<int> get lifecycleRevision => _lifecycleRevision;

  @override
  bool get storeRemovalInProgress => _storeRemovalInProgress;

  @override
  StoreStatus? get store => _lifecycle.store;

  @override
  String get currentRepoName {
    final store = _lifecycle.store;
    if (store == null) {
      return 'No password store configured';
    }
    return store.name;
  }

  @override
  RepoGitStatus get gitStatus => _gitStatus;

  @override
  StoreGitMode get gitMode =>
      _lifecycle.store?.gitMode ?? StoreGitMode.disabled;

  @override
  List<PasswordEntry> get entries => _entries;

  @override
  List<KeyRecord> get keys => _keys;

  @override
  bool get usesAppManagedPaths =>
      managedStoreBaseDir != null && managedStoreBaseDir!.trim().isNotEmpty;

  @override
  bool isAppManagedStoreRoot(String root) {
    if (!usesAppManagedPaths) {
      return false;
    }
    final baseDirectory = Directory(_requiredManagedStoreBaseDir()).absolute;
    final candidate = Directory(root).absolute;
    final base =
        baseDirectory.existsSync()
            ? baseDirectory.resolveSymbolicLinksSync()
            : baseDirectory.path;
    if (candidate.existsSync()) {
      return Directory(candidate.resolveSymbolicLinksSync()).parent.path ==
          base;
    }
    final parent = candidate.parent;
    final parentPath =
        parent.existsSync() ? parent.resolveSymbolicLinksSync() : parent.path;
    return parentPath == base;
  }

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
      gitBackend:
          Platform.isAndroid || Platform.isIOS
              ? 'Embedded libgit2'
              : 'System git command',
      keyStorageBackend: keyStorageBackendLabel(securityRepository),
      nativeLibrary: 'pars_bridge',
    );
  }

  @override
  Future<void> refresh() => _serializeStoreSideEffects(() async {
    if (_storeRemovalInProgress) return;
    await _refreshState(reconcileAutofill: true);
  });

  /// Publishes the last persisted snapshot so the first frame can render the
  /// vault without waiting for a full store rescan. A later [refresh] replaces
  /// whatever is restored here.
  Future<bool> hydrateFromCache() => _serializeStoreSideEffects(() async {
    if (_storeRemovalInProgress || _refreshEpoch != 0) return false;
    if (await _metadataStore.wasStoreRemoved()) return false;
    final snapshot = await _snapshotCache.load();
    if (snapshot == null || _refreshEpoch != 0) return false;
    _lifecycle = snapshot.lifecycle;
    _entries = snapshot.entries;
    _gitStatus = snapshot.gitStatus;
    _publishLifecycle();
    return true;
  });

  Future<void> _saveSnapshot() async {
    try {
      await _snapshotCache.save(
        VaultSnapshot(
          lifecycle: _lifecycle,
          entries: _entries,
          gitStatus: _gitStatus,
        ),
      );
    } catch (_) {
      // A stale or missing cache only costs a cold scan on the next launch.
    }
  }

  Future<T> _serializeStoreSideEffects<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _storeSideEffectTail = _storeSideEffectTail
        .catchError((_) {
          // A failed operation must not poison the serialization barrier.
        })
        .then((_) async {
          try {
            result.complete(await operation());
          } catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          }
        });
    return result.future;
  }

  Future<void> _refreshState({required bool reconcileAutofill}) async {
    final refreshEpoch = ++_refreshEpoch;
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
    if (refreshEpoch != _refreshEpoch) return;
    _lifecycle = StoreLifecycleSnapshot.fromBridge(state);

    final keyResponse = await bridge.listKeys(
      request: frb.ListKeysRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        sshDir: sshDir,
      ),
    );
    _throwIfFailure(keyResponse.error);
    if (refreshEpoch != _refreshEpoch) return;
    final localKeys = keyResponse.keys
        .map(_keyRecordFromBridge)
        .toList(growable: false);
    _keys = await _withStorePgpReferences(localKeys);
    if (refreshEpoch != _refreshEpoch) return;

    final currentStore = _lifecycle.store;
    if (currentStore == null || !currentStore.exists) {
      await _clearStoreScopedState();
      if (refreshEpoch == _refreshEpoch) {
        await _snapshotCache.clear();
        _publishLifecycle();
      }
      return;
    }

    await _loadMetadataForStore(currentStore.root);
    if (refreshEpoch != _refreshEpoch) return;
    final entriesResponse = await bridge.listEntries(
      request: frb.ListEntriesRequest(
        root: currentStore.root,
        target: null,
        recursive: true,
      ),
    );
    _throwIfFailure(entriesResponse.error);
    if (refreshEpoch != _refreshEpoch) return;
    _entries = entriesResponse.entries
        .map((entry) => _passwordEntryFromBridge(entry, currentStore))
        .toList(growable: false);

    _gitPreferences = await loadGitPreferences(configPath);
    switch (currentStore.gitMode) {
      case StoreGitMode.disabled:
        _statusSummary = null;
        _gitStatus = RepoGitStatus.disabled;
      case StoreGitMode.invalid:
        _statusSummary = null;
        _gitStatus = RepoGitStatus.invalid;
      case StoreGitMode.local:
      case StoreGitMode.remote:
        final summaryResponse = await bridge.gitStatusSummary(
          request: frb.GitRequest(root: currentStore.root, sshDir: sshDir),
        );
        if (refreshEpoch != _refreshEpoch) return;
        _applySummaryResponse(summaryResponse, currentStore.gitMode);
    }
    if (reconcileAutofill) {
      await _runAutofillUpdate(
        (repository) => repository.reconcileIndex(_entries),
      );
    }
    if (refreshEpoch == _refreshEpoch) {
      await _saveSnapshot();
      _publishLifecycle();
    }
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
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    final response = await bridge.readEntry(
      request: await _entryRequest(entry),
    );
    _throwIfFailure(response.error);
    final secret = response.secret;
    if (secret == null) {
      throw const BridgeRepositoryException('Bridge did not return an entry.');
    }
    return _secretFromBridge(secret);
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async {
    final response = await bridge.copyEntryPassword(
      request: await _entryRequest(entry),
    );
    _throwIfFailure(response.error);
    final result = response.result;
    if (result == null) {
      throw const BridgeRepositoryException(
        'Bridge did not return a copied password.',
      );
    }
    return result.password;
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
    await _refreshState(reconcileAutofill: false);
    await _upsertAutofillEntry(result.entryPath);
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
    await _refreshState(reconcileAutofill: false);
    await _upsertAutofillEntry(result.entryPath);
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
    await _refreshState(reconcileAutofill: false);
    await _upsertAutofillEntry(result.path);
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
    final recursive = _entryForPath(fromPath)?.isDirectory ?? false;
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
    await _refreshState(reconcileAutofill: false);
    await _runAutofillUpdate(
      (repository) => repository.moveEntry(
        oldPath: fromPath,
        newPath: result.path,
        recursive: recursive,
      ),
    );
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
    await _refreshState(reconcileAutofill: false);
    await _runAutofillUpdate(
      (repository) => repository.removeEntry(
        path: result.deletedPath,
        recursive: recursive,
      ),
    );
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
  bool get commitsEveryChange =>
      _gitPreferences.commitEveryChange &&
      (gitMode == StoreGitMode.local || gitMode == StoreGitMode.remote);

  @override
  Future<GitOperationResult> commitChanges(String message) async {
    return commit(message.trim().isEmpty ? 'Update password store' : message);
  }

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool initializeGit,
  }) async {
    final response = await bridge.createLocalStore(
      request: frb.CreateLocalStoreRequest(
        configPath: configPath,
        name: name,
        root: root,
        pgpKeys: pgpKeys,
        initializeGit: initializeGit,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<void> importLocalStore({required String root}) async {
    final response = await bridge.importLocalStore(
      request: frb.ImportLocalStoreRequest(configPath: configPath, root: root),
    );
    _throwIfFailure(response.error);
  }

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    bool overwrite = false,
  }) async {
    final transport = await _transport(root: root, remoteUrl: remoteUrl);
    await _withTransport(transport, () async {
      final response = await bridge.cloneStore(
        request: frb.CloneStoreRequest(
          configPath: configPath,
          remoteUrl: remoteUrl,
          root: root,
          sshPrivateKeyPath: transport.request.sshPrivateKeyPath,
          sshDir: sshDir,
          overwrite: overwrite,
          httpsUsername: transport.request.httpsUsername,
          httpsToken: transport.request.httpsToken,
          sshPassphrase: transport.request.sshPassphrase,
        ),
      );
      final failure = response.error;
      if (failure != null && failure.conflictKind == 'EntryAlreadyExists') {
        throw const StoreCloneTargetExists();
      }
      _throwIfFailure(failure);
    });
    await refresh();
  }

  @override
  Future<void> removeStore({required String root}) =>
      _serializeStoreSideEffects(() async {
        final wasCanonical = _isCanonicalStoreRoot(root);
        var cleanupCompleted = false;
        try {
          if (wasCanonical) {
            await _beginCanonicalStoreRemoval();
            cleanupCompleted = true;
          }
          final response = await bridge.disconnectStore(
            request: frb.DisconnectStoreRequest(
              configPath: configPath,
              root: root,
            ),
          );
          _throwIfFailure(response.error);
        } catch (error, stackTrace) {
          if (wasCanonical) {
            if (cleanupCompleted) {
              await _recoverFailedCanonicalStoreRemoval();
            } else {
              _finishFailedCanonicalStoreCleanup();
            }
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (wasCanonical) {
          _completeCanonicalStoreRemoval();
        } else {
          await _refreshState(reconcileAutofill: false);
        }
      });

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) => _serializeStoreSideEffects(() async {
    final wasCanonical = _isCanonicalStoreRoot(root);
    var cleanupCompleted = false;
    try {
      if (wasCanonical) {
        await _beginCanonicalStoreRemoval();
        cleanupCompleted = true;
      }
      final response = await bridge.deleteLocalStore(
        request: frb.DeleteLocalStoreRequest(
          configPath: configPath,
          root: root,
          managedStoreBase: _requiredManagedStoreBaseDir(),
          confirmation: confirmation,
        ),
      );
      _throwIfFailure(response.error);
    } catch (error, stackTrace) {
      if (wasCanonical) {
        if (cleanupCompleted) {
          await _recoverFailedCanonicalStoreRemoval();
        } else {
          _finishFailedCanonicalStoreCleanup();
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (wasCanonical) {
      _completeCanonicalStoreRemoval();
    } else {
      await _refreshState(reconcileAutofill: false);
    }
  });

  Future<void> _beginCanonicalStoreRemoval() async {
    ++_refreshEpoch;
    _storeRemovalInProgress = true;
    _clearStoreScopedPresentation();
    _publishLifecycle();
    await _clearStoreScopedDurableState();
  }

  void _finishFailedCanonicalStoreCleanup() {
    _storeRemovalInProgress = false;
    autofillRepository?.recordSyncFailure(
      const AutofillRepositoryException(
        'Autofill cleanup failed. The store remains configured and locked down.',
      ),
    );
    _publishLifecycle();
  }

  Future<void> _recoverFailedCanonicalStoreRemoval() async {
    try {
      await _refreshState(reconcileAutofill: false);
    } catch (_) {
      // Preserve the original removal failure and the prior canonical lifecycle.
    } finally {
      _storeRemovalInProgress = false;
      autofillRepository?.recordSyncFailure(
        const AutofillRepositoryException(
          'Autofill data was cleared for privacy and will rebuild on refresh.',
        ),
      );
      _publishLifecycle();
    }
  }

  void _completeCanonicalStoreRemoval() {
    _lifecycle = StoreLifecycleSnapshot.withoutStore(
      configPath: configPath,
      configExists: true,
    );
    _storeRemovalInProgress = false;
    _publishLifecycle();
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
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async {
    final response = await bridge.inspectPgpKeyText(
      request: frb.InspectPgpKeyTextRequest(armoredText: armoredText),
    );
    return _pgpInspection(response.inspection, response.error);
  }

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async {
    // Only the path crosses the boundary; Rust reads the bytes.
    final response = await bridge.inspectPgpKeyFile(
      request: frb.InspectPgpKeyFileRequest(path: path),
    );
    return _pgpInspection(response.inspection, response.error);
  }

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async {
    final response = await bridge.importPgpKeyText(
      request: frb.ImportPgpKeyTextRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        armoredText: armoredText,
        passphrase: passphrase,
      ),
    );
    return _recordPgpImport(response);
  }

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async {
    final response = await bridge.importPgpKeyFile(
      request: frb.ImportPgpKeyFileRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        path: path,
        passphrase: passphrase,
      ),
    );
    return _recordPgpImport(response);
  }

  @override
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async {
    final response = await bridge.preparePgpPrivateKey(
      request: frb.PreparePgpPrivateKeyRequest(
        configPath: configPath,
        pgpExecutable: _optionalPgpExecutable(),
        fingerprint: fingerprint,
        passphrase: passphrase,
      ),
    );
    _throwIfPgpImportFailure(response.error);
    final confirmedFingerprint = response.fingerprint;
    if (confirmedFingerprint == null || confirmedFingerprint.trim().isEmpty) {
      throw const PgpImportException(
        PgpImportFailureKind.backendError,
        'The bridge returned no prepared PGP fingerprint.',
      );
    }
    return PgpPrivateKeyPreparation(
      fingerprint: confirmedFingerprint,
      migrated: response.migrated,
    );
  }

  @override
  Future<void> initializeStoreRecipients(List<String> fingerprints) async {
    final response = await bridge.initializeStoreRecipients(
      request: frb.InitializeStoreRecipientsRequest(
        configPath: configPath,
        root: _requiredStoreRoot(),
        fingerprints: fingerprints,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
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
    await _gitCredentials.deletePassphrase(name);
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
  Future<GitOperationResult> initializeRepository() async {
    final store = _lifecycle.store;
    if (store == null || !store.exists) {
      throw const BridgeRepositoryException(
        'A password store is required before Git can be initialized.',
      );
    }
    if (store.gitMode != StoreGitMode.disabled) {
      return const GitOperationResult(
        command: 'git init',
        stdout: 'Git is already enabled.',
        stderr: '',
        exitCode: 0,
        success: true,
      );
    }
    final response = await bridge.initializeGitRepository(
      request: frb.InitializeGitRepositoryRequest(root: store.root),
    );
    _throwIfFailure(response.error);
    await refresh();
    return const GitOperationResult(
      command: 'git init',
      stdout: 'Initialized an empty Git repository.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  GitStatusSummary? get statusSummary => _statusSummary;

  @override
  GitSyncConflict? get lastConflict => _lastConflict;

  @override
  bool get lastRemoteCheckFailed => _lastRemoteCheckFailed;

  @override
  GitPreferences get preferences => _gitPreferences;

  @override
  Future<void> updatePreferences(GitPreferences preferences) async {
    await saveGitPreferences(configPath, preferences);
    _gitPreferences = preferences;
  }

  @override
  Future<GitOperationResult> refreshGitStatus() async {
    final mode = _lifecycle.store?.gitMode;
    if (mode == null || mode == StoreGitMode.disabled) {
      _statusSummary = null;
      _gitStatus = RepoGitStatus.disabled;
      return _gitDisabledResult('git status');
    }
    if (mode == StoreGitMode.invalid) {
      _statusSummary = null;
      _gitStatus = RepoGitStatus.invalid;
      return _gitInvalidResult('git status');
    }
    final root = _requiredStoreRoot();
    final summaryResponse = await bridge.gitStatusSummary(
      request: frb.GitRequest(root: root, sshDir: sshDir),
    );
    _applySummaryResponse(summaryResponse, mode);
    final response = await bridge.gitStatus(
      request: frb.GitRequest(root: root, sshDir: sshDir),
    );
    return _gitResultFromBridge(response);
  }

  @override
  Future<void> checkRemoteOnLaunch() async {
    if (_launchCheckDone) return;
    final store = _lifecycle.store;
    if (store == null || store.gitMode != StoreGitMode.remote) return;
    _launchCheckDone = true;
    if (!_gitPreferences.checkRemoteOnLaunch) return;
    try {
      final transport = await _transport(root: store.root);
      final response = await _withTransport(
        transport,
        () => bridge.gitFetch(request: transport.request),
      );
      _throwIfFailure(response.error);
      _lastRemoteCheckFailed = false;
      _applySummaryResponse(response, store.gitMode);
    } catch (_) {
      _lastRemoteCheckFailed = true;
    }
  }

  @override
  Future<GitOperationResult> pull() async {
    if (_lifecycle.store?.gitMode != StoreGitMode.remote) {
      return _gitDisabledResult('git pull', message: 'Skipped: no Git remote.');
    }
    final transport = await _transport(root: _requiredStoreRoot());
    final result = await _recordingSyncFailure(
      () => _withTransport(transport, () async {
        return _gitResultFromBridge(
          await bridge.gitPull(request: transport.request),
        );
      }),
    );
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> push() async {
    if (_lifecycle.store?.gitMode != StoreGitMode.remote) {
      return _gitDisabledResult('git push', message: 'Skipped: no Git remote.');
    }
    final transport = await _transport(root: _requiredStoreRoot());
    final result = await _recordingSyncFailure(
      () => _withTransport(transport, () async {
        return _gitResultFromBridge(
          await bridge.gitPush(request: transport.request),
        );
      }),
    );
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> commit(String message) async {
    final mode = _lifecycle.store?.gitMode;
    if (mode == null || mode == StoreGitMode.disabled) {
      return _gitDisabledResult('git commit');
    }
    if (mode == StoreGitMode.invalid) {
      return _gitInvalidResult('git commit');
    }
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
  Future<GitSyncOutcome> sync({
    required bool commitPending,
    String message = 'Sync password store',
  }) async {
    if (_lifecycle.store?.gitMode != StoreGitMode.remote) {
      throw const BridgeRepositoryException('Git sync needs a remote.');
    }
    final transport = await _transport(root: _requiredStoreRoot());
    final outcome = await _recordingSyncFailure(
      () => _withTransport(transport, () async {
        final response = await bridge.gitSync(
          request: frb.GitSyncRequest(
            git: transport.request,
            message: message,
            commitPending: commitPending,
            strategy: switch (_gitPreferences.strategy) {
              GitIntegrationStrategy.rebase =>
                frb.GitIntegrationStrategyDto.rebase,
              GitIntegrationStrategy.merge =>
                frb.GitIntegrationStrategyDto.merge,
            },
          ),
        );
        _throwIfFailure(response.error);
        final result = response.result;
        if (result == null) {
          throw const BridgeRepositoryException(
            'Bridge did not return a sync result.',
          );
        }
        return _syncOutcomeFromBridge(result);
      }),
    );
    _lastConflict = outcome.conflict;
    _lastRemoteCheckFailed = false;
    await refresh();
    return outcome;
  }

  @override
  Future<GitResetOutcome> resetToUpstream() async {
    if (_lifecycle.store?.gitMode != StoreGitMode.remote) {
      throw const BridgeRepositoryException('Reset needs a Git remote.');
    }
    final transport = await _transport(root: _requiredStoreRoot());
    final outcome = await _withTransport(transport, () async {
      final response = await bridge.gitResetToUpstream(
        request: frb.GitResetRequest(
          git: transport.request,
          message: 'Save local changes before reset',
        ),
      );
      _throwIfFailure(response.error);
      final result = response.result;
      if (result == null) {
        throw const BridgeRepositoryException(
          'Bridge did not return a reset result.',
        );
      }
      return GitResetOutcome(
        committed: result.committed,
        backupBranch: result.backupBranch,
        summary: _summaryFromBridge(result.summary),
      );
    });
    _lastConflict = null;
    _lastSyncFailed = false;
    await refresh();
    return outcome;
  }

  @override
  Future<GitOperationResult> pushBackupBranch(String branch) async {
    if (_lifecycle.store?.gitMode != StoreGitMode.remote) {
      return _gitDisabledResult('git push', message: 'Skipped: no Git remote.');
    }
    final transport = await _transport(root: _requiredStoreRoot());
    final result = await _withTransport(transport, () async {
      return _gitResultFromBridge(
        await bridge.gitPushBranch(
          request: frb.GitPushBranchRequest(
            git: transport.request,
            branch: branch,
          ),
        ),
      );
    });
    if (_lastConflict?.backupBranch == branch) {
      _lastConflict = null;
    }
    await refresh();
    return result;
  }

  @override
  Future<List<GitLogEntry>> history({int limit = 50}) async {
    final mode = _lifecycle.store?.gitMode;
    if (mode != StoreGitMode.local && mode != StoreGitMode.remote) {
      return const <GitLogEntry>[];
    }
    final response = await bridge.gitLog(
      request: frb.GitLogRequest(root: _requiredStoreRoot(), limit: limit),
    );
    _throwIfFailure(response.error);
    return response.entries
        .map(
          (entry) => GitLogEntry(
            id: entry.id,
            summary: entry.summary,
            author: entry.author,
            time: DateTime.fromMillisecondsSinceEpoch(
              entry.time.toInt() * 1000,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<GitRemoteBranches> remoteBranches() async {
    if (_lifecycle.store?.gitMode != StoreGitMode.remote) {
      return const GitRemoteBranches(
        remote: null,
        current: null,
        branches: <String>[],
      );
    }
    final root = _requiredStoreRoot();
    final transport = await _transport(root: root);
    final fetched = await _withTransport(
      transport,
      () => bridge.gitFetch(request: transport.request),
    );
    _throwIfFailure(fetched.error);
    _applySummaryResponse(fetched, StoreGitMode.remote);
    final response = await bridge.gitListRemoteBranches(
      request: frb.GitRequest(root: root, sshDir: sshDir),
    );
    _throwIfFailure(response.error);
    return GitRemoteBranches(
      remote: response.remote,
      current: response.current,
      branches: response.branches,
    );
  }

  @override
  Future<void> switchBranch(String branch) async {
    final response = await bridge.gitSwitchBranch(
      request: frb.GitSwitchBranchRequest(
        root: _requiredStoreRoot(),
        branch: branch,
      ),
    );
    _throwIfFailure(response.error);
    await refresh();
  }

  @override
  Future<GitIdentity?> identity() async {
    final mode = _lifecycle.store?.gitMode;
    if (mode != StoreGitMode.local && mode != StoreGitMode.remote) return null;
    final response = await bridge.gitIdentity(
      request: frb.GitIdentityRequest(root: _requiredStoreRoot()),
    );
    _throwIfFailure(response.error);
    final identity = response.identity;
    if (identity == null) return null;
    return GitIdentity(
      name: identity.name,
      email: identity.email,
      local: identity.local,
    );
  }

  @override
  GitIdentity? suggestedIdentity() {
    GitIdentity? fallback;
    for (final key in _keys) {
      if (key.type != KeyRecordType.pgp || !key.hasPrivateKey) continue;
      final parsed = GitIdentity.fromUserId(key.name);
      if (parsed == null) continue;
      if (key.referencedByStores.isNotEmpty) return parsed;
      fallback ??= parsed;
    }
    return fallback;
  }

  @override
  Future<void> setIdentity({
    required String name,
    required String email,
  }) async {
    final response = await bridge.gitSetIdentity(
      request: frb.GitSetIdentityRequest(
        root: _requiredStoreRoot(),
        name: name,
        email: email,
      ),
    );
    _throwIfFailure(response.error);
  }

  @override
  Future<bool> hasHttpsCredentials() async {
    final url = await _primaryRemoteUrl();
    if (url == null || !_isHttpsRemote(url)) return false;
    return await _gitCredentials.readHttps(url) != null;
  }

  @override
  Future<void> rememberHttpsCredentials(HttpsCredentials credentials) async {
    _pendingHttps = credentials;
  }

  @override
  Future<void> forgetHttpsCredentials() async {
    _pendingHttps = null;
    final url = await _primaryRemoteUrl();
    if (url != null) await _gitCredentials.deleteHttps(url);
  }

  @override
  Future<void> rememberSshPassphrase(
    String passphrase, {
    required bool persist,
  }) async {
    _pendingSshPassphrase = (passphrase: passphrase, persist: persist);
  }

  @override
  Future<GitOperationResult> runCommandLine(String commandLine) async {
    final mode = _lifecycle.store?.gitMode;
    final command = 'git ${commandLine.trim()}';
    if (mode == null || mode == StoreGitMode.disabled) {
      return _gitDisabledResult(command);
    }
    if (mode == StoreGitMode.invalid) {
      return _gitInvalidResult(command);
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return GitOperationResult(
        command: command,
        stdout: '',
        stderr: 'Advanced Git arguments are unavailable on mobile.',
        exitCode: 1,
        success: false,
      );
    }
    try {
      final response = await bridge.runGitArgs(
        request: frb.GitArgsRequest(
          root: _requiredStoreRoot(),
          commandLine: commandLine,
        ),
      );
      return _gitResultFromBridge(response);
    } finally {
      await refresh();
    }
  }

  @override
  Future<List<GitRemote>> listRemotes() async {
    final mode = _lifecycle.store?.gitMode;
    if (mode == null ||
        mode == StoreGitMode.disabled ||
        mode == StoreGitMode.invalid) {
      return const <GitRemote>[];
    }
    final response = await bridge.gitListRemotes(
      request: frb.GitRequest(root: _requiredStoreRoot(), sshDir: sshDir),
    );
    return _parseRemotes(_gitResultFromBridge(response).stdout);
  }

  @override
  Future<GitOperationResult> addRemote({
    required String name,
    required String url,
  }) async {
    final mode = _lifecycle.store?.gitMode;
    final command =
        'git remote add ${name.trim()} ${_sanitizedRemoteUrl(url.trim())}';
    if (mode == null || mode == StoreGitMode.disabled) {
      return _gitDisabledResult(command);
    }
    if (mode == StoreGitMode.invalid) {
      return _gitInvalidResult(command);
    }
    final response = await bridge.gitAddRemote(
      request: frb.GitRemoteRequest(
        root: _requiredStoreRoot(),
        name: name.trim(),
        url: url.trim(),
      ),
    );
    final result = _gitResultFromBridge(response);
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> editRemote({
    required String name,
    required String url,
  }) async {
    final mode = _lifecycle.store?.gitMode;
    final command =
        'git remote set-url ${name.trim()} ${_sanitizedRemoteUrl(url.trim())}';
    if (mode == null || mode == StoreGitMode.disabled) {
      return _gitDisabledResult(command);
    }
    if (mode == StoreGitMode.invalid) {
      return _gitInvalidResult(command);
    }
    final response = await bridge.gitSetRemoteUrl(
      request: frb.GitRemoteRequest(
        root: _requiredStoreRoot(),
        name: name.trim(),
        url: url.trim(),
      ),
    );
    final result = _gitResultFromBridge(response);
    await refresh();
    return result;
  }

  @override
  Future<GitOperationResult> removeRemote(String name) async {
    final mode = _lifecycle.store?.gitMode;
    if (mode == null || mode == StoreGitMode.disabled) {
      return _gitDisabledResult('git remote remove ${name.trim()}');
    }
    if (mode == StoreGitMode.invalid) {
      return _gitInvalidResult('git remote remove ${name.trim()}');
    }
    final response = await bridge.gitRemoveRemote(
      request: frb.GitRemoteRequest(
        root: _requiredStoreRoot(),
        name: name.trim(),
        url: null,
      ),
    );
    final result = _gitResultFromBridge(response);
    await refresh();
    return result;
  }

  /// Marks an explicit network failure as sync failed. Credential prompts are
  /// not failures: the caller asks the user and retries.
  Future<T> _recordingSyncFailure<T>(Future<T> Function() operation) async {
    try {
      final result = await operation();
      _lastSyncFailed = false;
      return result;
    } on GitIdentityRequiredException {
      rethrow;
    } on GitAuthenticationRequiredException {
      rethrow;
    } on GitSshPassphraseRequiredException {
      rethrow;
    } catch (_) {
      _lastSyncFailed = true;
      _gitStatus = RepoGitStatus.syncFailed;
      rethrow;
    }
  }

  Future<String?> _primaryRemoteUrl() async {
    final remotes = await listRemotes();
    if (remotes.isEmpty) return null;
    final upstreamRemote = _statusSummary?.upstream?.split('/').first;
    final remote = remotes.firstWhere(
      (remote) => remote.name == upstreamRemote,
      orElse: () => remotes.first,
    );
    return remote.pushUrl.isNotEmpty ? remote.pushUrl : remote.fetchUrl;
  }

  bool _isHttpsRemote(String url) {
    final lower = url.trim().toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  /// Resolves the SSH key and any credentials for one network operation.
  /// Values the user just typed are only persisted once the remote accepts
  /// them; stored values the remote rejects are forgotten.
  Future<_GitTransport> _transport({
    required String root,
    String? remoteUrl,
  }) async {
    final url = remoteUrl ?? await _primaryRemoteUrl();
    final sshKeyPath = url == null ? null : await _sshPrivateKeyForUrl(url);
    final mobile = Platform.isAndroid || Platform.isIOS;

    HttpsCredentials? https;
    var httpsFromStore = false;
    var httpsFromPending = false;
    if (mobile && url != null && _isHttpsRemote(url)) {
      final pending = _pendingHttps;
      if (pending != null) {
        https = pending;
        httpsFromPending = true;
      } else {
        https = await _gitCredentials.readHttps(url);
        httpsFromStore = https != null;
      }
    }

    String? keyName;
    String? passphrase;
    var passphraseFromPending = false;
    if (mobile && sshKeyPath != null) {
      keyName = sshKeyPath.split(RegExp(r'[/\\]')).last;
      final encrypted = _keys.any(
        (key) =>
            key.type == KeyRecordType.ssh &&
            key.name == keyName &&
            key.encrypted,
      );
      if (encrypted) {
        final pending = _pendingSshPassphrase;
        if (pending != null) {
          passphrase = pending.passphrase;
          passphraseFromPending = true;
        } else {
          passphrase = await _gitCredentials.readPassphrase(keyName);
        }
      }
    }

    return _GitTransport(
      request: frb.GitRequest(
        root: root,
        sshPrivateKeyPath: sshKeyPath,
        sshDir: sshDir,
        httpsUsername: https?.username,
        httpsToken: https?.token,
        sshPassphrase: passphrase,
      ),
      remoteUrl: url,
      httpsFromStore: httpsFromStore,
      httpsFromPending: httpsFromPending,
      sshKeyName: keyName,
      passphraseFromPending: passphraseFromPending,
    );
  }

  Future<T> _withTransport<T>(
    _GitTransport transport,
    Future<T> Function() operation,
  ) async {
    try {
      final result = await operation();
      await _acceptTransport(transport);
      return result;
    } on GitAuthenticationRequiredException {
      _pendingHttps = null;
      final url = transport.remoteUrl;
      if (transport.httpsFromStore && url != null) {
        await _gitCredentials.deleteHttps(url);
      }
      rethrow;
    } on GitSshPassphraseRequiredException {
      _pendingSshPassphrase = null;
      final keyName = transport.sshKeyName;
      if (keyName != null) await _gitCredentials.deletePassphrase(keyName);
      rethrow;
    }
  }

  Future<void> _acceptTransport(_GitTransport transport) async {
    final url = transport.remoteUrl;
    final https = _pendingHttps;
    if (transport.httpsFromPending && https != null && url != null) {
      _pendingHttps = null;
      await _gitCredentials.writeHttps(url, https);
    }
    final pending = _pendingSshPassphrase;
    final keyName = transport.sshKeyName;
    if (transport.passphraseFromPending && pending != null && keyName != null) {
      _pendingSshPassphrase = null;
      await _gitCredentials.writePassphrase(
        keyName,
        pending.passphrase,
        remember: pending.persist,
      );
    }
  }

  void _applySummaryResponse(
    frb.GitStatusSummaryResponse response,
    StoreGitMode mode,
  ) {
    final summary = response.summary;
    if (response.error != null || summary == null) {
      _statusSummary = null;
      _gitStatus = RepoGitStatus.syncFailed;
      return;
    }
    _statusSummary = _summaryFromBridge(summary);
    _gitStatus = classifyGitStatus(
      _statusSummary!,
      mode: mode,
      conflict: _lastConflict,
      syncFailed: _lastSyncFailed,
    );
  }

  GitStatusSummary _summaryFromBridge(frb.GitStatusSummaryDto dto) {
    final fetched = dto.lastFetchedAt;
    return GitStatusSummary(
      branch: dto.branch,
      upstream: dto.upstream,
      ahead: dto.ahead,
      behind: dto.behind,
      changed: dto.changed,
      conflicted: dto.conflicted,
      operation: switch (dto.operation) {
        frb.GitStatusOperationDto.none => GitOperationState.none,
        frb.GitStatusOperationDto.rebasing => GitOperationState.rebasing,
        frb.GitStatusOperationDto.merging => GitOperationState.merging,
        frb.GitStatusOperationDto.other => GitOperationState.other,
      },
      lastFetchedAt:
          fetched == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(fetched.toInt() * 1000),
    );
  }

  GitSyncOutcome _syncOutcomeFromBridge(frb.GitSyncResultDto dto) {
    final conflict = dto.conflict;
    return GitSyncOutcome(
      committed: dto.committed,
      pulled: dto.pulled,
      pushed: dto.pushed,
      blockedByChanges: dto.blockedByChanges,
      conflict:
          conflict == null
              ? null
              : GitSyncConflict(
                backupBranch: conflict.backupBranch,
                paths: List<String>.unmodifiable(conflict.paths),
              ),
      summary: _summaryFromBridge(dto.summary),
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
    );
  }

  KeyRecord _keyRecordFromBridge(frb.KeyRecordDto key) {
    return KeyRecord(
      type: key.keyType == 'ssh' ? KeyRecordType.ssh : KeyRecordType.pgp,
      name: key.name,
      fingerprint: key.fingerprint,
      source: key.source,
      hasPrivateKey: key.hasPrivateKey,
      encrypted: key.encrypted,
    );
  }

  Future<List<KeyRecord>> _withStorePgpReferences(
    List<KeyRecord> localKeys,
  ) async {
    final identifiers = <String, String>{};
    final storesByIdentifier = <String, Set<String>>{};

    final store = _lifecycle.store;
    if (store != null && store.exists) {
      for (final identifier in await _readStorePgpIdentifiers(store.root)) {
        final normalized = identifier.toLowerCase();
        identifiers.putIfAbsent(normalized, () => identifier);
        (storesByIdentifier[normalized] ??= <String>{}).add(store.name);
      }
    }

    final keys = <KeyRecord>[...localKeys];
    for (final entry in identifiers.entries) {
      final identifier = entry.value;
      if (localKeys.any((key) => _matchesPgpReference(key, identifier))) {
        continue;
      }
      keys.add(
        KeyRecord(
          type: KeyRecordType.pgp,
          name: identifier,
          fingerprint: identifier,
          source: '.gpg-id',
          hasPrivateKey: false,
          hasLocalKeyMaterial: false,
          referencedByStores: List<String>.unmodifiable(
            storesByIdentifier[entry.key] ?? const <String>{},
          ),
        ),
      );
    }
    return List<KeyRecord>.unmodifiable(keys);
  }

  Future<List<String>> _readStorePgpIdentifiers(String root) async {
    final gpgId = File(_joinFilesystemPath(root, '.gpg-id'));
    try {
      if (!await gpgId.exists()) {
        return const <String>[];
      }
      final content = await gpgId.readAsString();
      return content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList(growable: false);
    } on FileSystemException {
      return const <String>[];
    }
  }

  bool _matchesPgpReference(KeyRecord key, String reference) {
    if (key.type != KeyRecordType.pgp || !key.hasLocalKeyMaterial) {
      return false;
    }
    final normalizedReference = reference.trim().toLowerCase();
    final normalizedFingerprint = key.fingerprint.trim().toLowerCase();
    final normalizedName = key.name.trim().toLowerCase();
    if (normalizedReference == normalizedFingerprint ||
        normalizedReference == normalizedName ||
        normalizedName.contains('<$normalizedReference>')) {
      return true;
    }

    final compactReference = _compactHexKeyId(normalizedReference);
    final compactFingerprint = _compactHexKeyId(normalizedFingerprint);
    return compactReference != null &&
        compactFingerprint != null &&
        (compactFingerprint.endsWith(compactReference) ||
            compactReference.endsWith(compactFingerprint));
  }

  String? _compactHexKeyId(String value) {
    final compact = value
        .replaceFirst(RegExp(r'^0x'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 || !RegExp(r'^[0-9a-f]+$').hasMatch(compact)) {
      return null;
    }
    return compact;
  }

  KeyRecord _recordKeyMutation(frb.KeyMutationResponse response) {
    final key = _keyFromMutation(response);
    _upsertKey(key);
    return key;
  }

  PgpKeyInspection _pgpInspection(
    frb.PgpKeyInspectionDto? inspection,
    frb.BridgeFailure? failure,
  ) {
    _throwIfPgpImportFailure(failure);
    if (inspection == null) {
      throw const PgpImportException(
        PgpImportFailureKind.unsupportedMaterial,
        'The bridge returned no PGP key inspection.',
      );
    }
    return _pgpInspectionFromBridge(inspection);
  }

  Future<PgpImportResult> _recordPgpImport(
    frb.PgpKeyImportResponse response,
  ) async {
    _throwIfPgpImportFailure(response.error);
    final key = response.key;
    final inspection = response.inspection;
    if (key == null || inspection == null) {
      throw const PgpImportException(
        PgpImportFailureKind.backendError,
        'The bridge reported a successful PGP import without a key record.',
      );
    }
    final record = _keyRecordFromBridge(key);
    _upsertKey(record);
    return PgpImportResult(
      key: record,
      inspection: _pgpInspectionFromBridge(inspection),
    );
  }

  PgpKeyInspection _pgpInspectionFromBridge(frb.PgpKeyInspectionDto dto) {
    return PgpKeyInspection(
      kind:
          dto.kind == frb.PgpKeyKindDto.private
              ? PgpKeyKind.private
              : PgpKeyKind.public,
      fingerprint: dto.fingerprint,
      identity: dto.identity,
      hasPrivateKey: dto.hasPrivateKey,
      requiresPassphrase: dto.requiresPassphrase,
      armored: dto.armored,
    );
  }

  /// Maps a bridge failure to a typed import exception.
  ///
  /// The message is already sanitized in Rust; nothing is added to it here.
  void _throwIfPgpImportFailure(frb.BridgeFailure? failure) {
    if (failure == null) {
      return;
    }
    throw PgpImportException(
      _pgpImportFailureKind(failure.pgpImportKind),
      failure.message,
    );
  }

  PgpImportFailureKind _pgpImportFailureKind(frb.PgpImportFailureKind? kind) {
    switch (kind) {
      case frb.PgpImportFailureKind.unsupportedMaterial:
        return PgpImportFailureKind.unsupportedMaterial;
      case frb.PgpImportFailureKind.kindMismatch:
        return PgpImportFailureKind.kindMismatch;
      case frb.PgpImportFailureKind.passphraseRequired:
        return PgpImportFailureKind.passphraseRequired;
      case frb.PgpImportFailureKind.incorrectPassphrase:
        return PgpImportFailureKind.incorrectPassphrase;
      case frb.PgpImportFailureKind.unsupportedProtection:
        return PgpImportFailureKind.unsupportedProtection;
      case frb.PgpImportFailureKind.reprotectionFailed:
        return PgpImportFailureKind.reprotectionFailed;
      case frb.PgpImportFailureKind.backendError:
        return PgpImportFailureKind.backendError;
      case null:
        return PgpImportFailureKind.unknown;
    }
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
    if (key.type == KeyRecordType.pgp) {
      if (existing.hasLocalKeyMaterial && !key.hasLocalKeyMaterial) {
        return _matchesPgpReference(existing, key.fingerprint);
      }
      if (!existing.hasLocalKeyMaterial && key.hasLocalKeyMaterial) {
        return _matchesPgpReference(key, existing.fingerprint);
      }
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

  Future<frb.EntryRequest> _entryRequest(PasswordEntry entry) async {
    final activePassphrase =
        await securityRepository?.readActivePgpPassphrase();
    return frb.EntryRequest(
      configPath: configPath,
      root: _requiredStoreRoot(),
      path: entry.path,
      pgpExecutable: pgpExecutable,
      passphrase: activePassphrase?.passphrase,
    );
  }

  String _requiredStoreRoot() {
    final root = _lifecycle.store?.root;
    if (root == null) {
      throw const BridgeRepositoryException('No canonical password store.');
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

  PasswordEntry? _entryForPath(String path) {
    for (final entry in _entries) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  Future<void> _upsertAutofillEntry(String path) async {
    final entry =
        _entryForPath(path) ??
        PasswordEntry(
          path: path,
          displayName: _basename(path),
          repoName: currentRepoName,
          encryptedContent: '',
        );
    if (entry.isDirectory) return;
    await _runAutofillUpdate((repository) => repository.upsertEntry(entry));
  }

  bool _isCanonicalStoreRoot(String root) => _lifecycle.store?.root == root;

  Future<void> _runAutofillUpdate(
    Future<void> Function(AutofillRepository repository) update,
  ) async {
    final repository = autofillRepository;
    if (repository == null) return;
    try {
      await update(repository);
    } catch (error) {
      repository.recordSyncFailure(error);
    }
  }

  void _publishLifecycle() {
    final store = _lifecycle.store;
    final identity = <Object?>[
      _lifecycle.configExists,
      _lifecycle.onboardingState,
      _storeRemovalInProgress,
      ..._lifecycle.issues,
      store?.root,
      store?.exists,
      store?.hasGpgId,
      store?.pgpKeyMissing,
      store?.gitMode,
      ...?store?.issues,
    ].join('|');
    if (identity == _publishedLifecycleIdentity) return;
    _publishedLifecycleIdentity = identity;
    _lifecycleRevision.value += 1;
  }

  Future<VaultMetadata> _loadMetadataForStore(String root) async {
    final loaded = await _metadataStore.load();
    final removalWasPersisted = await _metadataStore.wasStoreRemoved();
    if (!removalWasPersisted &&
        !loaded.removalTombstone &&
        loaded.storeRoot == root) {
      final current = loaded.copyWith(version: VaultMetadata.currentVersion);
      if (loaded.version != VaultMetadata.currentVersion) {
        try {
          await _metadataStore.save(current);
        } catch (_) {
          // In-memory metadata is sanitized even if disk cleanup needs retry.
        }
      }
      return current;
    }
    if (!removalWasPersisted &&
        !loaded.removalTombstone &&
        loaded.storeRoot == null) {
      final migrated = loaded.copyWith(
        storeRoot: root,
        version: VaultMetadata.currentVersion,
      );
      try {
        await _metadataStore.save(migrated);
        return migrated;
      } catch (_) {
        return VaultMetadata.empty(storeRoot: root);
      }
    }
    final empty = VaultMetadata.empty(storeRoot: root);
    try {
      await _metadataStore.save(empty);
    } catch (_) {
      // Keep replacement metadata empty even when durable cleanup needs retry.
    }
    return empty;
  }

  void _clearStoreScopedPresentation() {
    _entries = const <PasswordEntry>[];
    _gitStatus = RepoGitStatus.disabled;
  }

  Future<void> _clearStoreScopedDurableState() async {
    var removalMarkerPersisted = false;
    var metadataTombstonePersisted = false;
    try {
      await _snapshotCache.clear();
    } catch (_) {
      // The metadata tombstone still keeps a stale snapshot from being restored.
    }
    try {
      await _metadataStore.markStoreRemoved();
      removalMarkerPersisted = true;
    } catch (_) {
      // The independent metadata tombstone may still make replacement fail-closed.
    }
    try {
      await _metadataStore.save(const VaultMetadata.removed());
      metadataTombstonePersisted = true;
    } catch (_) {
      // The independent removal marker may still make replacement fail-closed.
    }
    try {
      await securityRepository?.clearPgpSession();
    } catch (_) {
      // Store removal remains fail-closed even if session cleanup reports an error.
    }
    final autofillCleared = await _clearAutofillIndex();
    if (!removalMarkerPersisted && !metadataTombstonePersisted) {
      throw const BridgeRepositoryException(
        'Store removal was cancelled because privacy cleanup could not be saved. '
        'The store remains configured; fix storage access and retry.',
      );
    }
    if (!autofillCleared) {
      throw const AutofillRepositoryException(
        'Store removal was cancelled because Autofill could not be disabled.',
      );
    }
  }

  Future<void> _clearStoreScopedState() async {
    _clearStoreScopedPresentation();
    await _clearStoreScopedDurableState();
  }

  Future<bool> _clearAutofillIndex() async {
    final repository = autofillRepository;
    if (repository == null) return true;
    try {
      await repository.clearIndex();
      return true;
    } catch (error) {
      repository.recordSyncFailure(error);
      return false;
    }
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

  String? _sshPrivateKeyPathForRemote(
    String remoteUrl, {
    String? preferredName,
  }) {
    if (!remoteUrlUsesSsh(remoteUrl) ||
        sshDir == null ||
        sshDir!.trim().isEmpty) {
      return null;
    }
    final keys = <KeyRecord>[
      for (final key in _keys)
        if (key.type == KeyRecordType.ssh && key.hasPrivateKey) key,
    ];
    final preferred = preferredName?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      for (final key in keys) {
        if (key.name == preferred) {
          return _joinFilesystemPath(sshDir!, key.name);
        }
      }
    }
    if (keys.length == 1) {
      return _joinFilesystemPath(sshDir!, keys.single.name);
    }
    return null;
  }

  Future<String?> _sshPrivateKeyForUrl(String remoteUrl) async {
    if (!remoteUrlUsesSsh(remoteUrl)) return null;
    final preferred = await loadSelectedSshKey(configPath);
    final path = _sshPrivateKeyPathForRemote(
      remoteUrl,
      preferredName: preferred,
    );
    if (path != null) return path;
    final imported =
        _keys
            .where((key) => key.type == KeyRecordType.ssh && key.hasPrivateKey)
            .length;
    if (imported > 1) {
      throw const BridgeRepositoryException(
        'Choose an imported SSH key for this remote.',
      );
    }
    return null;
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

  GitOperationResult _gitDisabledResult(
    String command, {
    String message = 'Skipped: Git is disabled for this password store.',
  }) {
    return GitOperationResult(
      command: _sanitizeGitText(command),
      stdout: _sanitizeGitText(message),
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  GitOperationResult _gitInvalidResult(String command) {
    return GitOperationResult(
      command: _sanitizeGitText(command),
      stdout: '',
      stderr: 'The password store contains invalid Git metadata.',
      exitCode: 1,
      success: false,
    );
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
      command: _sanitizeGitText(output.command),
      stdout: _sanitizeGitText(output.stdout),
      stderr: _sanitizeGitText(output.stderr),
      exitCode: output.exitCode,
      success: output.success,
    );
  }

  String _sanitizeGitText(String raw) {
    return raw.splitMapJoin(
      RegExp(r'\s+'),
      onMatch: (match) => match.group(0)!,
      onNonMatch: _sanitizeGitToken,
    );
  }

  String _sanitizeGitToken(String token) {
    final leading =
        RegExp(r'''^[\'"(\[{]+''').firstMatch(token)?.group(0) ?? '';
    final trailing =
        RegExp(r'''[\'"),\]};]+$''').firstMatch(token)?.group(0) ?? '';
    if (leading.length + trailing.length > token.length) return token;
    final core = token.substring(
      leading.length,
      token.length - trailing.length,
    );
    final sanitized =
        core.startsWith('content://') || core.startsWith('file://')
            ? '[uri]'
            : core.contains('://')
            ? _sanitizedRemoteUrl(core)
            : core.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(core)
            ? '[path]'
            : _sanitizedRemoteUrl(core);
    return '$leading$sanitized$trailing';
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
      final url = _sanitizedRemoteUrl(parts[1]);
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

  String _sanitizedRemoteUrl(String input) {
    var value = _stripRemoteUrlSuffix(input);
    final scheme = value.indexOf('://');
    if (scheme >= 0) {
      final authorityStart = scheme + 3;
      final slash = value.indexOf('/', authorityStart);
      final authorityEnd = slash < 0 ? value.length : slash;
      final at = value.lastIndexOf('@', authorityEnd);
      if (at >= authorityStart) {
        value =
            '${value.substring(0, authorityStart)}***@${value.substring(at + 1)}';
      }
    } else {
      final at = value.lastIndexOf('@');
      if (at > 0) {
        final userinfo = value.substring(0, at);
        final hostPath = value.substring(at + 1);
        final colon = hostPath.indexOf(':');
        if (!userinfo.contains(RegExp(r'[/\\]')) &&
            colon > 0 &&
            colon < hostPath.length - 1 &&
            !hostPath.substring(0, colon).contains(RegExp(r'[/\\]'))) {
          value = '***@${value.substring(at + 1)}';
        }
      }
    }
    return value;
  }

  /// Query and fragment markers belong to remote URLs. The Git status header
  /// is the token `##`, and treating that `#` as a fragment erases it.
  String _stripRemoteUrlSuffix(String input) {
    if (!input.contains('://') && !_scpStyleRemote(input)) return input;
    return input.split(RegExp(r'[?#]')).first;
  }

  bool _scpStyleRemote(String value) {
    final at = value.lastIndexOf('@');
    if (at <= 0) return false;
    final userinfo = value.substring(0, at);
    final hostPath = value.substring(at + 1);
    final colon = hostPath.indexOf(':');
    return !userinfo.contains(RegExp(r'[/\\]')) &&
        colon > 0 &&
        colon < hostPath.length - 1 &&
        !hostPath.substring(0, colon).contains(RegExp(r'[/\\]'));
  }

  void _throwIfFailure(frb.BridgeFailure? failure) {
    if (failure == null) return;
    switch (failure.category) {
      case frb.BridgeFailureCategory.identityRequired:
        throw GitIdentityRequiredException(failure.message);
      case frb.BridgeFailureCategory.authenticationRequired:
        throw GitAuthenticationRequiredException(failure.message);
      case frb.BridgeFailureCategory.sshPassphraseRequired:
        throw GitSshPassphraseRequiredException(failure.message);
      default:
        throw BridgeRepositoryException(failure.message);
    }
  }
}

class _GitTransport {
  const _GitTransport({
    required this.request,
    required this.remoteUrl,
    required this.httpsFromStore,
    required this.httpsFromPending,
    required this.sshKeyName,
    required this.passphraseFromPending,
  });

  final frb.GitRequest request;
  final String? remoteUrl;
  final bool httpsFromStore;
  final bool httpsFromPending;
  final String? sshKeyName;
  final bool passphraseFromPending;
}
