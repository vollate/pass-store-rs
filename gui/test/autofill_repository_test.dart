import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/security_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native publication never persists a session-only passphrase', () async {
    const channel = MethodChannel('top.vollate.pars_gui/autofill');
    final published = <Map<Object?, Object?>>[];
    var clearCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'publishState') {
            published.add((call.arguments as Map).cast<Object?, Object?>());
          } else if (call.method == 'clearState') {
            clearCalls += 1;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final security = InMemorySecurityRepository();
    await security.startPgpSession(
      fingerprint: 'ABC',
      passphrase: 'session-only',
    );
    var currentRoot = '/tmp/store';
    var fingerprintUsable = true;
    String? validatedFingerprint;
    String? validatedPassphrase;
    final repository = BridgeAutofillRepository(
      bridge: _RecordingAutofillBridge(),
      configPath: '/tmp/pars.toml',
      indexPath: '/tmp/autofill.json',
      storeId: 'store-0',
      storeName: 'Personal',
      storeRoot: '/tmp/store',
      currentStoreRoot: () => currentRoot,
      currentStoreReady: () => currentRoot.isNotEmpty,
      validatePgpPassphraseForCurrentStore: (fingerprint, passphrase) async {
        validatedFingerprint = fingerprint;
        validatedPassphrase = passphrase;
        return fingerprintUsable;
      },
      securityRepository: security,
      forcePlatformPublication: true,
    );

    await repository.publishPlatformState();
    expect(published.last['passphrase'], isNull);

    await security.savePgpPassphrase(
      fingerprint: 'ABC',
      passphrase: 'explicitly-remembered',
    );
    await repository.publishPlatformState();
    expect(published.last['passphrase'], 'explicitly-remembered');
    expect(validatedFingerprint, 'ABC');
    expect(validatedPassphrase, 'explicitly-remembered');

    fingerprintUsable = false;
    await repository.publishPlatformState();
    expect(published.last['passphrase'], isNull);
    expect(
      (await security.readPgpPassphrase())?.passphrase,
      'explicitly-remembered',
    );

    currentRoot = '';
    await repository.publishPlatformState();
    expect(clearCalls, 1);
    expect(
      (await security.readPgpPassphrase())?.passphrase,
      'explicitly-remembered',
    );

    await security.clearPgpPassphrase();
    await repository.publishPlatformState();
    expect(clearCalls, 2);
  });

  test(
    'native clear wins over an in-flight publication and leaves no stale state',
    () async {
      const channel = MethodChannel('top.vollate.pars_gui/autofill');
      final nativeOperations = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeOperations.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final validationStarted = Completer<void>();
      final validationGate = Completer<void>();
      final security = InMemorySecurityRepository();
      await security.savePgpPassphrase(
        fingerprint: 'ABC',
        passphrase: 'remembered',
      );
      var currentRoot = '/tmp/store';
      var currentReady = true;
      final bridge = _RecordingAutofillBridge();
      final repository = BridgeAutofillRepository(
        bridge: bridge,
        configPath: '/tmp/pars.toml',
        indexPath: '/tmp/autofill.json',
        storeId: 'canonical-store',
        storeName: 'Personal',
        storeRoot: '/tmp/store',
        currentStoreRoot: () => currentRoot,
        currentStoreReady: () => currentReady,
        validatePgpPassphraseForCurrentStore: (fingerprint, passphrase) async {
          if (!validationStarted.isCompleted) validationStarted.complete();
          await validationGate.future;
          return true;
        },
        securityRepository: security,
        forcePlatformPublication: true,
      );

      final publication = repository.publishPlatformState();
      await validationStarted.future;
      currentReady = false;
      currentRoot = '';
      final clear = repository.clearIndex();
      final publicationQueuedAfterRemoval = repository.publishPlatformState();
      validationGate.complete();
      await Future.wait<void>(<Future<void>>[
        publication,
        clear,
        publicationQueuedAfterRemoval,
      ]);

      expect(nativeOperations, isNot(contains('publishState')));
      expect(nativeOperations.last, 'clearState');
      expect(
        bridge.calledMethods.where(
          (method) => method == 'clear_autofill_index',
        ),
        hasLength(1),
      );
      expect(repository.status.kind, AutofillStatusKind.disabled);
    },
  );

  test('path rebuild sends ranking metadata without secret inputs', () async {
    final bridge = _RecordingAutofillBridge();
    final securityRepository = InMemorySecurityRepository();
    await securityRepository.startPgpSession(
      fingerprint: 'ABC123',
      passphrase: 'must-not-be-read-for-rebuild',
    );
    final repository = BridgeAutofillRepository(
      bridge: bridge,
      configPath: '/tmp/pars.toml',
      indexPath: '/tmp/autofill.json',
      storeId: 'store-0',
      storeName: 'Personal',
      storeRoot: '/tmp/store',
      pgpExecutable: '/usr/bin/gpg',
      securityRepository: securityRepository,
    );

    await repository.rebuildIndex(const <PasswordEntry>[
      PasswordEntry(
        path: 'github.com/alice',
        displayName: 'alice',
        repoName: 'Personal',
        encryptedContent: '',
        isFavorite: true,
        lastUsedLabel: 'Recent',
      ),
      PasswordEntry(
        path: 'github.com',
        displayName: 'github.com',
        repoName: 'Personal',
        encryptedContent: '',
        isDirectory: true,
      ),
    ]);

    expect(bridge.calledMethods, contains('rebuild_autofill_index'));
    final request = bridge.lastRebuildRequest!;
    expect(request.indexPath, '/tmp/autofill.json');
    expect(request.storeId, 'store-0');
    expect(request.root, '/tmp/store');
    expect(request.entries, hasLength(1));
    expect(request.entries.single.path, 'github.com/alice');
    expect(request.entries.single.isFavorite, isTrue);
    expect(request.entries.single.recentRank, 0);
    expect(repository.status.indexedEntries, 1);
  });

  test(
    'incremental methods call only their replacement bridge operations',
    () async {
      final bridge = _RecordingAutofillBridge();
      final repository = _repository(bridge);
      const entry = PasswordEntry(
        path: 'github.com/alice',
        displayName: 'alice',
        repoName: 'Personal',
        encryptedContent: '',
        lastUsedLabel: 'Recent 3',
      );

      await repository.upsertEntry(entry);
      await repository.moveEntry(
        oldPath: 'github.com/alice',
        newPath: 'gitlab.com/alice',
        recursive: false,
      );
      await repository.removeEntry(path: 'old', recursive: true);
      await repository.patchRanking(const <PasswordEntry>[entry]);
      await repository.reconcileIndex(const <PasswordEntry>[entry]);

      expect(bridge.lastUpsertRequest?.entry.path, 'github.com/alice');
      expect(bridge.lastUpsertRequest?.entry.recentRank, 2);
      expect(bridge.lastMoveRequest?.oldPath, 'github.com/alice');
      expect(bridge.lastMoveRequest?.newPath, 'gitlab.com/alice');
      expect(bridge.lastRemoveRequest?.recursive, isTrue);
      expect(
        bridge.lastRankingRequest?.entries.single.path,
        'github.com/alice',
      );
      expect(bridge.lastReconcileRequest?.storeId, 'store-0');
      expect(bridge.calledMethods, isNot(contains('rebuild_autofill_index')));
    },
  );

  test(
    'website enrichment is explicit, selected, and secret-bearing',
    () async {
      final bridge = _RecordingAutofillBridge();
      final securityRepository = InMemorySecurityRepository();
      await securityRepository.startPgpSession(
        fingerprint: 'ABC123',
        passphrase: 'session-passphrase',
      );
      final repository = _repository(
        bridge,
        securityRepository: securityRepository,
      );

      await expectLater(
        repository.enrichWebsites(const <String>[]),
        throwsA(isA<AutofillRepositoryException>()),
      );
      await repository.enrichWebsites(const <String>['github.com/alice']);
      await repository.clearWebsiteEnrichment();

      expect(bridge.lastEnrichRequest?.paths, <String>['github.com/alice']);
      expect(bridge.lastEnrichRequest?.passphrase, 'session-passphrase');
      expect(bridge.lastClearWebsitesRequest?.paths, isEmpty);
    },
  );

  test('query maps app-name candidates and credential path username', () async {
    final bridge =
        _RecordingAutofillBridge()
          ..queryResponse = const frb.AutofillCandidatesResponse(
            candidates: <frb.AutofillCandidateDto>[
              frb.AutofillCandidateDto(
                path: 'GitHub/alice',
                displayName: 'GitHub',
                username: 'alice',
                matchKind: 'app_name',
                matchValue: 'github',
                score: 3650,
                isFavorite: true,
                recentRank: 0,
              ),
            ],
          )
          ..credentialResponse = const frb.AutofillCredentialResponse(
            credential: frb.AutofillCredentialDto(
              path: 'GitHub/alice',
              username: 'alice',
              password: 'secret',
            ),
          );
    final repository = _repository(bridge);

    final candidates = await repository.queryCandidates(
      appName: 'GitHub',
      limit: 5,
    );
    final credential = await repository.resolveCredential('GitHub/alice');

    expect(bridge.lastQueryRequest?.appName, 'GitHub');
    expect(bridge.lastQueryRequest?.limit, 5);
    expect(candidates.single.username, 'alice');
    expect(candidates.single.matchKind, 'app_name');
    expect(credential?.username, 'alice');
    expect(credential?.password, 'secret');
  });

  test(
    'root-mismatched reconcile disables native state and requires rebuild',
    () async {
      const channel = MethodChannel('top.vollate.pars_gui/autofill');
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bridge =
          _RecordingAutofillBridge()
            ..reconcileResponse = const frb.UnitResponse(
              error: frb.BridgeFailure(
                category: frb.BridgeFailureCategory.validationError,
                message:
                    'autofill index belongs to another store; rebuild required',
              ),
            );
      final repository = BridgeAutofillRepository(
        bridge: bridge,
        configPath: '/tmp/pars.toml',
        indexPath: '/tmp/autofill.json',
        storeId: 'canonical-store',
        storeName: 'Replacement',
        storeRoot: '/tmp/replacement',
        currentStoreReady: () => true,
        validatePgpPassphraseForCurrentStore: (_, _) async => false,
        forcePlatformPublication: true,
      );

      await expectLater(
        repository.reconcileIndex(const <PasswordEntry>[
          PasswordEntry(
            path: 'example.com/alice',
            displayName: 'alice',
            repoName: 'Replacement',
            encryptedContent: '',
          ),
        ]),
        throwsA(isA<AutofillRepositoryException>()),
      );

      expect(methods, <String>['clearState']);
      expect(repository.status.kind, AutofillStatusKind.needsRebuild);
    },
  );

  test('fake repository records path operations and clear', () async {
    final repository = FakeAutofillRepository(
      candidates: const <AutofillCandidate>[
        AutofillCandidate(
          path: 'github.com/alice',
          displayName: 'github.com',
          username: 'alice',
          matchKind: 'path_website',
          matchValue: 'github.com',
          score: 4000,
          isFavorite: false,
        ),
      ],
      credentials: const <String, AutofillCredential>{
        'github.com/alice': AutofillCredential(
          path: 'github.com/alice',
          username: 'alice',
          password: 'secret',
        ),
      },
    );
    const entries = <PasswordEntry>[
      PasswordEntry(
        path: 'github.com/alice',
        displayName: 'alice',
        repoName: 'Personal',
        encryptedContent: '',
      ),
    ];

    await repository.rebuildIndex(entries);
    await repository.upsertEntry(entries.single);
    await repository.patchRanking(entries);

    expect(repository.lastRebuiltEntries.single.path, 'github.com/alice');
    expect(repository.operations, contains('upsert:github.com/alice'));
    expect(
      await repository.queryCandidates(website: 'github.com'),
      hasLength(1),
    );
    expect(
      (await repository.resolveCredential('github.com/alice'))?.password,
      'secret',
    );

    await repository.clearIndex();
    expect(repository.cleared, isTrue);
    expect(await repository.queryCandidates(website: 'github.com'), isEmpty);
  });
}

