import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/security_repository.dart';

void main() {
  group('GestureVerifier', () {
    test('matches only the captured gesture order', () {
      final verifier = GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]);

      expect(verifier.matches(const <int>[0, 1, 2, 5]), isTrue);
      expect(verifier.matches(const <int>[0, 1, 5, 2]), isFalse);
    });

    test('rejects short or repeated gestures', () {
      expect(
        () => GestureVerifier.fromPattern(const <int>[0, 1, 2]),
        throwsArgumentError,
      );
      expect(
        () => GestureVerifier.fromPattern(const <int>[0, 1, 1, 2]),
        throwsArgumentError,
      );
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
      await repository.setAutoLockTimeout(const Duration(minutes: 5));

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
        biometricAuth: _FakeBiometricAuthAdapter(),
      );

      expect(reloaded.hasGestureVerifier, isTrue);
      expect(await reloaded.verifyGesture(const <int>[0, 1, 2, 5]), isTrue);
      expect(await reloaded.verifyGesture(const <int>[0, 1, 5, 2]), isFalse);
      expect(reloaded.lockOnResume, isTrue);
      expect(reloaded.autoLockTimeout, const Duration(minutes: 5));
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
      expect(biometrics.authenticateCount, 1);
    });

    test('keeps session locked when biometric authentication fails', () async {
      final biometrics = _FakeBiometricAuthAdapter(
        available: true,
        authenticateResult: false,
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
      expect(biometrics.authenticateCount, 1);
    });

    test(
      'keeps biometrics unavailable when the platform cannot use them',
      () async {
        final repository = await SecureStorageSecurityRepository.load(
          storage: _FakeSecureStorageAdapter(),
          biometricAuth: _FakeBiometricAuthAdapter(available: false),
        );

        await repository.setBiometricUnlockEnabled(true);

        expect(
          await repository.biometricUnlockStatus(),
          BiometricUnlockStatus.unavailable,
        );
        expect(await repository.unlockWithBiometrics(), isFalse);
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
  });

  final bool available;
  final bool authenticateResult;
  int authenticateCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    authenticateCount += 1;
    return authenticateResult;
  }
}
