import 'package:flutter/material.dart';

import '../screens/onboarding/onboarding_screen.dart';
import '../screens/shell/mobile_shell.dart';
import '../services/fake_pars_repository.dart';
import '../services/git_repository.dart';
import '../services/key_repository.dart';
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
  });

  factory ParsGuiApp.fake({Key? key}) {
    const repository = FakeParsRepository();
    return ParsGuiApp(
      key: key,
      vaultRepository: repository,
      settingsRepository: repository,
      keyRepository: repository,
      gitRepository: repository,
    );
  }

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
                settingsRepository: widget.settingsRepository,
                onComplete: () {
                  setState(() => _isOnboardingComplete = true);
                },
              ),
    );
  }
}
