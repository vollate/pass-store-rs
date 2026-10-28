import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum LocalUnlockMethod { gesture, password }

// A drawn pattern suits touch screens; with a mouse or trackpad it is slow
// and imprecise, so desktops start with a typed password instead.
LocalUnlockMethod platformDefaultUnlockMethod() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => LocalUnlockMethod.password,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => LocalUnlockMethod.gesture,
  };
}

class PasswordVerifier {
  const PasswordVerifier._({
    required this.iterations,
    required Uint8List salt,
    required Uint8List hash,
  }) : _salt = salt,
       _hash = hash;

  factory PasswordVerifier.fromPassword(
    String password, {
    int iterations = defaultIterations,
    Random? random,
  }) {
    if (password.runes.length < minimumLength) {
      throw ArgumentError('Use at least $minimumLength characters.');
    }
    _checkIterations(iterations);
    final source = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => source.nextInt(256)),
    );
    return PasswordVerifier._(
      iterations: iterations,
      salt: salt,
      hash: _derive(password, salt, iterations),
    );
  }

  factory PasswordVerifier.fromStoredValue(String value) {
    final parts = value.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) {
      throw ArgumentError('Invalid verifier value.');
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null) {
      throw ArgumentError('Invalid verifier value.');
    }
    _checkIterations(iterations);
    final Uint8List salt;
    final Uint8List hash;
    try {
      salt = base64Decode(parts[2]);
      hash = base64Decode(parts[3]);
    } on FormatException {
      throw ArgumentError('Invalid verifier value.');
    }
    if (salt.isEmpty || hash.length != _hashLength) {
      throw ArgumentError('Invalid verifier value.');
    }
    return PasswordVerifier._(iterations: iterations, salt: salt, hash: hash);
  }

  static const int minimumLength = 6;
  static const int defaultIterations = 210000;
  static const int _maximumIterations = 10000000;
  static const int _saltLength = 16;
  static const int _hashLength = 32;
  static const String _scheme = 'pbkdf2-sha256';

  final int iterations;
  final Uint8List _salt;
  final Uint8List _hash;

  String get value =>
      '$_scheme\$$iterations\$${base64Encode(_salt)}\$${base64Encode(_hash)}';

  bool matches(String password) {
    final candidate = _derive(password, _salt, iterations);
    var difference = 0;
    for (var index = 0; index < _hashLength; index += 1) {
      difference |= candidate[index] ^ _hash[index];
    }
    return difference == 0;
  }

  static void _checkIterations(int iterations) {
    if (iterations < 1 || iterations > _maximumIterations) {
      throw RangeError.range(iterations, 1, _maximumIterations, 'iterations');
    }
  }

  // PBKDF2-HMAC-SHA256 with a single output block, which is all a 32-byte
  // key needs.
  static Uint8List _derive(String password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var block = hmac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
    final result = Uint8List.fromList(block);
    for (var round = 1; round < iterations; round += 1) {
      block = hmac.convert(block).bytes;
      for (var index = 0; index < result.length; index += 1) {
        result[index] ^= block[index];
      }
    }
    return result;
  }
}

PasswordVerifier _createPasswordVerifier(String password) =>
    PasswordVerifier.fromPassword(password);

bool _passwordMatches((PasswordVerifier, String) request) =>
    request.$1.matches(request.$2);

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
    : _storage =
          storage ??
          // The data protection keychain needs a keychain-access-groups
          // entitlement, which an ad-hoc signed macOS build cannot carry;
          // every write would fail with errSecMissingEntitlement (-34018).
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

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

  bool get hasPasswordVerifier;

  // Only one local unlock method is active; saving one replaces the other.
  LocalUnlockMethod? get unlockMethod;

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

  Future<void> savePassword(String password);

  Future<bool> verifyPassword(String password);

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

extension SecurityRepositoryUnlock on SecurityRepository {
  bool get hasUnlockVerifier => unlockMethod != null;
}

