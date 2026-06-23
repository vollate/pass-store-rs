class GestureVerifier {
  const GestureVerifier._(this.value);

  factory GestureVerifier.fromPattern(List<int> pattern) {
    if (pattern.length < 4) {
      throw ArgumentError.value(pattern, 'pattern', 'Use at least 4 dots.');
    }
    if (pattern.toSet().length != pattern.length) {
      throw ArgumentError.value(pattern, 'pattern', 'Do not repeat dots.');
    }
    for (final dot in pattern) {
      if (dot < 0 || dot > 8) {
        throw ArgumentError.value(pattern, 'pattern', 'Dot is out of range.');
      }
    }
    return GestureVerifier._(_fingerprint(pattern));
  }

  final String value;

  bool matches(List<int> pattern) =>
      pattern.length >= 4 && value == _fingerprint(pattern);

  static String _fingerprint(List<int> pattern) {
    var hash = 0x811c9dc5;
    for (final dot in pattern) {
      hash ^= dot + 1;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    hash ^= pattern.length;
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

abstract interface class SecurityRepository {
  bool get hasGestureVerifier;

  bool get lockOnResume;

  Duration get autoLockTimeout;

  DateTime? get lastUnlockedAt;

  Future<void> saveGestureVerifier(GestureVerifier verifier);

  Future<bool> verifyGesture(List<int> pattern);

  Future<void> markUnlocked(DateTime at);

  Future<void> markLocked();

  Future<void> setLockOnResume(bool enabled);

  Future<void> setAutoLockTimeout(Duration timeout);

  bool shouldLock(DateTime now);
}

class InMemorySecurityRepository implements SecurityRepository {
  InMemorySecurityRepository({
    GestureVerifier? gestureVerifier,
    bool lockOnResume = false,
    Duration autoLockTimeout = const Duration(minutes: 15),
    DateTime? lastUnlockedAt,
  }) : _gestureVerifier = gestureVerifier,
       _lockOnResume = lockOnResume,
       _autoLockTimeout = autoLockTimeout,
       _lastUnlockedAt = lastUnlockedAt;

  factory InMemorySecurityRepository.withPattern(
    List<int> pattern, {
    bool lockOnResume = false,
    Duration autoLockTimeout = const Duration(minutes: 15),
    DateTime? lastUnlockedAt,
  }) {
    return InMemorySecurityRepository(
      gestureVerifier: GestureVerifier.fromPattern(pattern),
      lockOnResume: lockOnResume,
      autoLockTimeout: autoLockTimeout,
      lastUnlockedAt: lastUnlockedAt,
    );
  }

  GestureVerifier? _gestureVerifier;
  bool _lockOnResume;
  Duration _autoLockTimeout;
  DateTime? _lastUnlockedAt;

  @override
  bool get hasGestureVerifier => _gestureVerifier != null;

  @override
  bool get lockOnResume => _lockOnResume;

  @override
  Duration get autoLockTimeout => _autoLockTimeout;

  @override
  DateTime? get lastUnlockedAt => _lastUnlockedAt;

  @override
  Future<void> saveGestureVerifier(GestureVerifier verifier) async {
    _gestureVerifier = verifier;
  }

  @override
  Future<bool> verifyGesture(List<int> pattern) async =>
      _gestureVerifier?.matches(pattern) ?? false;

  @override
  Future<void> markUnlocked(DateTime at) async {
    _lastUnlockedAt = at;
  }

  @override
  Future<void> markLocked() async {
    _lastUnlockedAt = null;
  }

  @override
  Future<void> setLockOnResume(bool enabled) async {
    _lockOnResume = enabled;
  }

  @override
  Future<void> setAutoLockTimeout(Duration timeout) async {
    _autoLockTimeout = timeout;
  }

  @override
  bool shouldLock(DateTime now) {
    final unlockedAt = _lastUnlockedAt;
    if (!hasGestureVerifier || unlockedAt == null) {
      return hasGestureVerifier;
    }
    if (_autoLockTimeout <= Duration.zero) {
      return false;
    }
    return now.difference(unlockedAt) >= _autoLockTimeout;
  }
}
