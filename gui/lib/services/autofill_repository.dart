import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../bridge/frb_generated/api.dart' as frb;
import '../models/password_entry.dart';
import 'security_repository.dart';

const MethodChannel _platformAutofillChannel = MethodChannel(
  'top.vollate.pars_gui/autofill',
);

class AutofillRepositoryException implements Exception {
  const AutofillRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AutofillCandidate {
  const AutofillCandidate({
    required this.path,
    required this.displayName,
    required this.username,
    required this.matchKind,
    required this.matchValue,
    required this.score,
  });

  final String path;
  final String displayName;
  final String username;
  final String matchKind;
  final String matchValue;
  final int score;
}

class AutofillCredential {
  const AutofillCredential({
    required this.path,
    required this.username,
    required this.password,
  });

  final String path;
  final String username;
  final String password;
}

enum AutofillStatusKind { ready, syncFailed, busy, disabled, unavailable }

class AutofillStatus {
  const AutofillStatus({
    required this.available,
    required this.indexedEntries,
    this.kind = AutofillStatusKind.ready,
    this.message,
  });

  const AutofillStatus.unavailable(this.message)
    : available = false,
      indexedEntries = 0,
      kind = AutofillStatusKind.unavailable;

  const AutofillStatus.disabled(this.message)
    : available = false,
      indexedEntries = 0,
      kind = AutofillStatusKind.disabled;

  final bool available;
  final int indexedEntries;
  final AutofillStatusKind kind;
  final String? message;
}

abstract interface class AutofillRepository {
  AutofillStatus get status;

  Future<void> rebuildIndex(List<PasswordEntry> entries);

  Future<void> upsertEntry(PasswordEntry entry);

  Future<void> moveEntry({
    required String oldPath,
    required String newPath,
    required bool recursive,
  });

  Future<void> removeEntry({required String path, required bool recursive});

  Future<void> reconcileIndex(List<PasswordEntry> entries);

  Future<void> useEncryptedLoginAndUrls(List<PasswordEntry> entries);

  Future<void> forgetEncryptedLoginAndUrls();

  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? appName,
    String? query,
    int limit = 10,
  });

  Future<AutofillCredential?> resolveCredential(String path);

  Future<void> publishPlatformState();

  Future<void> openPlatformSettings();

  void recordSyncFailure(Object error);

  Future<void> clearIndex();
}

abstract interface class AutofillBridgeApi {
  Future<frb.UnitResponse> rebuildAutofillIndex({
    required frb.RebuildAutofillIndexRequest request,
  });

  Future<frb.UnitResponse> upsertAutofillIndexEntry({
    required frb.UpsertAutofillIndexEntryRequest request,
  });

  Future<frb.UnitResponse> moveAutofillIndexEntry({
    required frb.MoveAutofillIndexEntryRequest request,
  });

  Future<frb.UnitResponse> removeAutofillIndexEntry({
    required frb.RemoveAutofillIndexEntryRequest request,
  });

  Future<frb.UnitResponse> reconcileAutofillIndex({
    required frb.ReconcileAutofillIndexRequest request,
  });

  Future<frb.UnitResponse> refreshAutofillIndexLoginAndUrls({
    required frb.RefreshAutofillIndexLoginAndUrlsRequest request,
  });

  Future<frb.UnitResponse> forgetAutofillIndexLoginAndUrls({
    required frb.ForgetAutofillIndexLoginAndUrlsRequest request,
  });

  Future<frb.AutofillCandidatesResponse> queryAutofillCandidates({
    required frb.AutofillQueryRequest request,
  });

  Future<frb.AutofillCredentialResponse> resolveAutofillCredential({
    required frb.AutofillCredentialRequest request,
  });

  Future<frb.UnitResponse> clearAutofillIndex({
    required frb.ClearAutofillIndexRequest request,
  });
}

final class FrbAutofillBridgeApi implements AutofillBridgeApi {
  const FrbAutofillBridgeApi();

  @override
  Future<frb.UnitResponse> rebuildAutofillIndex({
    required frb.RebuildAutofillIndexRequest request,
  }) => frb.rebuildAutofillIndex(request: request);

