import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/security_repository.dart';

void main() {
  test('bridge autofill repository refreshes index with entry metadata and passphrase', () async {
    final bridge = _RecordingAutofillBridge();
    final securityRepository = InMemorySecurityRepository();
    await securityRepository.startPgpSession(
      fingerprint: 'ABC123',
      passphrase: 'session-passphrase',
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

    await repository.refreshIndex(
      const <PasswordEntry>[
        PasswordEntry(
          path: 'work/github',
          displayName: 'GitHub',
          repoName: 'Personal',
          encryptedContent: '',
          isFavorite: true,
          lastUsedLabel: 'today',
        ),
        PasswordEntry(
          path: 'work',
          displayName: 'work',
          repoName: 'Personal',
          encryptedContent: '',
          isDirectory: true,
        ),
      ],
    );

    expect(bridge.calledMethods, contains('refresh_autofill_index'));
    final request = bridge.lastRefreshRequest!;
    expect(request.configPath, '/tmp/pars.toml');
    expect(request.indexPath, '/tmp/autofill.json');
    expect(request.storeId, 'store-0');
    expect(request.root, '/tmp/store');
    expect(request.pgpExecutable, '/usr/bin/gpg');
    expect(request.passphrase, 'session-passphrase');
    expect(request.entries, hasLength(1));
    expect(request.entries.single.path, 'work/github');
    expect(request.entries.single.displayName, 'GitHub');
    expect(request.entries.single.isFavorite, isTrue);
    expect(request.entries.single.recentRank, 0);
  });

  test('bridge autofill repository queries and maps candidates', () async {
    final bridge = _RecordingAutofillBridge()
      ..queryResponse = const frb.AutofillCandidatesResponse(
        candidates: <frb.AutofillCandidateDto>[
          frb.AutofillCandidateDto(
            path: 'work/github',
            displayName: 'GitHub',
            username: 'alice',
            matchKind: 'website',
            matchValue: 'example.com',
            score: 2150,
            isFavorite: true,
            recentRank: 0,
          ),
        ],
      );
    final repository = BridgeAutofillRepository(
      bridge: bridge,
      configPath: '/tmp/pars.toml',
      indexPath: '/tmp/autofill.json',
      storeId: 'store-0',
      storeName: 'Personal',
      storeRoot: '/tmp/store',
    );

    final candidates = await repository.queryCandidates(
      website: 'example.com',
      limit: 5,
    );

    expect(bridge.lastQueryRequest?.website, 'example.com');
    expect(bridge.lastQueryRequest?.limit, 5);
    expect(candidates.single.path, 'work/github');
    expect(candidates.single.username, 'alice');
    expect(candidates.single.matchKind, 'website');
    expect(candidates.single.score, 2150);
  });

  test('bridge autofill repository resolves credentials with active passphrase', () async {
    final bridge = _RecordingAutofillBridge()
      ..credentialResponse = const frb.AutofillCredentialResponse(
        credential: frb.AutofillCredentialDto(
          path: 'work/github',
          username: 'alice',
          password: 'secret',
        ),
      );
    final securityRepository = InMemorySecurityRepository();
    await securityRepository.startPgpSession(
      fingerprint: 'ABC123',
      passphrase: 'session-passphrase',
    );
    final repository = BridgeAutofillRepository(
      bridge: bridge,
      configPath: '/tmp/pars.toml',
      indexPath: '/tmp/autofill.json',
      storeId: 'store-0',
      storeName: 'Personal',
      storeRoot: '/tmp/store',
      securityRepository: securityRepository,
    );

    final credential = await repository.resolveCredential('work/github');

    expect(bridge.lastCredentialRequest?.path, 'work/github');
    expect(bridge.lastCredentialRequest?.passphrase, 'session-passphrase');
    expect(credential?.username, 'alice');
    expect(credential?.password, 'secret');
  });

  test('fake autofill repository records refreshes and clears candidates', () async {
    final repository = FakeAutofillRepository(
      candidates: const <AutofillCandidate>[
        AutofillCandidate(
          path: 'work/github',
          displayName: 'GitHub',
          matchKind: 'website',
          matchValue: 'example.com',
          score: 2000,
          isFavorite: false,
        ),
      ],
      credentials: const <String, AutofillCredential>{
        'work/github': AutofillCredential(
          path: 'work/github',
          username: 'alice',
          password: 'secret',
        ),
      },
    );

    await repository.refreshIndex(
      const <PasswordEntry>[
        PasswordEntry(
          path: 'work/github',
          displayName: 'GitHub',
          repoName: 'Personal',
          encryptedContent: '',
        ),
      ],
    );

    expect(repository.lastRefreshedEntries.single.path, 'work/github');
    expect(await repository.queryCandidates(website: 'example.com'), hasLength(1));
    expect((await repository.resolveCredential('work/github'))?.password, 'secret');

    await repository.clearIndex();
    expect(repository.cleared, isTrue);
    expect(await repository.queryCandidates(website: 'example.com'), isEmpty);
  });
}

class _RecordingAutofillBridge implements AutofillBridgeApi {
  final List<String> calledMethods = <String>[];
  frb.RefreshAutofillIndexRequest? lastRefreshRequest;
  frb.AutofillQueryRequest? lastQueryRequest;
  frb.AutofillCredentialRequest? lastCredentialRequest;
  frb.ClearAutofillIndexRequest? lastClearRequest;
  frb.AutofillCandidatesResponse queryResponse =
      const frb.AutofillCandidatesResponse(candidates: <frb.AutofillCandidateDto>[]);
  frb.AutofillCredentialResponse credentialResponse = const frb.AutofillCredentialResponse();

  @override
  Future<frb.UnitResponse> refreshAutofillIndex({
    required frb.RefreshAutofillIndexRequest request,
  }) async {
    calledMethods.add('refresh_autofill_index');
    lastRefreshRequest = request;
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
