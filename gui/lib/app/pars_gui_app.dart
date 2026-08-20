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
import '../services/sensitive_clipboard_service.dart';
import '../services/settings_repository.dart';
import '../services/ui_preferences_store.dart';
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
    this.uiPreferencesStore,
    this.clipboardService,
    this.pathPickerService = const SystemPathPickerService(),
    this.now = DateTime.now,
  });

  factory ParsGuiApp.fake({Key? key, UiPreferencesStore? uiPreferencesStore}) {
    const repository = FakeParsRepository();
    return ParsGuiApp(
      key: key,
      vaultRepository: repository,
      settingsRepository: repository,
      keyRepository: repository,
      gitRepository: repository,
      securityRepository: InMemorySecurityRepository(),
      uiPreferencesStore: uiPreferencesStore,
    );
  }

  final VaultRepository vaultRepository;
  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final AutofillRepository? autofillRepository;
  final UiPreferencesStore? uiPreferencesStore;
  final SensitiveClipboardService? clipboardService;
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
  late final UiPreferencesStore _uiPreferencesStore;
  late final SensitiveClipboardService _clipboardService;
  late final bool _ownsClipboardService;
  AppLocalePreference _localePreference = AppLocalePreference.system;
  final ValueNotifier<int> _privacyEpoch = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autofillRepository = widget.autofillRepository ?? FakeAutofillRepository();
    _uiPreferencesStore =
        widget.uiPreferencesStore ?? InMemoryUiPreferencesStore();
    _ownsClipboardService = widget.clipboardService == null;
    _clipboardService = widget.clipboardService ?? SensitiveClipboardService();
    unawaited(_loadLocalePreference());
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
    if (_ownsClipboardService) _clipboardService.dispose();
    _privacyEpoch.dispose();
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
      _privacyEpoch.value += 1;
      unawaited(_clearClipboardAfterLock());
      unawaited(_refreshNativeAutofillSecurityState());
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
      locale: _localePreference.locale,
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
                localePreference: _localePreference,
                onLocalePreferenceChanged: _setLocalePreference,
                clipboardService: _clipboardService,
                privacyEvents: _privacyEpoch,
                onLock: _lock,
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

  Future<void> _loadLocalePreference() async {
    final preference = await _uiPreferencesStore.loadLocale();
    if (!mounted || preference == _localePreference) return;
    setState(() => _localePreference = preference);
  }

  Future<void> _setLocalePreference(AppLocalePreference preference) async {
    if (preference == _localePreference) return;
    final previous = _localePreference;
    setState(() => _localePreference = preference);
    try {
      await _uiPreferencesStore.saveLocale(preference);
    } catch (_) {
      if (mounted) setState(() => _localePreference = previous);
      rethrow;
    }
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

  Future<void> _lock() async {
    _lockTimer?.cancel();
    await widget.securityRepository.markLocked();
    _privacyEpoch.value += 1;
    if (mounted && _isOnboardingComplete) {
      setState(() => _isLocked = true);
    }
    unawaited(_clearClipboardAfterLock());
    unawaited(_refreshNativeAutofillSecurityState());
  }

  Future<void> _refreshNativeAutofillSecurityState() async {
    try {
      await _autofillRepository.publishPlatformState();
    } catch (_) {
      // Locking remains authoritative even if native publication is unavailable.
    }
  }

  Future<void> _clearClipboardAfterLock() async {
    try {
      await _clipboardService.clearNow();
    } catch (_) {
      // Clipboard cleanup is best-effort and must never block locking.
    }
  }

  bool get _isOnboardingSatisfied =>
      widget.securityRepository.onboardingComplete &&
      widget.securityRepository.hasGestureVerifier &&
      !widget.settingsRepository.lifecycle.requiresStoreSetup &&
      !widget.settingsRepository.lifecycle.requiresKeyRepair;

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
