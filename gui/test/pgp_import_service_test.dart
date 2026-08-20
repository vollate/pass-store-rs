import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/pgp_key_import.dart';
import 'package:pars_gui/services/key_repository.dart';
import 'package:pars_gui/services/pgp_import_service.dart';
import 'package:pars_gui/services/security_repository.dart';

const _passphrase = 'correct horse battery staple';

void main() {
  test('public import starts no session and stores no passphrase', () async {
    final keyRepository = _StubKeyRepository(
      inspection: _inspection(kind: PgpKeyKind.public),
    );
    final security = InMemorySecurityRepository();

    final completion = await importPgpKeyWithSecurity(
      keyRepository: keyRepository,
      securityRepository: security,
      source: PgpImportSource.text,
      value: '-----BEGIN PGP PUBLIC KEY BLOCK-----',
    );

    expect(completion.storage, PgpPassphraseStorageOutcome.notApplicable);
    expect(security.hasActivePgpSession, isFalse);
    expect(security.hasStoredPgpPassphrase, isFalse);
    expect(keyRepository.lastPassphrase, isNull);
  });

  test('unprotected private import skips passphrase work', () async {
    final keyRepository = _StubKeyRepository(
      inspection: _inspection(kind: PgpKeyKind.private, hasPrivateKey: true),
    );
    final security = InMemorySecurityRepository();

    final completion = await importPgpKeyWithSecurity(
      keyRepository: keyRepository,
      securityRepository: security,
      source: PgpImportSource.file,
      value: '/tmp/keys/plain.asc',
    );

    expect(completion.storage, PgpPassphraseStorageOutcome.notApplicable);
    expect(security.hasActivePgpSession, isFalse);
    expect(security.hasStoredPgpPassphrase, isFalse);
  });

  test('validated protected import starts a session for the returned fingerprint '
      'without durable storage', () async {
    // The repository returns a different fingerprint than the caller could guess, so this also
    // proves the session binds to what the backend confirmed.
    final keyRepository = _StubKeyRepository(
      inspection: _inspection(
        kind: PgpKeyKind.private,
        hasPrivateKey: true,
        requiresPassphrase: true,
        fingerprint: 'CONFIRMED ABC',
      ),
      fingerprint: 'CONFIRMED ABC',
    );
    final security = InMemorySecurityRepository();

    final completion = await importPgpKeyWithSecurity(
      keyRepository: keyRepository,
      securityRepository: security,
      source: PgpImportSource.text,
      value: '-----BEGIN PGP PRIVATE KEY BLOCK-----',
      passphrase: _passphrase,
    );

    expect(completion.storage, PgpPassphraseStorageOutcome.sessionOnly);
    expect(completion.key.fingerprint, 'CONFIRMED ABC');
    expect(security.hasActivePgpSession, isTrue);

    final session = await security.readActivePgpPassphrase();
    expect(session?.fingerprint, 'CONFIRMED ABC');
    expect(session?.passphrase, _passphrase);

    // Remember was not requested, so nothing is durable.
    expect(security.hasStoredPgpPassphrase, isFalse);
    expect(security.pgpPassphraseStorageEnabled, isFalse);
    expect(await security.readPgpPassphrase(), isNull);
  });

  test(
    'opting in enables secure storage and caches for the same fingerprint',
    () async {
      final keyRepository = _StubKeyRepository(
        inspection: _inspection(
          kind: PgpKeyKind.private,
          hasPrivateKey: true,
          requiresPassphrase: true,
        ),
      );
      final security = InMemorySecurityRepository();
      expect(security.pgpPassphraseStorageEnabled, isFalse);

      final completion = await importPgpKeyWithSecurity(
        keyRepository: keyRepository,
        securityRepository: security,
        source: PgpImportSource.text,
        value: '-----BEGIN PGP PRIVATE KEY BLOCK-----',
        passphrase: _passphrase,
        remember: true,
      );

      expect(completion.storage, PgpPassphraseStorageOutcome.remembered);
      expect(security.pgpPassphraseStorageEnabled, isTrue);

      final stored = await security.readPgpPassphrase();
      expect(stored?.fingerprint, completion.key.fingerprint);
      expect(stored?.passphrase, _passphrase);
      expect(security.hasActivePgpSession, isTrue);
    },
  );

  test(
    'secure-storage failure keeps the imported key and active session',
    () async {
      final keyRepository = _StubKeyRepository(
        inspection: _inspection(
          kind: PgpKeyKind.private,
          hasPrivateKey: true,
          requiresPassphrase: true,
        ),
      );
      final security = _FailingStorageSecurityRepository();

      final completion = await importPgpKeyWithSecurity(
        keyRepository: keyRepository,
        securityRepository: security,
        source: PgpImportSource.text,
        value: '-----BEGIN PGP PRIVATE KEY BLOCK-----',
        passphrase: _passphrase,
        remember: true,
      );

      expect(completion.storage, PgpPassphraseStorageOutcome.rememberFailed);
      expect(completion.rememberFailed, isTrue);
      // The key stays imported and usable; only remembering failed.
      expect(completion.key.fingerprint, isNotEmpty);
      expect(security.hasActivePgpSession, isTrue);
      expect(security.hasStoredPgpPassphrase, isFalse);
      expect(completion.storageError, isNotNull);
      expect(completion.storageError, isNot(contains(_passphrase)));
    },
  );

  test('import failures propagate and leave no session or cache', () async {
    final keyRepository = _StubKeyRepository(
      inspection: _inspection(
        kind: PgpKeyKind.private,
        requiresPassphrase: true,
      ),
      failure: const PgpImportException(
        PgpImportFailureKind.incorrectPassphrase,
        'the PGP private key passphrase is incorrect',
      ),
    );
    final security = InMemorySecurityRepository();

    await expectLater(
      importPgpKeyWithSecurity(
        keyRepository: keyRepository,
        securityRepository: security,
        source: PgpImportSource.text,
        value: '-----BEGIN PGP PRIVATE KEY BLOCK-----',
        passphrase: 'wrong',
        remember: true,
      ),
      throwsA(
        isA<PgpImportException>().having(
          (error) => error.kind,
          'kind',
          PgpImportFailureKind.incorrectPassphrase,
        ),
      ),
    );

    expect(security.hasActivePgpSession, isFalse);
    expect(security.hasStoredPgpPassphrase, isFalse);
  });
}

