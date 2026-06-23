import 'package:flutter/material.dart';

import '../screens/onboarding/onboarding_screen.dart';
import '../screens/shell/mobile_shell.dart';
import '../services/demo_vault_repository.dart';
import '../services/git_repository.dart';
import '../services/key_repository.dart';
import '../services/settings_repository.dart';
import '../services/vault_repository.dart';
import 'pars_theme.dart';

class ParsGuiApp extends StatefulWidget {
  const ParsGuiApp({
    super.key,
    VaultRepository? vaultRepository,
    SettingsRepository? settingsRepository,
    KeyRepository? keyRepository,
    GitRepository? gitRepository,
  }) : vaultRepository = vaultRepository ?? const DemoVaultRepository(),
       settingsRepository = settingsRepository ?? const DemoVaultRepository(),
       keyRepository = keyRepository ?? const DemoVaultRepository(),
       gitRepository = gitRepository ?? const DemoVaultRepository();

  final VaultRepository vaultRepository;
  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;

  @override
  State<ParsGuiApp> createState() => _ParsGuiAppState();
}

class _ParsGuiAppState extends State<ParsGuiApp> {
  bool _isOnboardingComplete = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pars',
      debugShowCheckedModeBanner: false,
      theme: ParsTheme.light(),
      home:
          _isOnboardingComplete
              ? MobileShell(
                vaultRepository: widget.vaultRepository,
                settingsRepository: widget.settingsRepository,
                keyRepository: widget.keyRepository,
                gitRepository: widget.gitRepository,
              )
              : OnboardingScreen(
                onComplete: () {
                  setState(() => _isOnboardingComplete = true);
                },
              ),
    );
  }
}
