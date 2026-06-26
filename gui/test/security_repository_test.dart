import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/security_repository.dart';

void main() {
  group('GestureVerifier', () {
    test('matches only the captured gesture order', () {
      final verifier = GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]);

      expect(verifier.matches(const <int>[0, 1, 2, 5]), isTrue);
      expect(verifier.matches(const <int>[0, 1, 5, 2]), isFalse);
    });

    test('rejects short or immediately repeated gestures', () {
      expect(
        () => GestureVerifier.fromPattern(const <int>[0, 1, 2]),
        throwsArgumentError,
      );
      expect(
        () => GestureVerifier.fromPattern(const <int>[0, 1, 1, 2]),
        throwsArgumentError,
      );
    });

    test('allows deliberate node jumps in gesture passwords', () {
      final verifier = GestureVerifier.fromPattern(const <int>[1, 0, 1, 2]);

      expect(verifier.matches(const <int>[1, 0, 1, 2]), isTrue);
      expect(verifier.matches(const <int>[1, 1, 1, 2]), isFalse);
    });
  });

  group('InMemorySecurityRepository', () {
    test('locks when no active app session exists', () {
      final repository = InMemorySecurityRepository.withPattern(const <int>[
        0,
        1,
        2,
        5,
      ]);

      expect(repository.shouldLock(DateTime(2026)), isTrue);
    });

    test('locks after auto-lock timeout', () async {
      final repository = InMemorySecurityRepository.withPattern(const <int>[
        0,
        1,
        2,
        5,
      ], autoLockTimeout: const Duration(minutes: 5));
      await repository.markUnlocked(DateTime(2026));

      expect(repository.shouldLock(DateTime(2026, 1, 1, 0, 4)), isFalse);
      expect(repository.shouldLock(DateTime(2026, 1, 1, 0, 5)), isTrue);
    });

    test('never auto-locks when timeout is disabled', () async {
      final repository = InMemorySecurityRepository.withPattern(const <int>[
        0,
        1,
        2,
        5,
      ], autoLockTimeout: Duration.zero);
      await repository.markUnlocked(DateTime(2026));

      expect(repository.shouldLock(DateTime(2026, 1, 2)), isFalse);
    });
  });

  group('SecureStorageSecurityRepository', () {
    test('persists gesture verifier and settings in secure storage', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.saveGestureVerifier(
        GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      );
      await repository.setLockOnResume(true);
      await repository.setAutoLockTimeout(Duration.zero);

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(reloaded.hasGestureVerifier, isTrue);
      expect(await reloaded.verifyGesture(const <int>[0, 1, 2, 5]), isTrue);
      expect(await reloaded.verifyGesture(const <int>[0, 1, 5, 2]), isFalse);
      expect(reloaded.lockOnResume, isTrue);
      expect(reloaded.autoLockTimeout, Duration.zero);
      await reloaded.markUnlocked(DateTime(2026));
      expect(reloaded.shouldLock(DateTime(2026, 1, 2)), isFalse);
    });

    test('persists PGP session expiration setting', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.setPgpSessionExpiration(PgpSessionExpiration.oneHour);

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(reloaded.pgpSessionExpiration, PgpSessionExpiration.oneHour);
    });

    test('persists onboarding completion setting', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(repository.onboardingComplete, isFalse);

      await repository.setOnboardingComplete(true);

      final completed = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(completed.onboardingComplete, isTrue);

      await completed.setOnboardingComplete(false);

      final reset = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(reset.onboardingComplete, isFalse);
    });

    test('does not persist active unlock sessions', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.saveGestureVerifier(
        GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      );
      await repository.markUnlocked(DateTime(2026));

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(repository.shouldLock(DateTime(2026)), isFalse);
      expect(reloaded.shouldLock(DateTime(2026)), isTrue);
    });

    test('enabling biometric unlock authenticates before persisting', () async {
      final storage = _FakeSecureStorageAdapter();
      final biometrics = _FakeBiometricAuthAdapter(available: true);
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: biometrics,
      );

      await repository.setBiometricUnlockEnabled(true);

      expect(biometrics.authenticateCount, 1);
      expect(repository.biometricUnlockEnabled, isTrue);

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(available: true),
      );
      expect(reloaded.biometricUnlockEnabled, isTrue);
    });

    test(
      'does not enable biometric unlock when authentication fails',
      () async {
        final storage = _FakeSecureStorageAdapter();
        final biometrics = _FakeBiometricAuthAdapter(
          available: true,
          authenticateResult: false,
        );
        final repository = await SecureStorageSecurityRepository.load(
          storage: storage,
          biometricAuth: biometrics,
        );

        await expectLater(
          repository.setBiometricUnlockEnabled(true),
          throwsStateError,
        );

        expect(biometrics.authenticateCount, 1);
        expect(repository.biometricUnlockEnabled, isFalse);

        final reloaded = await SecureStorageSecurityRepository.load(
          storage: storage,
          biometricAuth: _FakeBiometricAuthAdapter(available: true),
        );
        expect(reloaded.biometricUnlockEnabled, isFalse);
      },
    );

    test('unlocks with biometrics when enabled and available', () async {
      final storage = _FakeSecureStorageAdapter();
      final biometrics = _FakeBiometricAuthAdapter(available: true);
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: biometrics,
      );

      await repository.saveGestureVerifier(
        GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      );
      await repository.setBiometricUnlockEnabled(true);

      expect(
        await repository.biometricUnlockStatus(),
        BiometricUnlockStatus.available,
      );
      expect(await repository.unlockWithBiometrics(), isTrue);
      expect(repository.shouldLock(DateTime.now()), isFalse);
      expect(biometrics.authenticateCount, 2);
    });

    test(
      'biometric unlock starts PGP session from cached passphrase',
      () async {
        final biometrics = _FakeBiometricAuthAdapter(available: true);
        final repository = await SecureStorageSecurityRepository.load(
          storage: _FakeSecureStorageAdapter(),
          biometricAuth: biometrics,
        );

        await repository.saveGestureVerifier(
          GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
        );
        await repository.setBiometricUnlockEnabled(true);
        await repository.savePgpPassphrase(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        );

        expect(await repository.unlockWithBiometrics(), isTrue);
        expect(repository.hasActivePgpSession, isTrue);
        expect(
          await repository.readActivePgpPassphrase(),
          const PgpPassphraseCache(
            fingerprint: 'ABC123',
            passphrase: 'pgp-passphrase',
          ),
        );

        await repository.markLocked();

        expect(repository.hasActivePgpSession, isFalse);
        expect(await repository.readActivePgpPassphrase(), isNull);
      },
    );

    test('expires active PGP session after selected timeout', () async {
      final repository = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.setPgpSessionExpiration(
        PgpSessionExpiration.fiveMinutes,
      );
      await repository.startPgpSession(
        fingerprint: 'ABC123',
        passphrase: 'pgp-passphrase',
      );

      expect(repository.hasActivePgpSession, isTrue);

      await repository.expirePgpSessionIfNeeded(
        DateTime.now().add(const Duration(minutes: 4)),
      );

      expect(repository.hasActivePgpSession, isTrue);

      await repository.expirePgpSessionIfNeeded(
        DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(repository.hasActivePgpSession, isFalse);
      expect(await repository.readActivePgpPassphrase(), isNull);
    });

    test('immediate PGP session expiration clears session at start', () async {
      final repository = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.setPgpSessionExpiration(
        PgpSessionExpiration.immediately,
      );
      await repository.startPgpSession(
        fingerprint: 'ABC123',
        passphrase: 'pgp-passphrase',
      );

      expect(repository.hasActivePgpSession, isFalse);
      expect(await repository.readActivePgpPassphrase(), isNull);
    });

    test('until app exit PGP session does not expire by time', () async {
      final repository = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.setPgpSessionExpiration(
        PgpSessionExpiration.untilAppExit,
      );
      await repository.startPgpSession(
        fingerprint: 'ABC123',
        passphrase: 'pgp-passphrase',
      );
      await repository.expirePgpSessionIfNeeded(
        DateTime.now().add(const Duration(days: 1)),
      );

      expect(repository.hasActivePgpSession, isTrue);
      expect(
        await repository.readActivePgpPassphrase(),
        const PgpPassphraseCache(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        ),
      );
    });

    test('keeps session locked when biometric authentication fails', () async {
      final biometrics = _FakeBiometricAuthAdapter(
        available: true,
        authenticateResults: const <bool>[true, false],
      );
      final repository = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: biometrics,
      );

      await repository.saveGestureVerifier(
        GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      );
      await repository.setBiometricUnlockEnabled(true);

      expect(await repository.unlockWithBiometrics(), isFalse);
      expect(repository.shouldLock(DateTime.now()), isTrue);
      expect(biometrics.authenticateCount, 2);
    });

    test(
      'keeps biometrics unavailable when the platform cannot use them',
      () async {
        final repository = await SecureStorageSecurityRepository.load(
          storage: _FakeSecureStorageAdapter(),
          biometricAuth: _FakeBiometricAuthAdapter(available: false),
        );

        await expectLater(
          repository.setBiometricUnlockEnabled(true),
          throwsStateError,
        );

        expect(
          await repository.biometricUnlockStatus(),
          BiometricUnlockStatus.unavailable,
        );
        expect(await repository.unlockWithBiometrics(), isFalse);
      },
    );

    test('stores and clears PGP passphrase through secure storage', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.savePgpPassphrase(
        fingerprint: 'ABC123',
        passphrase: 'pgp-passphrase',
      );

      expect(repository.pgpPassphraseStorageEnabled, isTrue);
      expect(repository.hasStoredPgpPassphrase, isTrue);
      expect(
        await repository.readPgpPassphrase(),
        const PgpPassphraseCache(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        ),
      );

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(reloaded.pgpPassphraseStorageEnabled, isTrue);
      expect(reloaded.hasStoredPgpPassphrase, isTrue);
      expect(
        await reloaded.readPgpPassphrase(),
        const PgpPassphraseCache(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        ),
      );

      await reloaded.clearPgpPassphrase();

      expect(reloaded.hasStoredPgpPassphrase, isFalse);
      expect(await reloaded.readPgpPassphrase(), isNull);
    });

    test('disabling PGP passphrase storage clears cached passphrase', () async {
      final repository = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.savePgpPassphrase(
        fingerprint: 'ABC123',
        passphrase: 'pgp-passphrase',
      );
      await repository.setPgpPassphraseStorageEnabled(false);

      expect(repository.pgpPassphraseStorageEnabled, isFalse);
      expect(repository.hasStoredPgpPassphrase, isFalse);
      expect(await repository.readPgpPassphrase(), isNull);
    });

    test('legacy unbound PGP passphrase cache is cleared on load', () async {
      final storage = _FakeSecureStorageAdapter();
      await storage.write(
        key: 'pars.security.pgp_passphrase_storage_enabled.v1',
        value: '1',
      );
      await storage.write(
        key: 'pars.security.pgp_passphrase.v1',
        value: 'legacy-passphrase',
      );

      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(repository.hasStoredPgpPassphrase, isFalse);
      expect(await repository.readPgpPassphrase(), isNull);
    });

    test(
      'clears matching PGP passphrase cache and active session only',
      () async {
        final repository = await SecureStorageSecurityRepository.load(
          storage: _FakeSecureStorageAdapter(),
          biometricAuth: _FakeBiometricAuthAdapter(),
        );

        await repository.savePgpPassphrase(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        );
        await repository.startPgpSession(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        );

        await repository.clearPgpPassphraseForFingerprint('DEF456');

        expect(repository.hasStoredPgpPassphrase, isTrue);
        expect(repository.hasActivePgpSession, isTrue);

        await repository.clearPgpPassphraseForFingerprint('ABC123');

        expect(repository.hasStoredPgpPassphrase, isFalse);
        expect(repository.hasActivePgpSession, isFalse);
        expect(await repository.readPgpPassphrase(), isNull);
        expect(await repository.readActivePgpPassphrase(), isNull);
      },
    );
  });
}

class _FakeSecureStorageAdapter implements SecureStorageAdapter {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FakeBiometricAuthAdapter implements BiometricAuthAdapter {
  _FakeBiometricAuthAdapter({
    this.available = false,
    this.authenticateResult = true,
    List<bool>? authenticateResults,
  }) : _authenticateResults = authenticateResults ?? const <bool>[];

  final bool available;
  final bool authenticateResult;
  final List<bool> _authenticateResults;
  int authenticateCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    authenticateCount += 1;
    if (authenticateCount <= _authenticateResults.length) {
      return _authenticateResults[authenticateCount - 1];
    }
    return authenticateResult;
  }
}
