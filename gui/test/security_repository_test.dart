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
      );

      await repository.saveGestureVerifier(
        GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      );
      await repository.setLockOnResume(true);
      await repository.setAutoLockTimeout(const Duration(minutes: 5));

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
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
      );

      await repository.saveGestureVerifier(
        GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      );
      await repository.markUnlocked(DateTime(2026));

      final reloaded = await SecureStorageSecurityRepository.load(
        storage: storage,
      );

      expect(repository.shouldLock(DateTime(2026)), isFalse);
      expect(reloaded.shouldLock(DateTime(2026)), isTrue);
    });
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
