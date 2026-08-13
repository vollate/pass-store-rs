import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/security/lock_screen.dart';
import '../screens/shell/mobile_shell.dart';
import '../services/autofill_repository.dart';
import '../services/fake_pars_repository.dart';
import '../services/git_repository.dart';
import '../services/key_repository.dart';
import '../services/path_picker_service.dart';
import '../services/security_repository.dart';
import '../services/settings_repository.dart';
import '../services/vault_repository.dart';
import 'pars_theme.dart';

class ParsGuiApp extends StatefulWidget {
  const ParsGuiApp({
    super.key,
    required this.vaultRepository,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
    required this.securityRepository,
    this.autofillRepository,
    this.pathPickerService = const SystemPathPickerService(),
    this.now = DateTime.now,
  });

  factory ParsGuiApp.fake({Key? key}) {
    const repository = FakeParsRepository();
    return ParsGuiApp(
      key: key,
      vaultRepository: repository,
      settingsRepository: repository,
      keyRepository: repository,
      gitRepository: repository,
      securityRepository: InMemorySecurityRepository(),
    );
  }

  final VaultRepository vaultRepository;
  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final AutofillRepository? autofillRepository;
  final PathPickerService pathPickerService;
  final DateTime Function() now;

  @override
  State<ParsGuiApp> createState() => _ParsGuiAppState();
}

class _ParsGuiAppState extends State<ParsGuiApp> with WidgetsBindingObserver {
  static const _systemAuthLifecycleGracePeriod = Duration(seconds: 2);

  late bool _isOnboardingComplete;
  late bool _isLocked;
  Timer? _lockTimer;
  DateTime? _backgroundedAt;
  DateTime? _suppressLifecycleLocksUntil;
  int _systemAuthDepth = 0;
  late final AutofillRepository _autofillRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autofillRepository = widget.autofillRepository ?? FakeAutofillRepository();
    _isOnboardingComplete = _isOnboardingSatisfied;
    _isLocked =
        _isOnboardingComplete &&
        widget.securityRepository.shouldLock(widget.now());
    if (_isOnboardingComplete && !_isLocked) {
      _scheduleAutoLock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isOnboardingComplete) {
      return;
    }
    final now = widget.now();
    final isBackgrounded =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (isBackgrounded) {
      _backgroundedAt ??= now;
      _lockTimer?.cancel();
      return;
    }

    if (state != AppLifecycleState.resumed) {
      return;
    }

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (_shouldIgnoreLifecycleLock(now)) {
      if (!_isLocked) {
        _scheduleAutoLock();
      }
      return;
    }
    if (_isLocked) {
      return;
    }
    if (widget.securityRepository.lockOnResume ||
        _backgroundAutoLockExpired(backgroundedAt, now) ||
        widget.securityRepository.shouldLock(now)) {
      _lock();
      return;
    }
    _scheduleAutoLock();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pars',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ParsTheme.light(),
      darkTheme: ParsTheme.dark(),
      themeMode: ThemeMode.system,
      home:
          !_isOnboardingComplete
              ? OnboardingScreen(
                settingsRepository: widget.settingsRepository,
                keyRepository: widget.keyRepository,
                securityRepository: widget.securityRepository,
                pathPickerService: widget.pathPickerService,
                onComplete: () {
                  setState(() {
                    _isOnboardingComplete = true;
                    _isLocked = false;
                  });
                  _scheduleAutoLock();
                },
              )
              : _isLocked
              ? LockScreen(
                securityRepository: widget.securityRepository,
                unlockWithBiometrics: _unlockWithBiometrics,
                onUnlocked: () {
                  setState(() => _isLocked = false);
                  _scheduleAutoLock();
                },
              )
              : MobileShell(
                vaultRepository: widget.vaultRepository,
                settingsRepository: widget.settingsRepository,
                keyRepository: widget.keyRepository,
                gitRepository: widget.gitRepository,
                securityRepository: widget.securityRepository,
                autofillRepository: _autofillRepository,
                pathPickerService: widget.pathPickerService,
                onSecuritySettingsChanged: _scheduleAutoLock,
                runDuringSystemAuthentication: _runDuringSystemAuthentication,
                onOnboardingReset: () {
                  _lockTimer?.cancel();
                  setState(() {
                    _isOnboardingComplete = false;
                    _isLocked = false;
                  });
                },
              ),
    );
  }

  void _scheduleAutoLock() {
    _lockTimer?.cancel();
    if (_isLocked) {
      return;
    }
    final timeout = widget.securityRepository.autoLockTimeout;
    if (timeout <= Duration.zero) {
      return;
    }
    final unlockedAt = widget.securityRepository.lastUnlockedAt;
    if (unlockedAt == null) {
      return;
    }
    final remaining = timeout - widget.now().difference(unlockedAt);
    if (remaining <= Duration.zero) {
      _lock();
      return;
    }
    _lockTimer = Timer(remaining, _lock);
  }

  void _lock() {
    _lockTimer?.cancel();
    widget.securityRepository.markLocked();
    if (mounted && _isOnboardingComplete) {
      setState(() => _isLocked = true);
    }
  }

  bool get _isOnboardingSatisfied =>
      widget.securityRepository.onboardingComplete &&
      widget.securityRepository.hasGestureVerifier &&
      !widget.settingsRepository.lifecycle.requiresStoreSetup;

  Future<bool> _unlockWithBiometrics() async {
    final unlocked = await _runDuringSystemAuthentication(
      widget.securityRepository.unlockWithBiometrics,
    );
    if (!unlocked) return false;

    final cached = await widget.securityRepository.readPgpPassphrase();
    if (cached == null) return true;
    try {
      final prepared = await widget.keyRepository.preparePgpPrivateKey(
        fingerprint: cached.fingerprint,
        passphrase: cached.passphrase,
      );
      await widget.securityRepository.startPgpSession(
        fingerprint: prepared.fingerprint,
        passphrase: cached.passphrase,
      );
    } catch (_) {
      await widget.securityRepository.clearPgpSession();
    }
    return true;
  }

  Future<T> _runDuringSystemAuthentication<T>(
    Future<T> Function() action,
  ) async {
    _systemAuthDepth += 1;
    try {
      return await action();
    } finally {
      _systemAuthDepth -= 1;
      _suppressLifecycleLocksUntil = widget.now().add(
        _systemAuthLifecycleGracePeriod,
      );
    }
  }

  bool _shouldIgnoreLifecycleLock(DateTime now) {
    if (_systemAuthDepth > 0) {
      return true;
    }
    final suppressUntil = _suppressLifecycleLocksUntil;
    if (suppressUntil == null) {
      return false;
    }
    if (now.isBefore(suppressUntil)) {
      return true;
    }
    _suppressLifecycleLocksUntil = null;
    return false;
  }

  bool _backgroundAutoLockExpired(DateTime? backgroundedAt, DateTime now) {
    if (backgroundedAt == null) {
      return false;
    }
    final timeout = widget.securityRepository.autoLockTimeout;
    if (timeout <= Duration.zero) {
      return false;
    }
    return now.difference(backgroundedAt) >= timeout;
  }
}
