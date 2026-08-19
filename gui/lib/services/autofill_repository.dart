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
    required this.isFavorite,
    this.recentRank,
  });

  final String path;
  final String displayName;
  final String username;
  final String matchKind;
  final String matchValue;
  final int score;
  final bool isFavorite;
  final int? recentRank;
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

class AutofillStatus {
  const AutofillStatus({
    required this.available,
    required this.indexedEntries,
    this.message,
  });

  const AutofillStatus.unavailable(this.message)
    : available = false,
      indexedEntries = 0;

  final bool available;
  final int indexedEntries;
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

  Future<void> patchRanking(List<PasswordEntry> entries);

  Future<void> reconcileIndex(List<PasswordEntry> entries);

  Future<void> enrichWebsites(List<String> paths);

  Future<void> clearWebsiteEnrichment([List<String> paths = const <String>[]]);

  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? appName,
    String? query,
    int limit = 10,
  });

  Future<AutofillCredential?> resolveCredential(String path);

  Future<void> publishPlatformState();

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

  Future<frb.UnitResponse> patchAutofillIndexRanking({
    required frb.PatchAutofillIndexRankingRequest request,
  });

  Future<frb.UnitResponse> reconcileAutofillIndex({
    required frb.ReconcileAutofillIndexRequest request,
  });

  Future<frb.UnitResponse> enrichAutofillIndexWebsites({
    required frb.EnrichAutofillIndexWebsitesRequest request,
  });

  Future<frb.UnitResponse> clearAutofillIndexWebsites({
    required frb.ClearAutofillIndexWebsitesRequest request,
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
  Future<frb.UnitResponse> patchAutofillIndexRanking({
    required frb.PatchAutofillIndexRankingRequest request,
  }) => frb.patchAutofillIndexRanking(request: request);

  @override
  Future<frb.UnitResponse> reconcileAutofillIndex({
    required frb.ReconcileAutofillIndexRequest request,
  }) => frb.reconcileAutofillIndex(request: request);

  @override
  Future<frb.UnitResponse> enrichAutofillIndexWebsites({
    required frb.EnrichAutofillIndexWebsitesRequest request,
  }) => frb.enrichAutofillIndexWebsites(request: request);

  @override
  Future<frb.UnitResponse> clearAutofillIndexWebsites({
    required frb.ClearAutofillIndexWebsitesRequest request,
  }) => frb.clearAutofillIndexWebsites(request: request);

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
  AutofillStatus _status = const AutofillStatus.unavailable(
    'Autofill data has not been built',
  );

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
        entries: _entryMetadata(entries),
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
        entry: _metadataForEntry(entry),
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
  Future<void> patchRanking(List<PasswordEntry> entries) async {
    if (entries.isEmpty) return;
    final response = await bridge.patchAutofillIndexRanking(
      request: frb.PatchAutofillIndexRankingRequest(
        indexPath: indexPath,
        entries: _entryMetadata(entries),
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
        entries: _entryMetadata(entries),
      ),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    if (_status.available) {
      _status = AutofillStatus(
        available: true,
        indexedEntries: _passwordEntryCount(entries),
        message: 'Path-based autofill data is synchronized',
      );
    }
  }

  @override
  Future<void> enrichWebsites(List<String> paths) async {
    if (paths.isEmpty) {
      throw const AutofillRepositoryException(
        'Select at least one entry before reading encrypted URL fields.',
      );
    }
    final response = await bridge.enrichAutofillIndexWebsites(
      request: frb.EnrichAutofillIndexWebsitesRequest(
        configPath: configPath,
        indexPath: indexPath,
        root: currentStoreRoot?.call() ?? storeRoot,
        pgpExecutable: pgpExecutable,
        passphrase: await _activePassphrase(),
        paths: paths,
      ),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    _status = AutofillStatus(
      available: _status.available,
      indexedEntries: _status.indexedEntries,
      message: 'Encrypted website aliases updated for ${paths.length} entries',
    );
  }

  @override
  Future<void> clearWebsiteEnrichment([
    List<String> paths = const <String>[],
  ]) async {
    final response = await bridge.clearAutofillIndexWebsites(
      request: frb.ClearAutofillIndexWebsitesRequest(
        indexPath: indexPath,
        paths: paths,
      ),
    );
    _throwIfFailure(response.error);
    await publishPlatformState();
    _status = AutofillStatus(
      available: _status.available,
      indexedEntries: _status.indexedEntries,
      message: 'Encrypted website aliases cleared',
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
  Future<void> publishPlatformState() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _platformAutofillChannel.invokeMethod<void>('publishState', {
        'configPath': configPath,
        'indexPath': indexPath,
        'storeRoot': currentStoreRoot?.call() ?? storeRoot,
        'passphrase': await _activePassphrase(),
      });
    } on MissingPluginException {
      return;
    }
  }

  @override
  void recordSyncFailure(Object error) {
    _status = AutofillStatus(
      available: _status.available,
      indexedEntries: _status.indexedEntries,
      message: 'Autofill sync failed: $error. Rebuild it from Settings.',
    );
  }

  @override
  Future<void> clearIndex() async {
    final response = await bridge.clearAutofillIndex(
      request: frb.ClearAutofillIndexRequest(indexPath: indexPath),
    );
    _throwIfFailure(response.error);
    await _clearPlatformState();
    _status = const AutofillStatus.unavailable('Autofill data is cleared');
  }

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

  List<frb.AutofillEntryMetadataDto> _entryMetadata(
    List<PasswordEntry> entries,
  ) => <frb.AutofillEntryMetadataDto>[
    for (final entry in entries)
      if (!entry.isDirectory) _metadataForEntry(entry),
  ];

  frb.AutofillEntryMetadataDto _metadataForEntry(PasswordEntry entry) {
    return frb.AutofillEntryMetadataDto(
      path: entry.path,
      isFavorite: entry.isFavorite,
      recentRank: _recentRank(entry.lastUsedLabel),
    );
  }

  int? _recentRank(String? label) {
    if (label == null) return null;
    if (label == 'Recent') return 0;
    final match = RegExp(r'^Recent (\d+)$').firstMatch(label);
    final position = match == null ? null : int.tryParse(match.group(1)!);
    return position == null ? null : position - 1;
  }

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
      isFavorite: candidate.isFavorite,
      recentRank: candidate.recentRank,
    );
  }

  void _throwIfFailure(frb.BridgeFailure? failure) {
    if (failure != null) {
      throw AutofillRepositoryException(failure.message);
    }
  }

  Future<void> _clearPlatformState() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
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
  List<PasswordEntry> lastRankingEntries = const <PasswordEntry>[];
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
  Future<void> patchRanking(List<PasswordEntry> entries) async {
    operations.add('ranking');
    lastRankingEntries = List<PasswordEntry>.of(entries);
  }

  @override
  Future<void> reconcileIndex(List<PasswordEntry> entries) async {
    operations.add('reconcile');
    final error = operationError;
    if (error != null) throw error;
  }

  @override
  Future<void> enrichWebsites(List<String> paths) async {
    if (paths.isEmpty) {
      throw const AutofillRepositoryException('Select at least one entry.');
    }
    operations.add('enrich');
    lastEnrichedPaths = List<String>.of(paths);
  }

  @override
  Future<void> clearWebsiteEnrichment([
    List<String> paths = const <String>[],
  ]) async {
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
  void recordSyncFailure(Object error) {
    _status = AutofillStatus(
      available: _status.available,
      indexedEntries: _status.indexedEntries,
      message: 'Autofill sync failed: $error. Rebuild it from Settings.',
    );
  }

  @override
  Future<void> clearIndex() async {
    _candidates.clear();
    _credentials.clear();
    operations.add('clear');
    cleared = true;
    _status = const AutofillStatus.unavailable('Autofill data is cleared');
  }
}