  @override
  Future<frb.UnitResponse> upsertAutofillIndexEntry({
    required frb.UpsertAutofillIndexEntryRequest request,
  }) => frb.upsertAutofillIndexEntry(request: request);

  @override
  Future<frb.UnitResponse> moveAutofillIndexEntry({
    required frb.MoveAutofillIndexEntryRequest request,
  }) => frb.moveAutofillIndexEntry(request: request);

  @override
  Future<frb.UnitResponse> removeAutofillIndexEntry({
    required frb.RemoveAutofillIndexEntryRequest request,
  }) => frb.removeAutofillIndexEntry(request: request);

  @override
  Future<frb.UnitResponse> reconcileAutofillIndex({
    required frb.ReconcileAutofillIndexRequest request,
  }) => frb.reconcileAutofillIndex(request: request);

  @override
  Future<frb.UnitResponse> refreshAutofillIndexLoginAndUrls({
    required frb.RefreshAutofillIndexLoginAndUrlsRequest request,
  }) => frb.refreshAutofillIndexLoginAndUrls(request: request);

  @override
  Future<frb.UnitResponse> forgetAutofillIndexLoginAndUrls({
    required frb.ForgetAutofillIndexLoginAndUrlsRequest request,
  }) => frb.forgetAutofillIndexLoginAndUrls(request: request);

  @override
  Future<frb.AutofillCandidatesResponse> queryAutofillCandidates({
    required frb.AutofillQueryRequest request,
  }) => frb.queryAutofillCandidates(request: request);

  @override
  Future<frb.AutofillCredentialResponse> resolveAutofillCredential({
    required frb.AutofillCredentialRequest request,
  }) => frb.resolveAutofillCredential(request: request);

  @override
  Future<frb.UnitResponse> clearAutofillIndex({
    required frb.ClearAutofillIndexRequest request,
  }) => frb.clearAutofillIndex(request: request);
}

class BridgeAutofillRepository implements AutofillRepository {
  BridgeAutofillRepository({
    required this.bridge,
    required this.configPath,
    required this.indexPath,
    required this.storeId,
    required this.storeName,
    required this.storeRoot,
    this.pgpExecutable,
    this.securityRepository,
    this.currentStoreId,
    this.currentStoreName,
    this.currentStoreRoot,
    this.currentStoreReady,
    this.validatePgpPassphraseForCurrentStore,
    this.forcePlatformPublication = false,
  });

  final AutofillBridgeApi bridge;
  final String configPath;
  final String indexPath;
  final String storeId;
  final String storeName;
  final String storeRoot;
  final String? pgpExecutable;
  final SecurityRepository? securityRepository;
  final String Function()? currentStoreId;
  final String Function()? currentStoreName;
  final String Function()? currentStoreRoot;
  final bool Function()? currentStoreReady;
  final Future<bool> Function(String fingerprint, String passphrase)?
  validatePgpPassphraseForCurrentStore;
  final bool forcePlatformPublication;
  AutofillStatus _status = const AutofillStatus.unavailable(
    'Autofill data has not been built',
  );
  Future<void> _platformStateTail = Future<void>.value();

  @override
  AutofillStatus get status => _status;

