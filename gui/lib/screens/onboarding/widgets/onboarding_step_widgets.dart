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
    final optional =
        currentStep == _OnboardingStep.biometrics ||
        currentStep == _OnboardingStep.ssh;
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
          const SizedBox(height: ParsSpacing.xs),
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

class _BiometricSetupStep extends StatefulWidget {
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
  State<_BiometricSetupStep> createState() => _BiometricSetupStepState();
}

class _BiometricSetupStepState extends State<_BiometricSetupStep> {
  late Future<({BiometricUnlockStatus status, BiometricKind kind})>
  _biometricsFuture;

  @override
  void initState() {
    super.initState();
    _biometricsFuture = _loadBiometrics();
  }

  @override
  void didUpdateWidget(covariant _BiometricSetupStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.securityRepository != widget.securityRepository) {
      _biometricsFuture = _loadBiometrics();
    }
  }

  Future<({BiometricUnlockStatus status, BiometricKind kind})>
  _loadBiometrics() async {
    final status = await widget.securityRepository.biometricUnlockStatus();
    final kind = await widget.securityRepository.biometricKind();
    return (status: status, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({BiometricUnlockStatus status, BiometricKind kind})>(
      future: _biometricsFuture,
      builder: (context, snapshot) {
        final status =
            snapshot.data?.status ?? BiometricUnlockStatus.unavailable;
        final kind = snapshot.data?.kind ?? BiometricKind.fingerprint;
        return ListView(
          children: <Widget>[
            AppSectionBox(
              padding: EdgeInsets.zero,
              children: <Widget>[
                ParsSectionRow(
                  leading: ParsSectionRowIcon.custom(
                    child: BiometricIcon(kind: kind),
                  ),
                  title: context.l10n.biometricUnlock,
                  subtitle: _biometricSubtitle(context.l10n, status),
                ),
              ],
            ),
            const SizedBox(height: ParsSpacing.md),
            ParsButtonGrid(
              children: <Widget>[
                OutlinedButton(
                  onPressed: widget.onSkip,
                  child: Text(
                    context.l10n.skipBiometrics,
                    textAlign: TextAlign.center,
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      status == BiometricUnlockStatus.unavailable
                          ? null
                          : () async {
                            try {
                              await widget.securityRepository
                                  .setBiometricUnlockEnabled(true);
                              widget.onEnable();
                            } catch (error) {
                              widget.onError(error);
                            }
                          },
                  icon: BiometricIcon(kind: kind),
                  label: Text(
                    context.l10n.enableBiometricUnlock,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
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
        AppSectionBox(
          padding: EdgeInsets.zero,
          children: <Widget>[
            ParsSectionRow(
              leading: ParsSectionRowIcon(icon: icon),
              title: title,
            ),
          ],
        ),
        const SizedBox(height: ParsSpacing.md),
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
