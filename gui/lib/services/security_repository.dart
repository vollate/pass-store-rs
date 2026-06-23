import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  factory GestureVerifier.fromStoredValue(String value) {
    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'Invalid verifier value.');
    }
    return GestureVerifier._(value);
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

abstract interface class SecureStorageAdapter {
  Future<String?> read(String key);

  Future<void> write({required String key, required String value});

  Future<void> delete(String key);
}

class FlutterSecureStorageAdapter implements SecureStorageAdapter {
  const FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
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

class SecureStorageSecurityRepository implements SecurityRepository {
  SecureStorageSecurityRepository._({
    required SecureStorageAdapter storage,
    required GestureVerifier? gestureVerifier,
    required bool lockOnResume,
    required Duration autoLockTimeout,
  }) : _storage = storage,
       _gestureVerifier = gestureVerifier,
       _lockOnResume = lockOnResume,
       _autoLockTimeout = autoLockTimeout;

  static const _gestureVerifierKey = 'pars.security.gesture_verifier.v1';
  static const _lockOnResumeKey = 'pars.security.lock_on_resume.v1';
  static const _autoLockTimeoutSecondsKey =
      'pars.security.auto_lock_timeout_seconds.v1';
  static const _defaultAutoLockTimeout = Duration(minutes: 15);

  final SecureStorageAdapter _storage;

  GestureVerifier? _gestureVerifier;
  bool _lockOnResume;
  Duration _autoLockTimeout;
  DateTime? _lastUnlockedAt;

  static Future<SecureStorageSecurityRepository> load({
    SecureStorageAdapter storage = const FlutterSecureStorageAdapter(),
  }) async {
    final verifierValue = await storage.read(_gestureVerifierKey);
    GestureVerifier? verifier;
    if (verifierValue != null) {
      try {
        verifier = GestureVerifier.fromStoredValue(verifierValue);
      } on ArgumentError {
        await storage.delete(_gestureVerifierKey);
      }
    }

    return SecureStorageSecurityRepository._(
      storage: storage,
      gestureVerifier: verifier,
      lockOnResume: await _readBool(storage, _lockOnResumeKey),
      autoLockTimeout: await _readDuration(
        storage,
        _autoLockTimeoutSecondsKey,
        _defaultAutoLockTimeout,
      ),
    );
  }

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
    await _storage.write(key: _gestureVerifierKey, value: verifier.value);
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
    await _storage.write(key: _lockOnResumeKey, value: enabled ? '1' : '0');
    _lockOnResume = enabled;
  }

  @override
  Future<void> setAutoLockTimeout(Duration timeout) async {
    await _storage.write(
      key: _autoLockTimeoutSecondsKey,
      value: timeout.inSeconds.toString(),
    );
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

  static Future<bool> _readBool(
    SecureStorageAdapter storage,
    String key,
  ) async {
    return await storage.read(key) == '1';
  }

  static Future<Duration> _readDuration(
    SecureStorageAdapter storage,
    String key,
    Duration fallback,
  ) async {
    final raw = await storage.read(key);
    final seconds = raw == null ? null : int.tryParse(raw);
    if (seconds == null || seconds < 0) {
      return fallback;
    }
    return Duration(seconds: seconds);
  }
}
