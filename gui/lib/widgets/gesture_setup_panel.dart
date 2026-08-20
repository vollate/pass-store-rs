import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/security_repository.dart';
import 'gesture_lock_input.dart';

class GestureSetupPanel extends StatefulWidget {
  const GestureSetupPanel({
    super.key,
    required this.securityRepository,
    required this.onSaved,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onSaved;

  @override
  State<GestureSetupPanel> createState() => _GestureSetupPanelState();
}

class _GestureSetupPanelState extends State<GestureSetupPanel> {
  List<int>? _initialPattern;
  String? _message;
  bool _isSaving = false;

  bool get _isConfirming => _initialPattern != null;

  @override
  Widget build(BuildContext context) {
    Widget grid(double size) => Center(
      child: GestureLockInput(
        size: size,
        enabled: !_isSaving,
        onCompleted: (pattern) => _handlePattern(context, pattern),
      ),
    );
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text(
            _message ??
                (_isConfirming
                    ? context.l10n.drawSameGesture
                    : context.l10n.drawAtLeastFourDots),
            key: ValueKey<String>(_message ?? 'default-$_isConfirming'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  _message == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed:
              _initialPattern == null || _isSaving
                  ? null
                  : () => setState(() {
                    _initialPattern = null;
                    _message = context.l10n.startNewGesture;
                  }),
          child: SizedBox(
            width: double.infinity,
            child: Center(child: Text(context.l10n.resetGesture)),
          ),
        ),
      ],
    );
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (largeText) {
          final inputSize = constraints.maxWidth.clamp(0.0, 320.0).toDouble();
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[grid(inputSize), controls],
            ),
          );
        }
        return Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (context, gridConstraints) {
                  final inputSize =
                      gridConstraints.biggest.shortestSide
                          .clamp(0.0, 320.0)
                          .toDouble();
                  return grid(inputSize);
                },
              ),
            ),
            controls,
          ],
        );
      },
    );
  }

  Future<void> _handlePattern(BuildContext context, List<int> pattern) async {
    final localizations = context.l10n;
    if (pattern.length < 4) {
      setState(() => _message = localizations.useAtLeastFourDots);
      return;
    }
    final first = _initialPattern;
    if (first == null) {
      setState(() {
        _initialPattern = pattern;
        _message = localizations.gestureCapturedConfirm;
      });
      return;
    }
    if (!_samePattern(first, pattern)) {
      setState(() {
        _initialPattern = null;
        _message = localizations.gesturesDidNotMatch;
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _message = localizations.gestureConfirmed;
    });
    await widget.securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(pattern),
    );
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (context.mounted) {
      widget.onSaved();
    }
  }

  bool _samePattern(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
