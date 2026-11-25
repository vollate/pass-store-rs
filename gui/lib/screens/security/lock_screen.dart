import 'package:flutter/material.dart';

import '../../app/pars_design_tokens.dart';
import '../../l10n/l10n.dart';
import '../../services/security_repository.dart';
import '../../widgets/biometric_icon.dart';
import '../../widgets/pin_lock_input.dart';

typedef _BiometricInfo = ({BiometricUnlockStatus status, BiometricKind kind});

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
  late Future<_BiometricInfo> _biometricInfo;
  bool _autoBiometricAttempted = false;
  bool _biometricUnlockInProgress = false;
  bool _pinCheckInProgress = false;
  bool _passwordCheckInProgress = false;
  int _pinResetSignal = 0;

  bool get _usesPassword =>
      widget.securityRepository.unlockMethod == LocalUnlockMethod.password;

  @override
  void initState() {
    super.initState();
    _biometricInfo = _loadBiometricInfo();
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

  Future<_BiometricInfo> _loadBiometricInfo() async {
    final status = await widget.securityRepository.biometricUnlockStatus();
    final kind = await widget.securityRepository.biometricKind();
    return (status: status, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_BiometricInfo>(
          future: _biometricInfo,
          builder: (context, snapshot) {
            final biometric = snapshot.data;
            final biometricAvailable =
                biometric?.status == BiometricUnlockStatus.available;
            final biometricKind = biometric?.kind ?? BiometricKind.fingerprint;
            return LayoutBuilder(
              builder: (context, constraints) {
                final minHeight =
                    (constraints.maxHeight - ParsSpacing.lg * 2)
                        .clamp(0, double.infinity)
                        .toDouble();
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(ParsSpacing.lg),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child:
                        _usesPassword
                            ? _buildPasswordLayout(
                              context,
                              biometricAvailable: biometricAvailable,
                              biometricKind: biometricKind,
                            )
                            : _buildPinLayout(
                              context,
                              biometricAvailable: biometricAvailable,
                              biometricKind: biometricKind,
                            ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPinLayout(
    BuildContext context, {
    required bool biometricAvailable,
    required BiometricKind biometricKind,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: ParsSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: ParsSizes.lockBadge,
                height: ParsSizes.lockBadge,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(ParsRadii.card),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: ParsSizes.icon,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: ParsSpacing.md),
              Text(
                context.l10n.unlockPars,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: ParsSpacing.xs),
              Text(
                context.l10n.enterPinToUnlock,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: ParsSpacing.xl),
          child: Center(
            child: PinLockInput(
              enabled: !_pinCheckInProgress,
              hasError: _error != null,
              resetSignal: _pinResetSignal,
              biometricKind: biometricAvailable ? biometricKind : null,
              onBiometricPressed:
                  biometricAvailable ? _unlockWithBiometrics : null,
              biometricEnabled:
                  !_biometricUnlockInProgress && !_pinCheckInProgress,
              biometricTooltip: context.l10n.unlockWithBiometrics,
              statusWidget: _buildErrorNotice(context),
              onChanged: (value) {
                if (_error != null && value.isNotEmpty) {
                  setState(() => _error = null);
                }
              },
              onCompleted: (pin) => _unlockWithPin(context, pin),
            ),
          ),
        ),
        const SizedBox(height: ParsSpacing.sm),
      ],
    );
  }

  Widget _buildPasswordLayout(
    BuildContext context, {
    required bool biometricAvailable,
    required BiometricKind biometricKind,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: ParsSpacing.xl),
            Text(
              context.l10n.unlockPars,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: ParsSpacing.xs),
            Text(context.l10n.enterPasswordToUnlock),
            const SizedBox(height: ParsSpacing.xxl),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(child: _buildPasswordInput(context)),
            if (_error != null) ...<Widget>[
              const SizedBox(height: ParsSpacing.md),
              Center(child: _buildErrorNotice(context)!),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(
            top: ParsSpacing.xl,
            bottom: ParsSpacing.md,
          ),
          child:
              biometricAvailable
                  ? Center(
                    child: FilledButton.tonalIcon(
                      key: const Key('password-biometric-button'),
                      onPressed:
                          _biometricUnlockInProgress
                              ? null
                              : _unlockWithBiometrics,
                      icon: BiometricIcon(kind: biometricKind),
                      label: Text(
                        context.l10n.unlockWithBiometrics,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                  : const SizedBox(height: ParsSpacing.xl),
        ),
      ],
    );
  }

  Widget? _buildErrorNotice(BuildContext context) {
    final error = _error;
    if (error == null) return null;
    return Semantics(
      liveRegion: true,
      child: Text(
        error,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w700,
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

  Future<void> _unlockWithPin(BuildContext context, String pin) async {
    if (_pinCheckInProgress) return;
    setState(() {
      _error = null;
      _pinCheckInProgress = true;
    });
    final isValid = await widget.securityRepository.verifyPin(pin);
    if (!context.mounted) {
      return;
    }
    if (!isValid) {
      setState(() {
        _error = context.l10n.incorrectPin;
        _pinCheckInProgress = false;
        _pinResetSignal += 1;
      });
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
    final info = await _biometricInfo;
    if (!mounted || info.status != BiometricUnlockStatus.available) {
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