BridgeAutofillRepository _repository(
  _RecordingAutofillBridge bridge, {
  SecurityRepository? securityRepository,
}) {
  return BridgeAutofillRepository(
    bridge: bridge,
    configPath: '/tmp/pars.toml',
    indexPath: '/tmp/autofill.json',
    storeId: 'store-0',
    storeName: 'Personal',
    storeRoot: '/tmp/store',
    securityRepository: securityRepository,
  );
}

class _RecordingAutofillBridge implements AutofillBridgeApi {
  final List<String> calledMethods = <String>[];
  frb.RebuildAutofillIndexRequest? lastRebuildRequest;
  frb.UpsertAutofillIndexEntryRequest? lastUpsertRequest;
  frb.MoveAutofillIndexEntryRequest? lastMoveRequest;
  frb.RemoveAutofillIndexEntryRequest? lastRemoveRequest;
  frb.PatchAutofillIndexRankingRequest? lastRankingRequest;
  frb.ReconcileAutofillIndexRequest? lastReconcileRequest;
  frb.EnrichAutofillIndexWebsitesRequest? lastEnrichRequest;
  frb.ClearAutofillIndexWebsitesRequest? lastClearWebsitesRequest;
  frb.AutofillQueryRequest? lastQueryRequest;
  frb.AutofillCredentialRequest? lastCredentialRequest;
  frb.ClearAutofillIndexRequest? lastClearRequest;
  frb.UnitResponse reconcileResponse = const frb.UnitResponse();
  frb.AutofillCandidatesResponse queryResponse =
      const frb.AutofillCandidatesResponse(
        candidates: <frb.AutofillCandidateDto>[],
      );
  frb.AutofillCredentialResponse credentialResponse =
      const frb.AutofillCredentialResponse();

