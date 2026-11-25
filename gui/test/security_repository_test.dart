import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/security_repository.dart';

void main() {
  group('PinVerifier', () {
    test('salts every verifier and round-trips through storage', () {
      final first = PinVerifier.fromPin('123456', iterations: 1000);
      final second = PinVerifier.fromPin('123456', iterations: 1000);

      expect(first.value, isNot(second.value));
      expect(first.value, isNot(contains('123456')));
      final restored = PinVerifier.fromStoredValue(first.value);
      expect(restored.matches('123456'), isTrue);
      expect(restored.matches('123457'), isFalse);
      expect(restored.matches('12345'), isFalse);
      expect(restored.matches('abcdef'), isFalse);
    });

    test('rejects invalid PIN lengths, non-digits, and malformed values', () {
      for (final invalid in <String>['', '12345', '1234567', '12345a', ' 12345']) {
        expect(
          () => PinVerifier.fromPin(invalid, iterations: 1000),
          throwsArgumentError,
          reason: invalid,
        );
      }
      for (final value in <String>[
        '',
        'pbkdf2-sha256',
        r'md5$1$c2FsdA==$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
        r'pbkdf2-sha256$0$c2FsdA==$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
        r'pbkdf2-sha256$4096$$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
        r'pbkdf2-sha256$4096$c2FsdA==$c2hvcnQ=',
        r'pbkdf2-sha256$4096$not base64$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
      ]) {
        expect(
          () => PinVerifier.fromStoredValue(value),
          throwsArgumentError,
          reason: value,
        );
      }
    });
  });

  group('PasswordVerifier', () {
    test('derives PBKDF2-HMAC-SHA256', () {
      // RFC 7914 / common test vector: P="password", S="salt", c=4096.
      final verifier = PasswordVerifier.fromStoredValue(
        r'pbkdf2-sha256$4096$c2FsdA==$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
      );

      expect(verifier.matches('password'), isTrue);
      expect(verifier.matches('Password'), isFalse);
    });

    test('salts every verifier and round-trips through storage', () {
      final first = PasswordVerifier.fromPassword(
        'correct horse',
        iterations: 1000,
      );
      final second = PasswordVerifier.fromPassword(
        'correct horse',
        iterations: 1000,
      );

      expect(first.value, isNot(second.value));
      expect(first.value, isNot(contains('correct horse')));
      final restored = PasswordVerifier.fromStoredValue(first.value);
      expect(restored.matches('correct horse'), isTrue);
      expect(restored.matches('correct horsf'), isFalse);
    });

    test('rejects short passwords and malformed stored values', () {
      expect(() => PasswordVerifier.fromPassword('short'), throwsArgumentError);
      for (final value in <String>[
        '',
        'pbkdf2-sha256',
        r'md5$1$c2FsdA==$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
        r'pbkdf2-sha256$0$c2FsdA==$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
        r'pbkdf2-sha256$4096$$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
        r'pbkdf2-sha256$4096$c2FsdA==$c2hvcnQ=',
        r'pbkdf2-sha256$4096$not base64$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=',
      ]) {
        expect(
          () => PasswordVerifier.fromStoredValue(value),
          throwsArgumentError,
          reason: value,
        );
      }
    });
  });

  group('platformDefaultUnlockMethod', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('uses a password on desktops and a PIN on phones and tablets', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final desktop = <TargetPlatform>{
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(platform);
        expect(
          platformDefaultUnlockMethod(),
          desktop ? LocalUnlockMethod.password : LocalUnlockMethod.pin,
          reason: platform.name,
        );
      }
    });
  });

  group('InMemorySecurityRepository', () {
    test('saving one unlock method replaces the other', () async {
      final repository = InMemorySecurityRepository.withPin(
        '123456',
        onboardingComplete: false,
      );

      expect(repository.unlockMethod, LocalUnlockMethod.pin);
      await repository.savePassword('correct horse');
      expect(repository.unlockMethod, LocalUnlockMethod.password);
      expect(repository.hasPinVerifier, isFalse);
      expect(await repository.verifyPin('123456'), isFalse);
      expect(repository.shouldLock(DateTime(2026)), isTrue);

      await repository.savePin('654321');
      expect(repository.unlockMethod, LocalUnlockMethod.pin);
      expect(repository.hasPasswordVerifier, isFalse);
      expect(await repository.verifyPassword('correct horse'), isFalse);
      expect(await repository.verifyPin('654321'), isTrue);
    });

    test('locks when no active app session exists', () {
      final repository = InMemorySecurityRepository.withPin('123456');

      expect(repository.shouldLock(DateTime(2026)), isTrue);
    });

    test('locks after auto-lock timeout', () async {
      final repository = InMemorySecurityRepository.withPin(
        '123456',
        autoLockTimeout: const Duration(minutes: 5),
      );
      await repository.markUnlocked(DateTime(2026));

      expect(repository.shouldLock(DateTime(2026, 1, 1, 0, 4)), isFalse);
      expect(repository.shouldLock(DateTime(2026, 1, 1, 0, 5)), isTrue);
    });

    test('never auto-locks when timeout is disabled', () async {
      final repository = InMemorySecurityRepository.withPin(
        '123456',
        autoLockTimeout: Duration.zero,
      );
      await repository.markUnlocked(DateTime(2026));

      expect(repository.shouldLock(DateTime(2026, 1, 2)), isFalse);
    });
  });

  group('SecureStorageSecurityRepository', () {
    test('persists PIN verifier and settings in secure storage', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      await repository.savePin('123456');
      await repository.setLockOnResume(true);
      await repository.setAutoLockTimeout(Duration.zero);

      expect(storage.values.any((value) => value.contains('123456')), isFalse);
      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(reloaded.hasPinVerifier, isTrue);
      expect(reloaded.unlockMethod, LocalUnlockMethod.pin);
      expect(await reloaded.verifyPin('123456'), isTrue);
      expect(await reloaded.verifyPin('123457'), isFalse);
      expect(reloaded.lockOnResume, isTrue);
      expect(reloaded.autoLockTimeout, Duration.zero);
      await reloaded.markUnlocked(DateTime(2026));
      expect(reloaded.shouldLock(DateTime(2026, 1, 2)), isFalse);
    });

    test('persists a password verifier and drops the PIN', () async {
      final storage = _FakeSecureStorageAdapter();
      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );
      await repository.savePin('123456');

      await repository.savePassword('correct horse');

      expect(storage.keys, isNot(contains('pars.security.pin_verifier.v1')));
      expect(
        storage.values.any((value) => value.contains('correct horse')),
        isFalse,
      );
      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );
      expect(reloaded.unlockMethod, LocalUnlockMethod.password);
      expect(reloaded.hasPinVerifier, isFalse);
      expect(await reloaded.verifyPassword('correct horse'), isTrue);
      expect(await reloaded.verifyPassword('correct horsf'), isFalse);
      expect(reloaded.shouldLock(DateTime(2026)), isTrue);

      await reloaded.savePin('654321');
      expect(
        storage.keys,
        isNot(contains('pars.security.password_verifier.v1')),
      );
    });

    test('clears legacy gesture verifier and corrupted verifiers on load', () async {
      final storage = _FakeSecureStorageAdapter();
      await storage.write(
        key: 'pars.security.gesture_verifier.v1',
        value: 'deadbeef',
      );
      await storage.write(
        key: 'pars.security.pin_verifier.v1',
        value: 'garbage',
      );
      await storage.write(
        key: 'pars.security.password_verifier.v1',
        value: 'garbage',
      );

      final repository = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(repository.unlockMethod, isNull);
      expect(
        storage.keys,
        isNot(contains('pars.security.gesture_verifier.v1')),
      );
      expect(storage.keys, isNot(contains('pars.security.pin_verifier.v1')));
      expect(
        storage.keys,
        isNot(contains('pars.security.password_verifier.v1')),
      );
    });

    test('reports active biometric kind from the biometric adapter', () async {
      final faceRepo = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: _FakeBiometricAuthAdapter(
          available: true,
          kind: BiometricKind.face,
        ),
      );
      final fingerRepo = await SecureStorageSecurityRepository.load(
        storage: _FakeSecureStorageAdapter(),
        biometricAuth: _FakeBiometricAuthAdapter(
          available: true,
          kind: BiometricKind.fingerprint,
        ),
      );

      expect(await faceRepo.biometricKind(), BiometricKind.face);
      expect(await fingerRepo.biometricKind(), BiometricKind.fingerprint);
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

      await repository.savePin('123456');
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

      await repository.savePin('123456');
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
      'biometric authentication leaves cached PGP session preparation to app orchestration',
      () async {
        final biometrics = _FakeBiometricAuthAdapter(available: true);
        final repository = await SecureStorageSecurityRepository.load(
          storage: _FakeSecureStorageAdapter(),
          biometricAuth: biometrics,
        );

        await repository.savePin('123456');
        await repository.setBiometricUnlockEnabled(true);
        await repository.savePgpPassphrase(
          fingerprint: 'ABC123',
          passphrase: 'pgp-passphrase',
        );

        expect(await repository.unlockWithBiometrics(), isTrue);
        expect(repository.hasActivePgpSession, isFalse);
        expect(await repository.readActivePgpPassphrase(), isNull);
        expect(
          await repository.readPgpPassphrase(),
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

      await repository.savePin('123456');
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

  Iterable<String> get keys => _values.keys;

  Iterable<String> get values => _values.values;

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
    this.kind = BiometricKind.fingerprint,
    this.authenticateResult = true,
    List<bool>? authenticateResults,
  }) : _authenticateResults = authenticateResults ?? const <bool>[];

  final bool available;
  final BiometricKind kind;
  final bool authenticateResult;
  final List<bool> _authenticateResults;
  int authenticateCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricKind> biometricKind() async => kind;

  @override
  Future<bool> authenticate() async {
    authenticateCount += 1;
    if (authenticateCount <= _authenticateResults.length) {
      return _authenticateResults[authenticateCount - 1];
    }
    return authenticateResult;
  }
}
