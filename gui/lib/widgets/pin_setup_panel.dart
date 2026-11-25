import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/l10n.dart';
import '../services/security_repository.dart';
import 'pin_lock_input.dart';

class PinSetupPanel extends StatefulWidget {
  const PinSetupPanel({
    super.key,
    required this.securityRepository,
    required this.onSaved,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onSaved;

  @override
  State<PinSetupPanel> createState() => _PinSetupPanelState();
}

class _PinSetupPanelState extends State<PinSetupPanel> {
  String? _initialPin;
  String? _message;
  bool _isError = false;
  bool _isSaving = false;
  int _resetSignal = 0;

  bool get _isConfirming => _initialPin != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final statusText =
        _message ??
        (_isConfirming ? l10n.enterSamePin : l10n.enterSixDigitPin);
    final statusColor =
        _isError
            ? colorScheme.error
            : _message == null
            ? colorScheme.onSurfaceVariant
            : colorScheme.primary;
    final statusWidget = AnimatedSwitcher(
      duration: ParsMotion.quick,
      child: Semantics(
        liveRegion: true,
        child: Text(
          statusText,
          key: ValueKey<String>('$statusText-$_isConfirming-$_isError'),
          textAlign: TextAlign.center,
          style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
    final resetButton = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ParsSizes.pinKeypadMaxWidth),
      child: OutlinedButton(
        onPressed:
            _initialPin == null || _isSaving
                ? null
                : () => setState(() {
                  _initialPin = null;
                  _isError = false;
                  _message = l10n.startNewPin;
                  _resetSignal += 1;
                }),
        child: SizedBox(
          width: double.infinity,
          child: Center(child: Text(l10n.resetPin)),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PinLockInput(
              enabled: !_isSaving,
              hasError: _isError,
              resetSignal: _resetSignal,
              statusWidget: statusWidget,
              onChanged: (_) {
                if (_isError) {
                  setState(() => _isError = false);
                }
              },
              onCompleted: (pin) => _handlePin(context, pin),
            ),
            const SizedBox(height: ParsSpacing.lg),
            resetButton,
          ],
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  Future<void> _handlePin(BuildContext context, String pin) async {
    if (_isSaving) return;
    final l10n = context.l10n;
    final first = _initialPin;
    if (first == null) {
      setState(() {
        _initialPin = pin;
        _isError = false;
        _message = l10n.pinCapturedConfirm;
        _resetSignal += 1;
      });
      return;
    }
    if (first != pin) {
      setState(() {
        _initialPin = null;
        _isError = true;
        _message = l10n.pinsDidNotMatch;
        _resetSignal += 1;
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _isError = false;
      _message = l10n.pinConfirmed;
    });
    await widget.securityRepository.savePin(pin);
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (context.mounted) {
      widget.onSaved();
    }
  }
}