  @override
  Future<frb.UnitResponse> rebuildAutofillIndex({
    required frb.RebuildAutofillIndexRequest request,
  }) async {
    calledMethods.add('rebuild_autofill_index');
    lastRebuildRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> upsertAutofillIndexEntry({
    required frb.UpsertAutofillIndexEntryRequest request,
  }) async {
    calledMethods.add('upsert_autofill_index_entry');
    lastUpsertRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> moveAutofillIndexEntry({
    required frb.MoveAutofillIndexEntryRequest request,
  }) async {
    calledMethods.add('move_autofill_index_entry');
    lastMoveRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> removeAutofillIndexEntry({
    required frb.RemoveAutofillIndexEntryRequest request,
  }) async {
    calledMethods.add('remove_autofill_index_entry');
    lastRemoveRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> patchAutofillIndexRanking({
    required frb.PatchAutofillIndexRankingRequest request,
  }) async {
    calledMethods.add('patch_autofill_index_ranking');
    lastRankingRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> reconcileAutofillIndex({
    required frb.ReconcileAutofillIndexRequest request,
  }) async {
    calledMethods.add('reconcile_autofill_index');
    lastReconcileRequest = request;
    return reconcileResponse;
  }

  @override
  Future<frb.UnitResponse> enrichAutofillIndexWebsites({
    required frb.EnrichAutofillIndexWebsitesRequest request,
  }) async {
    calledMethods.add('enrich_autofill_index_websites');
    lastEnrichRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> clearAutofillIndexWebsites({
    required frb.ClearAutofillIndexWebsitesRequest request,
  }) async {
    calledMethods.add('clear_autofill_index_websites');
    lastClearWebsitesRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.AutofillCandidatesResponse> queryAutofillCandidates({
    required frb.AutofillQueryRequest request,
  }) async {
    calledMethods.add('query_autofill_candidates');
    lastQueryRequest = request;
    return queryResponse;
  }

  @override
  Future<frb.AutofillCredentialResponse> resolveAutofillCredential({
    required frb.AutofillCredentialRequest request,
  }) async {
    calledMethods.add('resolve_autofill_credential');
    lastCredentialRequest = request;
    return credentialResponse;
  }

  @override
  Future<frb.UnitResponse> clearAutofillIndex({
    required frb.ClearAutofillIndexRequest request,
  }) async {
    calledMethods.add('clear_autofill_index');
    lastClearRequest = request;
    return const frb.UnitResponse();
  }
}
