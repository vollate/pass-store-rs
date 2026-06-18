import 'package:flutter/material.dart';

import '../screens/onboarding/onboarding_screen.dart';
import '../screens/shell/mobile_shell.dart';
import '../services/demo_vault_repository.dart';
import 'pars_theme.dart';

class ParsGuiApp extends StatefulWidget {
  const ParsGuiApp({super.key});

  @override
  State<ParsGuiApp> createState() => _ParsGuiAppState();
}

class _ParsGuiAppState extends State<ParsGuiApp> {
  bool _isOnboardingComplete = false;
  final DemoVaultRepository _repository = const DemoVaultRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pars',
      debugShowCheckedModeBanner: false,
      theme: ParsTheme.light(),
      home: _isOnboardingComplete
          ? MobileShell(repository: _repository)
          : OnboardingScreen(
              onComplete: () {
                setState(() => _isOnboardingComplete = true);
              },
            ),
    );
  }
}