  @override
  Future<void> rebuildIndex(List<PasswordEntry> entries) async {
    final response = await bridge.rebuildAutofillIndex(
      request: frb.RebuildAutofillIndexRequest(
        indexPath: indexPath,
        storeId: currentStoreId?.call() ?? storeId,
        storeName: currentStoreName?.call() ?? storeName,
        root: currentStoreRoot?.call() ?? storeRoot,
      ),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    _status = AutofillStatus(
      available: true,
      indexedEntries: _passwordEntryCount(entries),
      message: 'Path-based autofill data is up to date',
    );
  }

  @override
  Future<void> upsertEntry(PasswordEntry entry) async {
    final response = await bridge.upsertAutofillIndexEntry(
      request: frb.UpsertAutofillIndexEntryRequest(
        indexPath: indexPath,
        path: entry.path,
      ),
    );
    await _completeIncremental(response);
  }

  @override
  Future<void> moveEntry({
    required String oldPath,
    required String newPath,
    required bool recursive,
  }) async {
    final response = await bridge.moveAutofillIndexEntry(
      request: frb.MoveAutofillIndexEntryRequest(
        indexPath: indexPath,
        oldPath: oldPath,
        newPath: newPath,
        recursive: recursive,
      ),
    );
    await _completeIncremental(response);
  }

  @override
  Future<void> removeEntry({
    required String path,
    required bool recursive,
  }) async {
    final response = await bridge.removeAutofillIndexEntry(
      request: frb.RemoveAutofillIndexEntryRequest(
        indexPath: indexPath,
        path: path,
        recursive: recursive,
      ),
    );
    await _completeIncremental(response);
  }

  @override
  Future<void> reconcileIndex(List<PasswordEntry> entries) async {
    final response = await bridge.reconcileAutofillIndex(
      request: frb.ReconcileAutofillIndexRequest(
        indexPath: indexPath,
        storeId: currentStoreId?.call() ?? storeId,
        storeName: currentStoreName?.call() ?? storeName,
        root: currentStoreRoot?.call() ?? storeRoot,
      ),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    _status = AutofillStatus(
      available: true,
      indexedEntries: _passwordEntryCount(entries),
      message: 'Path-based autofill data is synchronized automatically',
    );
  }

  @override
  Future<void> useEncryptedLoginAndUrls(List<PasswordEntry> entries) async {
    final paths = entries
        .where((entry) => !entry.isDirectory)
        .map((entry) => entry.path)
        .toList(growable: false);
    if (paths.isEmpty) {
      throw const AutofillRepositoryException(
        'There are no password entries to read.',
      );
    }
    final response = await bridge.refreshAutofillIndexLoginAndUrls(
      request: frb.RefreshAutofillIndexLoginAndUrlsRequest(
        configPath: configPath,
        indexPath: indexPath,
        root: currentStoreRoot?.call() ?? storeRoot,
        pgpExecutable: pgpExecutable,
        passphrase: await _activePassphrase(),
      ),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    _status = AutofillStatus(
      available: _status.available,
      indexedEntries: _status.indexedEntries,
      kind: _status.kind,
      message:
          'Encrypted login and URL fields updated for ${paths.length} entries',
    );
  }

  @override
  Future<void> forgetEncryptedLoginAndUrls() async {
    final response = await bridge.forgetAutofillIndexLoginAndUrls(
      request: frb.ForgetAutofillIndexLoginAndUrlsRequest(indexPath: indexPath),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    _status = AutofillStatus(
      available: _status.available,
      indexedEntries: _status.indexedEntries,
      kind: _status.kind,
      message: 'Encrypted login and URL fields removed',
    );
  }

  @override
  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? appName,
    String? query,
    int limit = 10,
  }) async {
    final response = await bridge.queryAutofillCandidates(
      request: frb.AutofillQueryRequest(
        indexPath: indexPath,
        website: website,
        appName: appName,
        query: query,
        limit: limit,
      ),
    );
    _throwIfFailure(response.error);
    return response.candidates
        .map(_candidateFromBridge)
        .toList(growable: false);
  }

  @override
  Future<AutofillCredential?> resolveCredential(String path) async {
    final response = await bridge.resolveAutofillCredential(
      request: frb.AutofillCredentialRequest(
        configPath: configPath,
        indexPath: indexPath,
        root: currentStoreRoot?.call() ?? storeRoot,
        path: path,
        pgpExecutable: pgpExecutable,
        passphrase: await _activePassphrase(),
      ),
    );
    _throwIfFailure(response.error);
    final credential = response.credential;
    if (credential == null) return null;
    return AutofillCredential(
      path: credential.path,
      username: credential.username,
      password: credential.password,
    );
  }

  @override
  Future<void> publishPlatformState() => _serializePlatformState(() async {
    if (!forcePlatformPublication && !Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    final capturedRoot = currentStoreRoot?.call() ?? storeRoot;
    if (!_isCapturedStoreReady(capturedRoot)) {
      await _clearPlatformState();
      return;
    }
    // The app only loads the stored passphrase after a biometric unlock, so
    // native Autofill receives it only under the same condition.
    final biometricUnlock = securityRepository?.biometricUnlockEnabled ?? false;
    final passphrase =
        biometricUnlock ? await _storedPlatformPassphrase(capturedRoot) : null;
    if (!_isCapturedStoreReady(capturedRoot)) {
      await _clearPlatformState();
      return;
    }
    try {
      await _platformAutofillChannel.invokeMethod<void>('publishState', {
        'configPath': configPath,
        'indexPath': indexPath,
        'storeRoot': capturedRoot,
        'passphrase': passphrase,
        'biometricUnlock': biometricUnlock,
      });
    } on MissingPluginException {
      return;
    }
  });

  @override
  Future<void> openPlatformSettings() async {
    if (!forcePlatformPublication && !Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      await _platformAutofillChannel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      return;
    }
  }

  @override
  void recordSyncFailure(Object error) {
    _status = AutofillStatus(
      available: false,
      indexedEntries: _status.indexedEntries,
      kind: AutofillStatusKind.syncFailed,
      message:
          'Automatic Autofill sync failed: $error. It will retry on refresh.',
    );
  }

  @override
  Future<void> clearIndex() => _serializePlatformState(() async {
    Object? failure;
    StackTrace? failureStack;
    try {
      // Persist the native disabled tombstone before touching the shared index.
      await _clearPlatformState();
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    try {
      final response = await bridge.clearAutofillIndex(
        request: frb.ClearAutofillIndexRequest(indexPath: indexPath),
      );
      _throwIfFailure(response.error);
    } catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    }
    try {
      // This final tombstone wins over any publication queued before removal.
      await _clearPlatformState();
    } catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    } finally {
      _status = const AutofillStatus.disabled('Autofill data is cleared');
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  });

  Future<void> _completeIncremental(frb.UnitResponse response) async {
    _throwIfFailure(response.error);
    await publishPlatformState();
    if (_status.available) {
      _status = AutofillStatus(
        available: true,
        indexedEntries: _status.indexedEntries,
        message: 'Path-based autofill data is synchronized',
      );
    }
  }

  Future<String?> _activePassphrase() async {
    final passphrase = await securityRepository?.readActivePgpPassphrase();
    return passphrase?.passphrase;
  }

  Future<String?> _storedPlatformPassphrase(String capturedRoot) async {
    if (!_isCapturedStoreReady(capturedRoot)) return null;
    final passphrase = await securityRepository?.readPgpPassphrase();
    if (!_isCapturedStoreReady(capturedRoot) || passphrase == null) return null;
    final valid =
        await validatePgpPassphraseForCurrentStore?.call(
          passphrase.fingerprint,
          passphrase.passphrase,
        ) ==
        true;
    if (!_isCapturedStoreReady(capturedRoot) || !valid) return null;
    return passphrase.passphrase;
  }

  bool _isCapturedStoreReady(String capturedRoot) =>
      capturedRoot.trim().isNotEmpty &&
      currentStoreReady?.call() == true &&
      (currentStoreRoot?.call() ?? storeRoot) == capturedRoot;

  int _passwordEntryCount(List<PasswordEntry> entries) =>
      entries.where((entry) => !entry.isDirectory).length;

  AutofillCandidate _candidateFromBridge(frb.AutofillCandidateDto candidate) {
    return AutofillCandidate(
      path: candidate.path,
      displayName: candidate.displayName,
      username: candidate.username,
      matchKind: candidate.matchKind,
      matchValue: candidate.matchValue,
      score: candidate.score,
    );
  }

  void _throwIfFailure(frb.BridgeFailure? failure) {
    if (failure != null) {
      throw AutofillRepositoryException(failure.message);
    }
  }

  Future<T> _serializePlatformState<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _platformStateTail = _platformStateTail
        .catchError((_) {
          // One failed native operation must not poison the serialization tail.
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

  Future<void> _clearPlatformState() async {
    if (!forcePlatformPublication && !Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      await _platformAutofillChannel.invokeMethod<void>('clearState');
    } on MissingPluginException {
      return;
    }
  }
}

class FakeAutofillRepository implements AutofillRepository {
  FakeAutofillRepository({
    List<AutofillCandidate> candidates = const <AutofillCandidate>[],
    Map<String, AutofillCredential> credentials =
        const <String, AutofillCredential>{},
    this.operationError,
  }) : _candidates = List<AutofillCandidate>.of(candidates),
       _credentials = Map<String, AutofillCredential>.of(credentials);

  final List<AutofillCandidate> _candidates;
  final Map<String, AutofillCredential> _credentials;
  final Object? operationError;
  List<PasswordEntry> lastRebuiltEntries = const <PasswordEntry>[];
  List<String> lastEnrichedPaths = const <String>[];
  final List<String> operations = <String>[];
  bool cleared = false;
  AutofillStatus _status = const AutofillStatus.unavailable(
    'Autofill data has not been built',
  );

  @override
  AutofillStatus get status => _status;

  @override
  Future<void> rebuildIndex(List<PasswordEntry> entries) async {
    operations.add('rebuild');
    lastRebuiltEntries = List<PasswordEntry>.of(entries);
    cleared = false;
    _status = AutofillStatus(
      available: true,
      indexedEntries: entries.where((entry) => !entry.isDirectory).length,
      message: 'Path-based autofill data is up to date',
    );
  }

  @override
  Future<void> upsertEntry(PasswordEntry entry) async {
    operations.add('upsert:${entry.path}');
    final error = operationError;
    if (error != null) throw error;
  }

  @override
  Future<void> moveEntry({
    required String oldPath,
    required String newPath,
    required bool recursive,
  }) async {
    operations.add('move:$oldPath:$newPath:$recursive');
  }

  @override
  Future<void> removeEntry({
    required String path,
    required bool recursive,
  }) async {
    operations.add('remove:$path:$recursive');
  }

  @override
  Future<void> reconcileIndex(List<PasswordEntry> entries) async {
    operations.add('reconcile');
    final error = operationError;
    if (error != null) throw error;
    _status = AutofillStatus(
      available: true,
      indexedEntries: entries.where((entry) => !entry.isDirectory).length,
      message: 'Path-based autofill data is synchronized automatically',
    );
  }

  @override
  Future<void> useEncryptedLoginAndUrls(List<PasswordEntry> entries) async {
    final paths = entries
        .where((entry) => !entry.isDirectory)
        .map((entry) => entry.path)
        .toList(growable: false);
    if (paths.isEmpty) {
      throw const AutofillRepositoryException('There are no password entries.');
    }
    operations.add('enrich');
    lastEnrichedPaths = List<String>.of(paths);
  }

  @override
  Future<void> forgetEncryptedLoginAndUrls() async {
    operations.add('clear-enrichment');
  }

  @override
  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? appName,
    String? query,
    int limit = 10,
  }) async => _candidates.take(limit).toList(growable: false);

  @override
  Future<AutofillCredential?> resolveCredential(String path) async =>
      _credentials[path];

  @override
  Future<void> publishPlatformState() async {
    operations.add('publish');
  }

  @override
  Future<void> openPlatformSettings() async {
    operations.add('open-settings');
  }

  @override
  void recordSyncFailure(Object error) {
    _status = AutofillStatus(
      available: false,
      indexedEntries: _status.indexedEntries,
      kind: AutofillStatusKind.syncFailed,
      message:
          'Automatic Autofill sync failed: $error. It will retry on refresh.',
    );
  }

  @override
  Future<void> clearIndex() async {
    _candidates.clear();
    _credentials.clear();
    lastRebuiltEntries = const <PasswordEntry>[];
    lastEnrichedPaths = const <String>[];
    operations.add('clear');
    cleared = true;
    _status = const AutofillStatus.disabled('Autofill data is cleared');
  }
}
