import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/l10n.dart';
import '../services/security_repository.dart';
import 'biometric_icon.dart';

/// 6-digit PIN indicator dots paired with a thumb-friendly 3x4 circular numeric
/// keypad (`1-9`, optional biometric slot, `0`, backspace).
class PinLockInput extends StatefulWidget {
  const PinLockInput({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.length = PinVerifier.pinLength,
    this.enabled = true,
    this.hasError = false,
    this.clearOnComplete = false,
    this.resetSignal = 0,
    this.biometricKind,
    this.onBiometricPressed,
    this.biometricEnabled = true,
    this.biometricTooltip,
    this.statusWidget,
    this.autofocus = true,
  });

  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final int length;
  final bool enabled;
  final bool hasError;
  final bool clearOnComplete;
  final int resetSignal;
  final BiometricKind? biometricKind;
  final VoidCallback? onBiometricPressed;
  final bool biometricEnabled;
  final String? biometricTooltip;
  final Widget? statusWidget;
  final bool autofocus;

  @override
  State<PinLockInput> createState() => _PinLockInputState();
}

class _PinLockInputState extends State<PinLockInput> {
  final FocusNode _focusNode = FocusNode();
  String _digits = '';

  @override
  void didUpdateWidget(covariant PinLockInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetSignal != oldWidget.resetSignal && _digits.isNotEmpty) {
      setState(() => _digits = '');
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: Semantics(
        label: l10n.pinInputLabel,
        value: l10n.pinInputProgress(_digits.length, widget.length),
        enabled: widget.enabled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth.isFinite
                    ? constraints.maxWidth.clamp(
                      0.0,
                      ParsSizes.pinKeypadMaxWidth,
                    )
                    : ParsSizes.pinKeypadMaxWidth;
            final tightWidth = maxWidth < ParsSizes.pinKeypadMaxWidth;
            final horizontalGap = tightWidth ? ParsSpacing.md : ParsSpacing.xl;
            final verticalGap = tightWidth ? ParsSpacing.sm : ParsSpacing.md;
            final keyFromWidth = (maxWidth - horizontalGap * 2) / 3;
            var keySize = keyFromWidth.clamp(
              ParsSizes.pinKeyMin,
              ParsSizes.pinKey,
            );
            if (constraints.maxHeight.isFinite) {
              // Reserve vertical room for the dots, status row, and gaps.
              final reserved =
                  ParsSizes.pinDot +
                  ParsSpacing.xl +
                  ParsSpacing.lg +
                  verticalGap * 3;
              final keyFromHeight = (constraints.maxHeight - reserved) / 4;
              if (keyFromHeight < keySize) {
                keySize = keyFromHeight.clamp(
                  ParsSizes.pinKeyMin,
                  ParsSizes.pinKey,
                );
              }
            }
            final showBiometric =
                widget.onBiometricPressed != null &&
                widget.biometricKind != null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PinDotsRow(
                  length: widget.length,
                  enteredCount: _digits.length,
                  hasError: widget.hasError,
                ),
                if (widget.statusWidget != null) ...<Widget>[
                  const SizedBox(height: ParsSpacing.md),
                  widget.statusWidget!,
                  const SizedBox(height: ParsSpacing.lg),
                ] else
                  const SizedBox(height: ParsSpacing.xxl),
                _buildKeypadRow(
                  digits: const <int>[1, 2, 3],
                  keySize: keySize,
                  horizontalGap: horizontalGap,
                ),
                SizedBox(height: verticalGap),
                _buildKeypadRow(
                  digits: const <int>[4, 5, 6],
                  keySize: keySize,
                  horizontalGap: horizontalGap,
                ),
                SizedBox(height: verticalGap),
                _buildKeypadRow(
                  digits: const <int>[7, 8, 9],
                  keySize: keySize,
                  horizontalGap: horizontalGap,
                ),
                SizedBox(height: verticalGap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (showBiometric)
                      _PinBiometricKey(
                        size: keySize,
                        kind: widget.biometricKind!,
                        tooltip:
                            widget.biometricTooltip ??
                            l10n.unlockWithBiometrics,
                        onPressed:
                            widget.biometricEnabled
                                ? widget.onBiometricPressed
                                : null,
                      )
                    else
                      SizedBox.square(dimension: keySize),
                    SizedBox(width: horizontalGap),
                    _PinDigitKey(
                      digit: 0,
                      size: keySize,
                      enabled: widget.enabled,
                      onPressed: () => _appendDigit(0),
                    ),
                    SizedBox(width: horizontalGap),
                    _PinBackspaceKey(
                      size: keySize,
                      tooltip: l10n.deletePinDigit,
                      enabled: widget.enabled && _digits.isNotEmpty,
                      onPressed: _deleteDigit,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeypadRow({
    required List<int> digits,
    required double keySize,
    required double horizontalGap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var index = 0; index < digits.length; index++) ...<Widget>[
          if (index > 0) SizedBox(width: horizontalGap),
          _PinDigitKey(
            digit: digits[index],
            size: keySize,
            enabled: widget.enabled,
            onPressed: () => _appendDigit(digits[index]),
          ),
        ],
      ],
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete) {
        _deleteDigit();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clear();
      return KeyEventResult.handled;
    }
    final digit = _digitFromKeyEvent(event);
    if (digit != null) {
      _appendDigit(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int? _digitFromKeyEvent(KeyDownEvent event) {
    final character = event.character;
    if (character != null && character.length == 1) {
      final code = character.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        return code - 0x30;
      }
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return 0;
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return 1;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return 2;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return 3;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return 4;
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return 5;
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      return 6;
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      return 7;
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      return 8;
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      return 9;
    }
    return null;
  }

  void _appendDigit(int digit) {
    if (!widget.enabled || _digits.length >= widget.length) return;
    final next = '$_digits$digit';
    setState(() => _digits = next);
    widget.onChanged?.call(next);
    if (next.length == widget.length) {
      widget.onCompleted(next);
      if (widget.clearOnComplete && mounted) {
        setState(() => _digits = '');
      }
    }
  }

  void _deleteDigit() {
    if (!widget.enabled || _digits.isEmpty) return;
    final next = _digits.substring(0, _digits.length - 1);
    setState(() => _digits = next);
    widget.onChanged?.call(next);
  }

  void _clear() {
    if (_digits.isEmpty) return;
    setState(() => _digits = '');
    widget.onChanged?.call('');
  }
}

class _PinDotsRow extends StatelessWidget {
  const _PinDotsRow({
    required this.length,
    required this.enteredCount,
    required this.hasError,
  });

  final int length;
  final int enteredCount;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      key: const Key('pin-dots'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var index = 0; index < length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: ParsSpacing.md),
          AnimatedContainer(
            key: Key('pin-dot-$index'),
            duration: ParsMotion.quick,
            width: ParsSizes.pinDot,
            height: ParsSizes.pinDot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  index < enteredCount
                      ? (hasError ? colorScheme.error : colorScheme.primary)
                      : colorScheme.surfaceContainerHighest,
              border: Border.all(
                color:
                    index < enteredCount
                        ? (hasError ? colorScheme.error : colorScheme.primary)
                        : (hasError
                            ? colorScheme.error
                            : colorScheme.outlineVariant),
                width: ParsSizes.hairline,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PinDigitKey extends StatelessWidget {
  const _PinDigitKey({
    required this.digit,
    required this.size,
    required this.enabled,
    required this.onPressed,
  });

  final int digit;
  final double size;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fillColor =
        isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest;
    final label = digit.toString();
    return SizedBox.square(
      dimension: size,
      child: Material(
        key: Key('pin-key-$digit'),
        color: fillColor,
        elevation: isDark ? ParsElevation.flat : ParsElevation.scrolledUnder,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
        shape: CircleBorder(
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: ParsSizes.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(ParsSpacing.xs),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color:
                        enabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinBiometricKey extends StatelessWidget {
  const _PinBiometricKey({
    required this.size,
    required this.kind,
    required this.tooltip,
    required this.onPressed,
  });

  final double size;
  final BiometricKind kind;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fillColor =
        isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest;
    final iconSize =
        size < ParsSizes.pinKey
            ? ParsSizes.icon
            : ParsSizes.biometricKeyIcon;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: onPressed != null,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            key: const Key('pin-biometric-button'),
            color: fillColor,
            elevation: isDark ? ParsElevation.flat : ParsElevation.scrolledUnder,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
            shape: CircleBorder(
              side: BorderSide(
                color: colorScheme.outlineVariant,
                width: ParsSizes.hairline,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child: BiometricIcon(
                  kind: kind,
                  size: iconSize,
                  color:
                      onPressed != null
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinBackspaceKey extends StatelessWidget {
  const _PinBackspaceKey({
    required this.size,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final double size;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: enabled,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            key: const Key('pin-backspace-button'),
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: Icon(
                  Icons.backspace_outlined,
                  size: ParsSizes.icon,
                  color:
                      enabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
