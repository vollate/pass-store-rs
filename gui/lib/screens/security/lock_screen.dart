import 'package:flutter/material.dart';

import '../../app/pars_design_tokens.dart';
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
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  String? _error;
  late Future<BiometricUnlockStatus> _biometricStatus;
  bool _autoBiometricAttempted = false;
  bool _biometricUnlockInProgress = false;
  bool _passwordCheckInProgress = false;

  bool get _usesPassword =>
      widget.securityRepository.unlockMethod == LocalUnlockMethod.password;

  @override
  void initState() {
    super.initState();
    _biometricStatus = widget.securityRepository.biometricUnlockStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutomaticBiometricUnlock();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final widthBound = (constraints.maxWidth - ParsSpacing.lg * 2)
                .clamp(0.0, ParsSizes.gestureGrid);
            final heightBound = (constraints.maxHeight *
                    ParsSizes.gestureGridViewportFactor)
                .clamp(ParsSizes.gestureGridMin, ParsSizes.gestureGrid);
            final gridSize =
                (widthBound < heightBound ? widthBound : heightBound)
                    .toDouble();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(ParsSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.maxHeight - ParsSpacing.lg * 2)
                          .clamp(0, double.infinity)
                          .toDouble(),
                ),
                // The password form is short, so it sits in the middle of the
                // free space rather than under the title.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment:
                      _usesPassword
                          ? MainAxisAlignment.spaceBetween
                          : MainAxisAlignment.start,
                  children: <Widget>[
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: ParsSpacing.xl),
                        Text(
                          context.l10n.unlockPars,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: ParsSpacing.xs),
                        Text(
                          _usesPassword
                              ? context.l10n.enterPasswordToUnlock
                              : context.l10n.drawGestureToUnlock,
                        ),
                        const SizedBox(height: ParsSpacing.xxl),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        FutureBuilder<BiometricUnlockStatus>(
                          future: _biometricStatus,
                          builder: (context, snapshot) {
                            if (snapshot.data !=
                                BiometricUnlockStatus.available) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: ParsSpacing.lg,
                              ),
                              child: Center(
                                child: FilledButton.icon(
                                  onPressed:
                                      _biometricUnlockInProgress
                                          ? null
                                          : _unlockWithBiometrics,
                                  icon: const Icon(Icons.fingerprint),
                                  label: Text(
                                    context.l10n.unlockWithBiometrics,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        Center(
                          child:
                              _usesPassword
                                  ? _buildPasswordInput(context)
                                  : GestureLockInput(
                                    size: gridSize,
                                    onCompleted:
                                        (pattern) => _unlock(context, pattern),
                                  ),
                        ),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: ParsSpacing.md),
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
                      ],
                    ),
                    const SizedBox(height: ParsSpacing.xl),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPasswordInput(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ParsContentWidth.narrow),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('unlock-password-field'),
            controller: _password,
            focusNode: _passwordFocus,
            autofocus: true,
            enabled: !_passwordCheckInProgress,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: context.l10n.password),
            onSubmitted: (_) => _unlockWithPassword(context),
          ),
          const SizedBox(height: ParsSpacing.md),
          FilledButton(
            onPressed:
                _passwordCheckInProgress
                    ? null
                    : () => _unlockWithPassword(context),
            child: Text(context.l10n.unlockAction, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Future<void> _unlockWithPassword(BuildContext context) async {
    if (_passwordCheckInProgress || _password.text.isEmpty) return;
    setState(() {
      _error = null;
      _passwordCheckInProgress = true;
    });
    final isValid = await widget.securityRepository.verifyPassword(
      _password.text,
    );
    if (!context.mounted) return;
    if (!isValid) {
      _password.clear();
      setState(() {
        _error = context.l10n.incorrectPassword;
        _passwordCheckInProgress = false;
      });
      _passwordFocus.requestFocus();
      return;
    }
    _password.clear();
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (context.mounted) {
      widget.onUnlocked();
    }
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
