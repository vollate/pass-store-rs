part of '../onboarding_screen.dart';

class _StepRail extends StatelessWidget {
  const _StepRail({required this.currentStep});

  final _OnboardingStep currentStep;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final step in _OnboardingStep.values)
          ChoiceChip(
            label: Text(_shortLabel(step)),
            selected: step == currentStep,
            onSelected: null,
          ),
      ],
    );
  }

  String _shortLabel(_OnboardingStep step) {
    switch (step) {
      case _OnboardingStep.gesture:
        return 'Gesture';
      case _OnboardingStep.biometrics:
        return 'Biometrics';
      case _OnboardingStep.pgp:
        return 'PGP';
      case _OnboardingStep.ssh:
        return 'SSH';
      case _OnboardingStep.store:
        return 'Store';
      case _OnboardingStep.review:
        return 'Review';
    }
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
              title: const Text('Biometric unlock'),
              subtitle: Text(_biometricSubtitle(status)),
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
              label: const Text('Enable biometric unlock'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onSkip,
              child: const SizedBox(
                width: double.infinity,
                child: Center(child: Text('Skip biometrics')),
              ),
            ),
          ],
        );
      },
    );
  }

  String _biometricSubtitle(BiometricUnlockStatus status) {
    switch (status) {
      case BiometricUnlockStatus.available:
        return 'Enabled on this device';
      case BiometricUnlockStatus.disabled:
        return 'Available on this device';
      case BiometricUnlockStatus.unavailable:
        return 'Unavailable on this device';
    }
  }
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

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.hasGestureVerifier,
    required this.biometricUnlockEnabled,
    required this.storeStatusLabel,
    required this.storeSetupComplete,
    required this.pgpKeyCount,
    required this.sshKeyCount,
    required this.onFinish,
  });

  final bool hasGestureVerifier;
  final bool biometricUnlockEnabled;
  final String storeStatusLabel;
  final bool storeSetupComplete;
  final int pgpKeyCount;
  final int sshKeyCount;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        _ReviewTile(
          label: 'Gesture lock',
          value: hasGestureVerifier ? 'Configured' : 'Required',
          complete: hasGestureVerifier,
        ),
        _ReviewTile(
          label: 'Biometrics',
          value: biometricUnlockEnabled ? 'Enabled' : 'Skipped',
          complete: true,
        ),
        _ReviewTile(
          label: 'Password store',
          value: storeStatusLabel,
          complete: storeSetupComplete,
        ),
        _ReviewTile(
          label: 'PGP key',
          value: pgpKeyCount == 0 ? 'Not found' : '$pgpKeyCount key(s)',
          complete: pgpKeyCount > 0,
        ),
        _ReviewTile(
          label: 'SSH key',
          value: sshKeyCount == 0 ? 'Skipped' : '$sshKeyCount key(s)',
          complete: true,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: storeSetupComplete ? onFinish : null,
          child: const SizedBox(
            width: double.infinity,
            child: Center(child: Text('Finish setup')),
          ),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.label,
    required this.value,
    required this.complete,
  });

  final String label;
  final String value;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        complete ? Icons.check_circle_outline : Icons.error_outline,
        color: complete ? null : Theme.of(context).colorScheme.error,
      ),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
