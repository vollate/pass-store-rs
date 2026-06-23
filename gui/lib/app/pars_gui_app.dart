import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/onboarding/onboarding_screen.dart';
import '../screens/security/lock_screen.dart';
import '../screens/shell/mobile_shell.dart';
import '../services/fake_pars_repository.dart';
import '../services/git_repository.dart';
import '../services/key_repository.dart';
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

  @override
  State<ParsGuiApp> createState() => _ParsGuiAppState();
}

class _ParsGuiAppState extends State<ParsGuiApp> with WidgetsBindingObserver {
  late bool _isOnboardingComplete;
  late bool _isLocked;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isOnboardingComplete = widget.securityRepository.hasGestureVerifier;
    _isLocked =
        _isOnboardingComplete &&
        widget.securityRepository.shouldLock(DateTime.now());
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
    if (state == AppLifecycleState.resumed &&
        _isOnboardingComplete &&
        (widget.securityRepository.lockOnResume ||
            widget.securityRepository.shouldLock(DateTime.now()))) {
      _lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pars',
      debugShowCheckedModeBanner: false,
      theme: ParsTheme.light(),
      home:
          !_isOnboardingComplete
              ? OnboardingScreen(
                settingsRepository: widget.settingsRepository,
                securityRepository: widget.securityRepository,
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
                onSecuritySettingsChanged: _scheduleAutoLock,
              ),
    );
  }

  void _scheduleAutoLock() {
    _lockTimer?.cancel();
    final timeout = widget.securityRepository.autoLockTimeout;
    if (timeout <= Duration.zero) {
      return;
    }
    _lockTimer = Timer(timeout, _lock);
  }

  void _lock() {
    _lockTimer?.cancel();
    widget.securityRepository.markLocked();
    if (mounted && _isOnboardingComplete) {
      setState(() => _isLocked = true);
    }
  }
}
