part of '../onboarding_screen.dart';

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({required this.currentStep, required this.steps});

  final _OnboardingStep currentStep;
  final List<_OnboardingStep> steps;

  @override
  Widget build(BuildContext context) {
    final safeSteps = steps.isEmpty ? <_OnboardingStep>[currentStep] : steps;
    final rawIndex = safeSteps.indexOf(currentStep);
    final index = rawIndex < 0 ? safeSteps.length - 1 : rawIndex;
    final current = index + 1;
    final optional = currentStep == _OnboardingStep.biometrics;
    final progressLabel = context.l10n.onboardingProgress(
      current,
      safeSteps.length,
    );
    return Semantics(
      label: progressLabel,
      value: optional ? context.l10n.optional : context.l10n.required,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: current / safeSteps.length),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  progressLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Chip(
                label: Text(
                  optional ? context.l10n.optional : context.l10n.required,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BiometricSetupStep extends StatelessWidget {
  const _BiometricSetupStep({
    required this.securityRepository,
    required this.onEnable,
    required this.onSkip,
    required this.onError,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onEnable;
  final VoidCallback onSkip;
  final void Function(Object error) onError;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BiometricUnlockStatus>(
      future: securityRepository.biometricUnlockStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? BiometricUnlockStatus.unavailable;
        return ListView(
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                status == BiometricUnlockStatus.unavailable
                    ? Icons.fingerprint_outlined
                    : Icons.fingerprint,
              ),
              title: Text(context.l10n.biometricUnlock),
              subtitle: Text(_biometricSubtitle(context.l10n, status)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  status == BiometricUnlockStatus.unavailable
                      ? null
                      : () async {
                        try {
                          await securityRepository.setBiometricUnlockEnabled(
                            true,
                          );
                          onEnable();
                        } catch (error) {
                          onError(error);
                        }
                      },
              icon: const Icon(Icons.fingerprint),
              label: Text(context.l10n.enableBiometricUnlock),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onSkip,
              child: SizedBox(
                width: double.infinity,
                child: Center(child: Text(context.l10n.skipBiometrics)),
              ),
            ),
          ],
        );
      },
    );
  }

  String _biometricSubtitle(
    AppLocalizations localizations,
    BiometricUnlockStatus status,
  ) => switch (status) {
    BiometricUnlockStatus.available => localizations.enabledOnDevice,
    BiometricUnlockStatus.disabled => localizations.availableOnDevice,
    BiometricUnlockStatus.unavailable => localizations.unavailableOnDevice,
  };
}

class _EmptyOnboardingStep extends StatelessWidget {
  const _EmptyOnboardingStep({
    required this.icon,
    required this.title,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: onPressed,
          child: SizedBox(
            width: double.infinity,
            child: Center(child: Text(buttonLabel)),
          ),
        ),
      ],
    );
  }
}
