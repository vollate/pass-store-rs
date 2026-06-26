import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class GestureVerifier {
  const GestureVerifier._(this.value);

  factory GestureVerifier.fromPattern(List<int> pattern) {
    if (pattern.length < 4) {
      throw ArgumentError.value(pattern, 'pattern', 'Use at least 4 dots.');
    }
    if (_hasConsecutiveRepeatedDots(pattern)) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        'Do not repeat the same dot without moving away.',
      );
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

bool _hasConsecutiveRepeatedDots(List<int> pattern) {
  for (var index = 1; index < pattern.length; index += 1) {
    if (pattern[index - 1] == pattern[index]) {
      return true;
    }
  }
  return false;
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

enum BiometricUnlockStatus { unavailable, disabled, available }

enum PgpSessionExpiration {
  immediately,
  fiveMinutes,
  fifteenMinutes,
  oneHour,
  untilAppExit,
}

class PgpPassphraseCache {
  const PgpPassphraseCache({
    required this.fingerprint,
    required this.passphrase,
  });

  final String fingerprint;
  final String passphrase;

  @override
  bool operator ==(Object other) {
    return other is PgpPassphraseCache &&
        other.fingerprint == fingerprint &&
        other.passphrase == passphrase;
  }

  @override
  int get hashCode => Object.hash(fingerprint, passphrase);
}

extension PgpSessionExpirationLabel on PgpSessionExpiration {
  String get label {
    switch (this) {
      case PgpSessionExpiration.immediately:
        return 'Immediately';
      case PgpSessionExpiration.fiveMinutes:
        return '5 min';
      case PgpSessionExpiration.fifteenMinutes:
        return '15 min';
      case PgpSessionExpiration.oneHour:
        return '1 hour';
      case PgpSessionExpiration.untilAppExit:
        return 'Until app exit';
    }
  }

  Duration? get duration {
    switch (this) {
      case PgpSessionExpiration.immediately:
        return Duration.zero;
      case PgpSessionExpiration.fiveMinutes:
        return const Duration(minutes: 5);
      case PgpSessionExpiration.fifteenMinutes:
        return const Duration(minutes: 15);
      case PgpSessionExpiration.oneHour:
        return const Duration(hours: 1);
      case PgpSessionExpiration.untilAppExit:
        return null;
    }
  }
}

abstract interface class BiometricAuthAdapter {
  Future<bool> isAvailable();

  Future<bool> authenticate();
}

class LocalAuthBiometricAdapter implements BiometricAuthAdapter {
  LocalAuthBiometricAdapter([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock the local Pars app session',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

abstract interface class SecurityRepository {
  bool get hasGestureVerifier;

  bool get lockOnResume;

  bool get biometricUnlockEnabled;

  bool get pgpPassphraseStorageEnabled;

  bool get hasStoredPgpPassphrase;

  bool get hasActivePgpSession;

  bool get onboardingComplete;

  PgpSessionExpiration get pgpSessionExpiration;

  Duration get autoLockTimeout;

  DateTime? get lastUnlockedAt;

  Future<void> saveGestureVerifier(GestureVerifier verifier);

  Future<bool> verifyGesture(List<int> pattern);

  Future<void> markUnlocked(DateTime at);

  Future<void> markLocked();

  Future<void> setOnboardingComplete(bool complete);

  Future<void> setLockOnResume(bool enabled);

  Future<void> setBiometricUnlockEnabled(bool enabled);

  Future<BiometricUnlockStatus> biometricUnlockStatus();

  Future<bool> unlockWithBiometrics();

  Future<void> setPgpPassphraseStorageEnabled(bool enabled);

  Future<void> savePgpPassphrase({
    required String fingerprint,
    required String passphrase,
  });

  Future<PgpPassphraseCache?> readPgpPassphrase();

  Future<void> clearPgpPassphrase();

  Future<void> startPgpSession({
    required String fingerprint,
    required String passphrase,
  });

  Future<PgpPassphraseCache?> readActivePgpPassphrase();

  Future<void> clearPgpSession();

  Future<void> clearPgpPassphraseForFingerprint(String fingerprint);

  Future<void> setPgpSessionExpiration(PgpSessionExpiration expiration);

  Future<void> expirePgpSessionIfNeeded(DateTime now);

  Future<void> setAutoLockTimeout(Duration timeout);

  bool shouldLock(DateTime now);
}

class InMemorySecurityRepository implements SecurityRepository {
  InMemorySecurityRepository({
    GestureVerifier? gestureVerifier,
    bool lockOnResume = false,
    bool biometricUnlockEnabled = false,
    bool pgpPassphraseStorageEnabled = false,
    PgpPassphraseCache? pgpPassphrase,
    PgpPassphraseCache? activePgpPassphrase,
    bool onboardingComplete = false,
    PgpSessionExpiration pgpSessionExpiration =
        PgpSessionExpiration.fifteenMinutes,
    Duration autoLockTimeout = const Duration(minutes: 15),
    DateTime? lastUnlockedAt,
  }) : _gestureVerifier = gestureVerifier,
       _lockOnResume = lockOnResume,
       _biometricUnlockEnabled = biometricUnlockEnabled,
       _pgpPassphraseStorageEnabled = pgpPassphraseStorageEnabled,
       _pgpPassphrase = pgpPassphrase,
       _activePgpPassphrase = activePgpPassphrase,
       _onboardingComplete = onboardingComplete,
       _pgpSessionExpiration = pgpSessionExpiration,
       _autoLockTimeout = autoLockTimeout,
       _lastUnlockedAt = lastUnlockedAt;

  factory InMemorySecurityRepository.withPattern(
    List<int> pattern, {
    bool lockOnResume = false,
    bool biometricUnlockEnabled = false,
    bool pgpPassphraseStorageEnabled = false,
    PgpPassphraseCache? pgpPassphrase,
    PgpPassphraseCache? activePgpPassphrase,
    bool onboardingComplete = true,
    PgpSessionExpiration pgpSessionExpiration =
        PgpSessionExpiration.fifteenMinutes,
    Duration autoLockTimeout = const Duration(minutes: 15),
    DateTime? lastUnlockedAt,
  }) {
    return InMemorySecurityRepository(
      gestureVerifier: GestureVerifier.fromPattern(pattern),
      lockOnResume: lockOnResume,
      biometricUnlockEnabled: biometricUnlockEnabled,
      pgpPassphraseStorageEnabled: pgpPassphraseStorageEnabled,
      pgpPassphrase: pgpPassphrase,
      activePgpPassphrase: activePgpPassphrase,
      onboardingComplete: onboardingComplete,
      pgpSessionExpiration: pgpSessionExpiration,
      autoLockTimeout: autoLockTimeout,
      lastUnlockedAt: lastUnlockedAt,
    );
  }

  GestureVerifier? _gestureVerifier;
  bool _lockOnResume;
  bool _biometricUnlockEnabled;
  bool _pgpPassphraseStorageEnabled;
  bool _onboardingComplete;
  PgpPassphraseCache? _pgpPassphrase;
  PgpPassphraseCache? _activePgpPassphrase;
  DateTime? _pgpSessionExpiresAt;
  PgpSessionExpiration _pgpSessionExpiration;
  Duration _autoLockTimeout;
  DateTime? _lastUnlockedAt;

  @override
  bool get hasGestureVerifier => _gestureVerifier != null;

  @override
  bool get lockOnResume => _lockOnResume;

  @override
  bool get biometricUnlockEnabled => _biometricUnlockEnabled;

  @override
  bool get pgpPassphraseStorageEnabled => _pgpPassphraseStorageEnabled;

  @override
  bool get hasStoredPgpPassphrase => _pgpPassphrase != null;

  @override
  bool get onboardingComplete => _onboardingComplete;

  @override
  bool get hasActivePgpSession {
    if (_pgpSessionIsExpired(DateTime.now())) {
      _activePgpPassphrase = null;
      _pgpSessionExpiresAt = null;
    }
    return _activePgpPassphrase != null;
  }

  @override
  PgpSessionExpiration get pgpSessionExpiration => _pgpSessionExpiration;

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
    await clearPgpSession();
  }

  @override
  Future<void> setOnboardingComplete(bool complete) async {
    _onboardingComplete = complete;
  }

  @override
  Future<void> setLockOnResume(bool enabled) async {
    _lockOnResume = enabled;
  }

  @override
  Future<void> setBiometricUnlockEnabled(bool enabled) async {
    _biometricUnlockEnabled = enabled;
  }

  @override
  Future<BiometricUnlockStatus> biometricUnlockStatus() async {
    if (!_biometricUnlockEnabled) {
      return BiometricUnlockStatus.disabled;
    }
    return BiometricUnlockStatus.unavailable;
  }

  @override
  Future<bool> unlockWithBiometrics() async => false;

  @override
  Future<void> setPgpPassphraseStorageEnabled(bool enabled) async {
    _pgpPassphraseStorageEnabled = enabled;
    if (!enabled) {
      _pgpPassphrase = null;
    }
  }

  @override
  Future<void> savePgpPassphrase({
    required String fingerprint,
    required String passphrase,
  }) async {
    final cache = _validatedPgpPassphraseCache(
      fingerprint: fingerprint,
      passphrase: passphrase,
    );
    _pgpPassphraseStorageEnabled = true;
    _pgpPassphrase = cache;
  }

  @override
  Future<PgpPassphraseCache?> readPgpPassphrase() async {
    if (!_pgpPassphraseStorageEnabled) {
      return null;
    }
    return _pgpPassphrase;
  }

  @override
  Future<void> clearPgpPassphrase() async {
    _pgpPassphrase = null;
  }

  @override
  Future<void> startPgpSession({
    required String fingerprint,
    required String passphrase,
  }) async {
    _activePgpPassphrase = _validatedPgpPassphraseCache(
      fingerprint: fingerprint,
      passphrase: passphrase,
    );
    _pgpSessionExpiresAt = _sessionExpiresAt(DateTime.now());
  }

  @override
  Future<PgpPassphraseCache?> readActivePgpPassphrase() async {
    await expirePgpSessionIfNeeded(DateTime.now());
    return _activePgpPassphrase;
  }

  @override
  Future<void> clearPgpSession() async {
    _activePgpPassphrase = null;
    _pgpSessionExpiresAt = null;
  }

  @override
  Future<void> clearPgpPassphraseForFingerprint(String fingerprint) async {
    final target = fingerprint.trim();
    if (_pgpPassphrase?.fingerprint == target) {
      await clearPgpPassphrase();
    }
    if (_activePgpPassphrase?.fingerprint == target) {
      await clearPgpSession();
    }
  }

  @override
  Future<void> setPgpSessionExpiration(PgpSessionExpiration expiration) async {
    _pgpSessionExpiration = expiration;
    if (_activePgpPassphrase != null) {
      _pgpSessionExpiresAt = _sessionExpiresAt(DateTime.now());
      await expirePgpSessionIfNeeded(DateTime.now());
    }
  }

  @override
  Future<void> expirePgpSessionIfNeeded(DateTime now) async {
    if (_pgpSessionIsExpired(now)) {
      await clearPgpSession();
    }
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

  DateTime? _sessionExpiresAt(DateTime now) {
    final duration = _pgpSessionExpiration.duration;
    if (duration == null) {
      return null;
    }
    return now.add(duration);
  }

  bool _pgpSessionIsExpired(DateTime now) {
    final expiresAt = _pgpSessionExpiresAt;
    return _activePgpPassphrase != null &&
        expiresAt != null &&
        !now.isBefore(expiresAt);
  }
}

PgpPassphraseCache _validatedPgpPassphraseCache({
  required String fingerprint,
  required String passphrase,
}) {
  final trimmedFingerprint = fingerprint.trim();
  if (trimmedFingerprint.isEmpty) {
    throw ArgumentError.value(
      fingerprint,
      'fingerprint',
      'Fingerprint cannot be empty.',
    );
  }
  if (passphrase.isEmpty) {
    throw ArgumentError.value(
      passphrase,
      'passphrase',
      'Passphrase cannot be empty.',
    );
  }
  return PgpPassphraseCache(
    fingerprint: trimmedFingerprint,
    passphrase: passphrase,
  );
}

class SecureStorageSecurityRepository implements SecurityRepository {
  SecureStorageSecurityRepository._({
    required SecureStorageAdapter storage,
    required BiometricAuthAdapter biometricAuth,
    required GestureVerifier? gestureVerifier,
    required bool lockOnResume,
    required bool biometricUnlockEnabled,
    required bool pgpPassphraseStorageEnabled,
    required bool hasStoredPgpPassphrase,
    required bool onboardingComplete,
    required PgpSessionExpiration pgpSessionExpiration,
    required Duration autoLockTimeout,
  }) : _storage = storage,
       _biometricAuth = biometricAuth,
       _gestureVerifier = gestureVerifier,
       _lockOnResume = lockOnResume,
       _biometricUnlockEnabled = biometricUnlockEnabled,
       _pgpPassphraseStorageEnabled = pgpPassphraseStorageEnabled,
       _hasStoredPgpPassphrase = hasStoredPgpPassphrase,
       _onboardingComplete = onboardingComplete,
       _pgpSessionExpiration = pgpSessionExpiration,
       _autoLockTimeout = autoLockTimeout;

  static const _gestureVerifierKey = 'pars.security.gesture_verifier.v1';
  static const _lockOnResumeKey = 'pars.security.lock_on_resume.v1';
  static const _biometricUnlockEnabledKey =
      'pars.security.biometric_unlock_enabled.v1';
  static const _pgpPassphraseStorageEnabledKey =
      'pars.security.pgp_passphrase_storage_enabled.v1';
  static const _pgpPassphraseKey = 'pars.security.pgp_passphrase.v1';
  static const _pgpPassphraseFingerprintKey =
      'pars.security.pgp_passphrase_fingerprint.v1';
  static const _onboardingCompleteKey = 'pars.security.onboarding_complete.v1';
  static const _pgpSessionExpirationKey =
      'pars.security.pgp_session_expiration.v1';
  static const _autoLockTimeoutSecondsKey =
      'pars.security.auto_lock_timeout_seconds.v1';
  static const _defaultAutoLockTimeout = Duration(minutes: 15);
  static const _defaultPgpSessionExpiration =
      PgpSessionExpiration.fifteenMinutes;

  final SecureStorageAdapter _storage;
  final BiometricAuthAdapter _biometricAuth;

  GestureVerifier? _gestureVerifier;
  bool _lockOnResume;
  bool _biometricUnlockEnabled;
  bool _pgpPassphraseStorageEnabled;
  bool _hasStoredPgpPassphrase;
  bool _onboardingComplete;
  PgpPassphraseCache? _activePgpPassphrase;
  DateTime? _pgpSessionExpiresAt;
  PgpSessionExpiration _pgpSessionExpiration;
  Duration _autoLockTimeout;
  DateTime? _lastUnlockedAt;

  static Future<SecureStorageSecurityRepository> load({
    SecureStorageAdapter storage = const FlutterSecureStorageAdapter(),
    BiometricAuthAdapter? biometricAuth,
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

    final pgpStorageEnabled = await _readBool(
      storage,
      _pgpPassphraseStorageEnabledKey,
    );
    var hasStoredPgpPassphrase = false;
    final storedPassphrase = await storage.read(_pgpPassphraseKey);
    final storedFingerprint = await storage.read(_pgpPassphraseFingerprintKey);
    if (storedPassphrase != null) {
      if ((storedFingerprint ?? '').trim().isEmpty) {
        await storage.delete(_pgpPassphraseKey);
        await storage.delete(_pgpPassphraseFingerprintKey);
      } else {
        hasStoredPgpPassphrase = pgpStorageEnabled;
      }
    }

    return SecureStorageSecurityRepository._(
      storage: storage,
      biometricAuth: biometricAuth ?? LocalAuthBiometricAdapter(),
      gestureVerifier: verifier,
      lockOnResume: await _readBool(storage, _lockOnResumeKey),
      biometricUnlockEnabled: await _readBool(
        storage,
        _biometricUnlockEnabledKey,
      ),
      pgpPassphraseStorageEnabled: pgpStorageEnabled,
      hasStoredPgpPassphrase: hasStoredPgpPassphrase,
      onboardingComplete: await _readBool(storage, _onboardingCompleteKey),
      pgpSessionExpiration: await _readPgpSessionExpiration(storage),
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
  bool get biometricUnlockEnabled => _biometricUnlockEnabled;

  @override
  bool get pgpPassphraseStorageEnabled => _pgpPassphraseStorageEnabled;

  @override
  bool get hasStoredPgpPassphrase => _hasStoredPgpPassphrase;

  @override
  bool get onboardingComplete => _onboardingComplete;

  @override
  bool get hasActivePgpSession {
    if (_pgpSessionIsExpired(DateTime.now())) {
      _activePgpPassphrase = null;
      _pgpSessionExpiresAt = null;
    }
    return _activePgpPassphrase != null;
  }

  @override
  PgpSessionExpiration get pgpSessionExpiration => _pgpSessionExpiration;

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
    await clearPgpSession();
  }

  @override
  Future<void> setOnboardingComplete(bool complete) async {
    await _storage.write(
      key: _onboardingCompleteKey,
      value: complete ? '1' : '0',
    );
    _onboardingComplete = complete;
  }

  @override
  Future<void> setLockOnResume(bool enabled) async {
    await _storage.write(key: _lockOnResumeKey, value: enabled ? '1' : '0');
    _lockOnResume = enabled;
  }

  @override
  Future<void> setBiometricUnlockEnabled(bool enabled) async {
    if (enabled && !_biometricUnlockEnabled) {
      if (!await _biometricAuth.isAvailable()) {
        throw StateError('Biometric unlock is unavailable on this device.');
      }
      if (!await _biometricAuth.authenticate()) {
        throw StateError('Biometric authentication failed.');
      }
    }
    await _storage.write(
      key: _biometricUnlockEnabledKey,
      value: enabled ? '1' : '0',
    );
    _biometricUnlockEnabled = enabled;
  }

  @override
  Future<BiometricUnlockStatus> biometricUnlockStatus() async {
    if (!await _biometricAuth.isAvailable()) {
      return BiometricUnlockStatus.unavailable;
    }
    if (!_biometricUnlockEnabled) {
      return BiometricUnlockStatus.disabled;
    }
    return BiometricUnlockStatus.available;
  }

  @override
  Future<bool> unlockWithBiometrics() async {
    if (await biometricUnlockStatus() != BiometricUnlockStatus.available) {
      return false;
    }
    final unlocked = await _biometricAuth.authenticate();
    if (unlocked) {
      await markUnlocked(DateTime.now());
      final cachedPassphrase = await readPgpPassphrase();
      if (cachedPassphrase != null) {
        await startPgpSession(
          fingerprint: cachedPassphrase.fingerprint,
          passphrase: cachedPassphrase.passphrase,
        );
      }
    }
    return unlocked;
  }

  @override
  Future<void> setPgpPassphraseStorageEnabled(bool enabled) async {
    await _storage.write(
      key: _pgpPassphraseStorageEnabledKey,
      value: enabled ? '1' : '0',
    );
    _pgpPassphraseStorageEnabled = enabled;
    if (!enabled) {
      await clearPgpPassphrase();
    }
  }

  @override
  Future<void> savePgpPassphrase({
    required String fingerprint,
    required String passphrase,
  }) async {
    final cache = _validatedPgpPassphraseCache(
      fingerprint: fingerprint,
      passphrase: passphrase,
    );
    await _storage.write(key: _pgpPassphraseKey, value: cache.passphrase);
    await _storage.write(
      key: _pgpPassphraseFingerprintKey,
      value: cache.fingerprint,
    );
    await _storage.write(key: _pgpPassphraseStorageEnabledKey, value: '1');
    _pgpPassphraseStorageEnabled = true;
    _hasStoredPgpPassphrase = true;
  }

  @override
  Future<PgpPassphraseCache?> readPgpPassphrase() async {
    if (!_pgpPassphraseStorageEnabled) {
      return null;
    }
    final passphrase = await _storage.read(_pgpPassphraseKey);
    final fingerprint = await _storage.read(_pgpPassphraseFingerprintKey);
    if (passphrase == null || (fingerprint ?? '').trim().isEmpty) {
      return null;
    }
    return PgpPassphraseCache(
      fingerprint: fingerprint!.trim(),
      passphrase: passphrase,
    );
  }

  @override
  Future<void> clearPgpPassphrase() async {
    await _storage.delete(_pgpPassphraseKey);
    await _storage.delete(_pgpPassphraseFingerprintKey);
    _hasStoredPgpPassphrase = false;
    await clearPgpSession();
  }

  @override
  Future<void> startPgpSession({
    required String fingerprint,
    required String passphrase,
  }) async {
    _activePgpPassphrase = _validatedPgpPassphraseCache(
      fingerprint: fingerprint,
      passphrase: passphrase,
    );
    _pgpSessionExpiresAt = _sessionExpiresAt(DateTime.now());
  }

  @override
  Future<PgpPassphraseCache?> readActivePgpPassphrase() async {
    await expirePgpSessionIfNeeded(DateTime.now());
    return _activePgpPassphrase;
  }

  @override
  Future<void> clearPgpSession() async {
    _activePgpPassphrase = null;
    _pgpSessionExpiresAt = null;
  }

  @override
  Future<void> clearPgpPassphraseForFingerprint(String fingerprint) async {
    final target = fingerprint.trim();
    final stored = await readPgpPassphrase();
    if (stored?.fingerprint == target) {
      await _storage.delete(_pgpPassphraseKey);
      await _storage.delete(_pgpPassphraseFingerprintKey);
      _hasStoredPgpPassphrase = false;
    }
    if (_activePgpPassphrase?.fingerprint == target) {
      await clearPgpSession();
    }
  }

  @override
  Future<void> setPgpSessionExpiration(PgpSessionExpiration expiration) async {
    await _storage.write(key: _pgpSessionExpirationKey, value: expiration.name);
    _pgpSessionExpiration = expiration;
    if (_activePgpPassphrase != null) {
      _pgpSessionExpiresAt = _sessionExpiresAt(DateTime.now());
      await expirePgpSessionIfNeeded(DateTime.now());
    }
  }

  @override
  Future<void> expirePgpSessionIfNeeded(DateTime now) async {
    if (_pgpSessionIsExpired(now)) {
      await clearPgpSession();
    }
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

  DateTime? _sessionExpiresAt(DateTime now) {
    final duration = _pgpSessionExpiration.duration;
    if (duration == null) {
      return null;
    }
    return now.add(duration);
  }

  bool _pgpSessionIsExpired(DateTime now) {
    final expiresAt = _pgpSessionExpiresAt;
    return _activePgpPassphrase != null &&
        expiresAt != null &&
        !now.isBefore(expiresAt);
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

  static Future<PgpSessionExpiration> _readPgpSessionExpiration(
    SecureStorageAdapter storage,
  ) async {
    final raw = await storage.read(_pgpSessionExpirationKey);
    if (raw == null) {
      return _defaultPgpSessionExpiration;
    }
    for (final expiration in PgpSessionExpiration.values) {
      if (expiration.name == raw) {
        return expiration;
      }
    }
    return _defaultPgpSessionExpiration;
  }
}
