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
    required this.matchKind,
    required this.matchValue,
    required this.score,
    required this.isFavorite,
    this.username,
    this.recentRank,
  });

  final String path;
  final String displayName;
  final String? username;
  final String matchKind;
  final String matchValue;
  final int score;
  final bool isFavorite;
  final int? recentRank;
}

class AutofillCredential {
  const AutofillCredential({
    required this.path,
    required this.password,
    this.username,
  });

  final String path;
  final String? username;
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

  Future<void> refreshIndex(List<PasswordEntry> entries);

  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? androidPackage,
    String? query,
    int limit = 10,
  });

  Future<AutofillCredential?> resolveCredential(String path);

  Future<void> clearIndex();
}

abstract interface class AutofillBridgeApi {
  Future<frb.UnitResponse> refreshAutofillIndex({
    required frb.RefreshAutofillIndexRequest request,
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
  Future<frb.UnitResponse> refreshAutofillIndex({
    required frb.RefreshAutofillIndexRequest request,
  }) => frb.refreshAutofillIndex(request: request);

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
    'Autofill data has not been refreshed',
  );

  @override
  AutofillStatus get status => _status;

  @override
  Future<void> refreshIndex(List<PasswordEntry> entries) async {
    final activeStoreId = currentStoreId?.call() ?? storeId;
    final activeStoreName = currentStoreName?.call() ?? storeName;
    final activeStoreRoot = currentStoreRoot?.call() ?? storeRoot;
    final passphrase = await _activePassphrase();
    final response = await bridge.refreshAutofillIndex(
      request: frb.RefreshAutofillIndexRequest(
        configPath: configPath,
        indexPath: indexPath,
        storeId: activeStoreId,
        storeName: activeStoreName,
        root: activeStoreRoot,
        pgpExecutable: pgpExecutable,
        passphrase: passphrase,
        entries: _entryMetadata(entries),
      ),
    );
    _throwIfFailure(response.error);
    await _publishPlatformState(
      storeRoot: activeStoreRoot,
      passphrase: passphrase,
    );
    _status = AutofillStatus(
      available: true,
      indexedEntries: entries.where((entry) => !entry.isDirectory).length,
      message: 'Autofill data is up to date',
    );
  }

  @override
  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? androidPackage,
    String? query,
    int limit = 10,
  }) async {
    final response = await bridge.queryAutofillCandidates(
      request: frb.AutofillQueryRequest(
        indexPath: indexPath,
        website: website,
        androidPackage: androidPackage,
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
    if (credential == null) {
      return null;
    }
    return AutofillCredential(
      path: credential.path,
      username: credential.username,
      password: credential.password,
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

  Future<String?> _activePassphrase() async {
    final passphrase = await securityRepository?.readActivePgpPassphrase();
    return passphrase?.passphrase;
  }

  List<frb.AutofillEntryMetadataDto> _entryMetadata(
    List<PasswordEntry> entries,
  ) {
    return <frb.AutofillEntryMetadataDto>[
      for (var index = 0; index < entries.length; index++)
        if (!entries[index].isDirectory)
          frb.AutofillEntryMetadataDto(
            path: entries[index].path,
            displayName: entries[index].displayName,
            isFavorite: entries[index].isFavorite,
            recentRank: entries[index].lastUsedLabel == null ? null : index,
          ),
    ];
  }

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

  Future<void> _publishPlatformState({
    required String storeRoot,
    required String? passphrase,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      await _platformAutofillChannel.invokeMethod<void>('publishState', {
        'configPath': configPath,
        'indexPath': indexPath,
        'storeRoot': storeRoot,
        'passphrase': passphrase,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _clearPlatformState() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
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
  }) : _candidates = List<AutofillCandidate>.of(candidates),
       _credentials = Map<String, AutofillCredential>.of(credentials);

  final List<AutofillCandidate> _candidates;
  final Map<String, AutofillCredential> _credentials;
  List<PasswordEntry> lastRefreshedEntries = const <PasswordEntry>[];
  bool cleared = false;
  AutofillStatus _status = const AutofillStatus.unavailable(
    'Autofill data has not been refreshed',
  );

  @override
  AutofillStatus get status => _status;

  @override
  Future<void> refreshIndex(List<PasswordEntry> entries) async {
    lastRefreshedEntries = List<PasswordEntry>.of(entries);
    cleared = false;
    _status = AutofillStatus(
      available: true,
      indexedEntries: entries.where((entry) => !entry.isDirectory).length,
      message: 'Autofill data is up to date',
    );
  }

  @override
  Future<List<AutofillCandidate>> queryCandidates({
    String? website,
    String? androidPackage,
    String? query,
    int limit = 10,
  }) async {
    return _candidates.take(limit).toList(growable: false);
  }

  @override
  Future<AutofillCredential?> resolveCredential(String path) async {
    return _credentials[path];
  }

  @override
  Future<void> clearIndex() async {
    _candidates.clear();
    _credentials.clear();
    cleared = true;
    _status = const AutofillStatus.unavailable('Autofill data is cleared');
  }
}
