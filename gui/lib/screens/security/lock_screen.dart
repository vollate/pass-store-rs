import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/security_repository.dart';
import '../../widgets/gesture_lock_input.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.securityRepository,
    required this.unlockWithBiometrics,
    required this.onUnlocked,
  });

  final SecurityRepository securityRepository;
  final Future<bool> Function() unlockWithBiometrics;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;
  late Future<BiometricUnlockStatus> _biometricStatus;
  bool _autoBiometricAttempted = false;
  bool _biometricUnlockInProgress = false;

  @override
  void initState() {
    super.initState();
    _biometricStatus = widget.securityRepository.biometricUnlockStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutomaticBiometricUnlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final widthBound = (constraints.maxWidth - 40).clamp(0.0, 320.0);
            final heightBound = (constraints.maxHeight * 0.52).clamp(
              160.0,
              320.0,
            );
            final gridSize =
                (widthBound < heightBound ? widthBound : heightBound)
                    .toDouble();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.maxHeight - 40)
                          .clamp(0, double.infinity)
                          .toDouble(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 24),
                    Text(
                      context.l10n.unlockPars,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(context.l10n.drawGestureToUnlock),
                    const SizedBox(height: 28),
                    FutureBuilder<BiometricUnlockStatus>(
                      future: _biometricStatus,
                      builder: (context, snapshot) {
                        if (snapshot.data != BiometricUnlockStatus.available) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Center(
                            child: FilledButton.icon(
                              onPressed:
                                  _biometricUnlockInProgress
                                      ? null
                                      : _unlockWithBiometrics,
                              icon: const Icon(Icons.fingerprint),
                              label: Text(context.l10n.unlockWithBiometrics),
                            ),
                          ),
                        );
                      },
                    ),
                    Center(
                      child: GestureLockInput(
                        size: gridSize,
                        onCompleted: (pattern) => _unlock(context, pattern),
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Center(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _unlock(BuildContext context, List<int> pattern) async {
    final isValid = await widget.securityRepository.verifyGesture(pattern);
    if (!context.mounted) {
      return;
    }
    if (!isValid) {
      setState(() => _error = context.l10n.gestureDidNotMatch);
      return;
    }
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (context.mounted) {
      widget.onUnlocked();
    }
  }

  Future<void> _tryAutomaticBiometricUnlock() async {
    if (_autoBiometricAttempted || _biometricUnlockInProgress) {
      return;
    }
    _autoBiometricAttempted = true;
    final status = await _biometricStatus;
    if (!mounted || status != BiometricUnlockStatus.available) {
      return;
    }
    await _unlockWithBiometrics();
  }

  Future<void> _unlockWithBiometrics() async {
    if (_biometricUnlockInProgress) {
      return;
    }
    setState(() {
      _error = null;
      _biometricUnlockInProgress = true;
    });
    final unlocked = await widget.unlockWithBiometrics();
    if (!mounted) {
      return;
    }
    if (!unlocked) {
      setState(() {
        _error = context.l10n.biometricUnlockFailed;
        _biometricUnlockInProgress = false;
      });
      return;
    }
    widget.onUnlocked();
  }
}