LocalUnlockMethod? _activeUnlockMethod(
  PasswordVerifier? password,
  GestureVerifier? gesture,
) {
  if (password != null) return LocalUnlockMethod.password;
  if (gesture != null) return LocalUnlockMethod.gesture;
  return null;
}

class InMemorySecurityRepository implements SecurityRepository {
  InMemorySecurityRepository({
    GestureVerifier? gestureVerifier,
    PasswordVerifier? passwordVerifier,
    this.passwordIterations = PasswordVerifier.defaultIterations,
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
  }) : _gestureVerifier = passwordVerifier == null ? gestureVerifier : null,
       _passwordVerifier = passwordVerifier,
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

  // Hashing runs inline here, so tests can lower the cost.
  final int passwordIterations;
  GestureVerifier? _gestureVerifier;
  PasswordVerifier? _passwordVerifier;
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
  bool get hasPasswordVerifier => _passwordVerifier != null;

  @override
  LocalUnlockMethod? get unlockMethod =>
      _activeUnlockMethod(_passwordVerifier, _gestureVerifier);

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
    _passwordVerifier = null;
  }

  @override
  Future<bool> verifyGesture(List<int> pattern) async =>
      _gestureVerifier?.matches(pattern) ?? false;

  @override
  Future<void> savePassword(String password) async {
    _passwordVerifier = PasswordVerifier.fromPassword(
      password,
      iterations: passwordIterations,
    );
    _gestureVerifier = null;
  }

  @override
  Future<bool> verifyPassword(String password) async =>
      _passwordVerifier?.matches(password) ?? false;

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
    if (!hasUnlockVerifier || unlockedAt == null) {
      return hasUnlockVerifier;
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
    required PasswordVerifier? passwordVerifier,
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
       _passwordVerifier = passwordVerifier,
       _lockOnResume = lockOnResume,
       _biometricUnlockEnabled = biometricUnlockEnabled,
       _pgpPassphraseStorageEnabled = pgpPassphraseStorageEnabled,
       _hasStoredPgpPassphrase = hasStoredPgpPassphrase,
       _onboardingComplete = onboardingComplete,
       _pgpSessionExpiration = pgpSessionExpiration,
       _autoLockTimeout = autoLockTimeout;

  static const _gestureVerifierKey = 'pars.security.gesture_verifier.v1';
  static const _passwordVerifierKey = 'pars.security.password_verifier.v1';
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
  PasswordVerifier? _passwordVerifier;
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

    final passwordValue = await storage.read(_passwordVerifierKey);
    PasswordVerifier? passwordVerifier;
    if (passwordValue != null) {
      try {
        passwordVerifier = PasswordVerifier.fromStoredValue(passwordValue);
      } on ArgumentError {
        await storage.delete(_passwordVerifierKey);
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
      gestureVerifier: passwordVerifier == null ? verifier : null,
      passwordVerifier: passwordVerifier,
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
  bool get hasPasswordVerifier => _passwordVerifier != null;

  @override
  LocalUnlockMethod? get unlockMethod =>
      _activeUnlockMethod(_passwordVerifier, _gestureVerifier);

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
    await _storage.delete(_passwordVerifierKey);
    _gestureVerifier = verifier;
    _passwordVerifier = null;
  }

  @override
  Future<bool> verifyGesture(List<int> pattern) async =>
      _gestureVerifier?.matches(pattern) ?? false;

  @override
  Future<void> savePassword(String password) async {
    final verifier = await compute(_createPasswordVerifier, password);
    await _storage.write(key: _passwordVerifierKey, value: verifier.value);
    await _storage.delete(_gestureVerifierKey);
    _passwordVerifier = verifier;
    _gestureVerifier = null;
  }

  @override
  Future<bool> verifyPassword(String password) async {
    final verifier = _passwordVerifier;
    if (verifier == null) return false;
    return compute(_passwordMatches, (verifier, password));
  }

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
    if (!hasUnlockVerifier || unlockedAt == null) {
      return hasUnlockVerifier;
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
