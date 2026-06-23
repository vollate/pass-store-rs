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
}