PgpKeyInspection _inspection({
  required PgpKeyKind kind,
  bool hasPrivateKey = false,
  bool requiresPassphrase = false,
  String fingerprint = 'IMPORTED PGP',
}) {
  return PgpKeyInspection(
    kind: kind,
    fingerprint: fingerprint,
    identity: 'Alice <alice@example.com>',
    hasPrivateKey: hasPrivateKey,
    requiresPassphrase: requiresPassphrase,
    armored: true,
  );
}

/// Minimal `KeyRepository` covering only the source-independent import surface.
class _StubKeyRepository implements KeyRepository {
  _StubKeyRepository({
    required this.inspection,
    this.fingerprint = 'IMPORTED PGP',
    this.failure,
  });

  final PgpKeyInspection inspection;
  final String fingerprint;
  final PgpImportException? failure;
  String? lastPassphrase;
  PgpImportSource? lastSource;

  PgpImportResult _result() {
    final error = failure;
    if (error != null) {
      throw error;
    }
    return PgpImportResult(
      key: KeyRecord(
        type: KeyRecordType.pgp,
        name: inspection.identity,
        fingerprint: fingerprint,
        source:
            inspection.isPrivate
                ? 'Imported private key'
                : 'Imported public key',
        hasPrivateKey: inspection.hasPrivateKey,
      ),
      inspection: inspection,
    );
  }

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async {
    lastSource = PgpImportSource.text;
    lastPassphrase = passphrase;
    return _result();
  }

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async {
    lastSource = PgpImportSource.file;
    lastPassphrase = passphrase;
    return _result();
  }

  @override
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async =>
      inspection;

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async => inspection;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Rejects durable writes while behaving normally for in-memory sessions.
class _FailingStorageSecurityRepository extends InMemorySecurityRepository {
  @override
  Future<void> savePgpPassphrase({
    required String fingerprint,
    required String passphrase,
  }) async {
    throw StateError('Keychain is unavailable');
  }
}
