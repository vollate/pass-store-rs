import 'package:flutter/material.dart';

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
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: GestureLockInput(
              enabled: !_isSaving,
              onCompleted: (pattern) => _handlePattern(context, pattern),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text(
            _message ??
                (_isConfirming
                    ? 'Draw the same gesture again.'
                    : 'Draw at least 4 dots.'),
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
                    _message = 'Start again with a new gesture.';
                  }),
          child: const SizedBox(
            width: double.infinity,
            child: Center(child: Text('Reset gesture')),
          ),
        ),
      ],
    );
  }

  Future<void> _handlePattern(BuildContext context, List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() => _message = 'Use at least 4 dots.');
      return;
    }
    final first = _initialPattern;
    if (first == null) {
      setState(() {
        _initialPattern = pattern;
        _message = 'Gesture captured. Confirm it once more.';
      });
      return;
    }
    if (!_samePattern(first, pattern)) {
      setState(() {
        _initialPattern = null;
        _message = 'Gestures did not match. Start again.';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _message = 'Gesture confirmed.';
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
