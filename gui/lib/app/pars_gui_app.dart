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

enum _RootPresentationState {
  securitySetup,
  locked,
  storeRemoving,
  storeSetup,
  storeRepair,
  ready,
}

class _ParsGuiAppState extends State<ParsGuiApp> with WidgetsBindingObserver {
  static const _systemAuthLifecycleGracePeriod = Duration(seconds: 2);

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
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleSource?.lifecycleRevision.addListener(_onStoreLifecycleRevision);
    _autofillRepository = widget.autofillRepository ?? FakeAutofillRepository();
    _uiPreferencesStore =
        widget.uiPreferencesStore ?? InMemoryUiPreferencesStore();
    _ownsClipboardService = widget.clipboardService == null;
    _clipboardService = widget.clipboardService ?? SensitiveClipboardService();
    unawaited(_loadLocalePreference());
    _isLocked =
        _isLocalSecurityConfigured &&
        widget.securityRepository.shouldLock(widget.now());
    if (_isLocalSecurityConfigured && !_isLocked) {
      _scheduleAutoLock();
    }
  }

  @override
  void didUpdateWidget(covariant ParsGuiApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsRepository == widget.settingsRepository) return;
    if (oldWidget.settingsRepository is StoreLifecycleChangeSource) {
      (oldWidget.settingsRepository as StoreLifecycleChangeSource)
          .lifecycleRevision
          .removeListener(_onStoreLifecycleRevision);
    }
    _lifecycleSource?.lifecycleRevision.addListener(_onStoreLifecycleRevision);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleSource?.lifecycleRevision.removeListener(
      _onStoreLifecycleRevision,
    );
    _lockTimer?.cancel();
    if (_ownsClipboardService) _clipboardService.dispose();
    _privacyEpoch.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isLocalSecurityConfigured) {
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
      navigatorKey: _navigatorKey,
      title: 'Pars',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _localePreference.locale,
      theme: ParsTheme.light(),
      darkTheme: ParsTheme.dark(),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    switch (_presentationState) {
      case _RootPresentationState.securitySetup:
      case _RootPresentationState.storeSetup:
      case _RootPresentationState.storeRepair:
        return OnboardingScreen(
          settingsRepository: widget.settingsRepository,
          keyRepository: widget.keyRepository,
          securityRepository: widget.securityRepository,
          pathPickerService: widget.pathPickerService,
          onComplete: _handleOnboardingComplete,
        );
      case _RootPresentationState.locked:
        return LockScreen(
          securityRepository: widget.securityRepository,
          unlockWithBiometrics: _unlockWithBiometrics,
          onUnlocked: () {
            setState(() => _isLocked = false);
            _scheduleAutoLock();
          },
        );
      case _RootPresentationState.storeRemoving:
        return const _StoreRemovingScreen();
      case _RootPresentationState.ready:
        return MobileShell(
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
          onStoreLifecycleChanged:
              _lifecycleSource == null ? _handleStoreLifecycleChanged : null,
          onOnboardingReset: () {
            _lockTimer?.cancel();
            setState(() => _isLocked = false);
          },
        );
    }
  }

  void _handleOnboardingComplete() {
    if (!mounted) return;
    setState(() => _isLocked = false);
    _scheduleAutoLock();
  }

  StoreLifecycleChangeSource? get _lifecycleSource =>
      widget.settingsRepository is StoreLifecycleChangeSource
          ? widget.settingsRepository as StoreLifecycleChangeSource
          : null;

  void _onStoreLifecycleRevision() {
    unawaited(_handleStoreLifecycleChanged());
  }

  Future<void> _handleStoreLifecycleChanged() async {
    // Invalidate and close secret-bearing routes before presenting no-store UI.
    _privacyEpoch.value += 1;
    if (mounted) {
      setState(() => _navigatorKey = GlobalKey<NavigatorState>());
    }
    await _clearClipboardAfterLock();
    if (!mounted) return;
    if (_isLocalSecurityConfigured && !_isLocked) {
      _scheduleAutoLock();
    }
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
    if (mounted && _isLocalSecurityConfigured) {
      setState(() {
        _navigatorKey = GlobalKey<NavigatorState>();
        _isLocked = true;
      });
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

  bool get _isLocalSecurityConfigured =>
      widget.securityRepository.onboardingComplete &&
      widget.securityRepository.hasGestureVerifier;

  _RootPresentationState get _presentationState {
    if (!_isLocalSecurityConfigured) {
      return _RootPresentationState.securitySetup;
    }
    if (_isLocked) {
      return _RootPresentationState.locked;
    }
    if (_lifecycleSource?.storeRemovalInProgress ?? false) {
      return _RootPresentationState.storeRemoving;
    }
    final lifecycle = widget.settingsRepository.lifecycle;
    if (lifecycle.requiresStoreSetup) {
      return _RootPresentationState.storeSetup;
    }
    if (lifecycle.requiresStoreRepair) {
      return _RootPresentationState.storeRepair;
    }
    return _RootPresentationState.ready;
  }

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

class _StoreRemovingScreen extends StatelessWidget {
  const _StoreRemovingScreen();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      localizations.storeRemovalInProgressTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localizations.storeRemovalInProgressDescription,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
