import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/l10n.dart';

const int _gestureDimension = 3;
const double _gestureDotSize = 48;
const double _gestureStrokeWidth = 6;
const double _gestureHitRadius = 44;

class GestureLockInput extends StatefulWidget {
  const GestureLockInput({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.size = 320,
  });

  final ValueChanged<List<int>> onCompleted;
  final bool enabled;
  final double size;

  @override
  State<GestureLockInput> createState() => _GestureLockInputState();
}

class _GestureLockInputState extends State<GestureLockInput> {
  final List<int> _selected = <int>[];
  Offset? _currentPosition;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semanticActions = <CustomSemanticsAction, VoidCallback>{
      if (widget.enabled)
        CustomSemanticsAction(label: context.l10n.clearGesture): _clearPattern,
      if (widget.enabled)
        CustomSemanticsAction(label: context.l10n.submitGesture):
            _completePattern,
    };
    return Semantics(
      label: context.l10n.gesturePatternInput,
      enabled: widget.enabled,
      customSemanticsActions: semanticActions,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: widget.size,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart:
                      widget.enabled
                          ? (details) => _selectDotAt(
                            details.localPosition,
                            constraints.biggest,
                          )
                          : null,
                  onPanUpdate:
                      widget.enabled
                          ? (details) => _selectDotAt(
                            details.localPosition,
                            constraints.biggest,
                          )
                          : null,
                  onPanEnd: widget.enabled ? (_) => _completePattern() : null,
                  onPanCancel: widget.enabled ? _clearPattern : null,
                  child: CustomPaint(
                    painter: _GestureLockPainter(
                      selected: List<int>.unmodifiable(_selected),
                      currentPosition: _currentPosition,
                      activeColor: colorScheme.primary,
                      inactiveColor: colorScheme.outline,
                      selectedFillColor: colorScheme.primaryContainer,
                    ),
                    child: Stack(
                      children: List<Widget>.generate(
                        _gestureDimension * _gestureDimension,
                        (index) {
                          final isSelected = _selected.contains(index);
                          final center = _gestureGridCenterFor(
                            index,
                            constraints.biggest,
                          );
                          return Positioned(
                            left: center.dx - _gestureDotSize / 2,
                            top: center.dy - _gestureDotSize / 2,
                            child: _GestureDot(
                              index: index,
                              selected: isSelected,
                              enabled: widget.enabled,
                              onActivate:
                                  widget.enabled
                                      ? () => _selectSemanticDot(index)
                                      : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (MediaQuery.accessibleNavigationOf(context))
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextButton(
                  onPressed: widget.enabled ? _clearPattern : null,
                  child: Text(context.l10n.clearGesture),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed:
                      widget.enabled && _selected.isNotEmpty
                          ? _completePattern
                          : null,
                  child: Text(context.l10n.submitGesture),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _selectDotAt(Offset position, Size size) {
    final index = _hitDot(position, size);
    setState(() {
      _currentPosition = position;
      if (index == null) {
        return;
      }
      _appendDot(index);
    });
  }

  void _selectSemanticDot(int index) {
    setState(() {
      _currentPosition = null;
      _appendDot(index);
    });
  }

  void _appendDot(int index) {
    if (_selected.isNotEmpty && _selected.last == index) {
      return;
    }
    _selected.add(index);
  }

  int? _hitDot(Offset position, Size size) {
    for (
      var index = 0;
      index < _gestureDimension * _gestureDimension;
      index += 1
    ) {
      final center = _gestureGridCenterFor(index, size);
      if ((center - position).distance <= _gestureHitRadius) {
        return index;
      }
    }
    return null;
  }

  void _completePattern() {
    if (_selected.isNotEmpty) {
      widget.onCompleted(List<int>.unmodifiable(_selected));
    }
    _clearPattern();
  }

  void _clearPattern() {
    setState(() {
      _selected.clear();
      _currentPosition = null;
    });
  }
}

class _GestureDot extends StatelessWidget {
  const _GestureDot({
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onActivate,
  });

  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.outline;
    return Semantics(
      label: context.l10n.gestureDot(index + 1),
      button: true,
      enabled: enabled,
      selected: selected,
      onTap: onActivate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: _gestureDotSize,
        height: _gestureDotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? colorScheme.primaryContainer : colorScheme.surface,
          border: Border.all(color: color, width: selected ? 3 : 2),
        ),
      ),
    );
  }
}

class _GestureLockPainter extends CustomPainter {
  const _GestureLockPainter({
    required this.selected,
    required this.currentPosition,
    required this.activeColor,
    required this.inactiveColor,
    required this.selectedFillColor,
  });

  final List<int> selected;
  final Offset? currentPosition;
  final Color activeColor;
  final Color inactiveColor;
  final Color selectedFillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pathPaint =
        Paint()
          ..color = activeColor
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = _gestureStrokeWidth;

    for (var i = 1; i < selected.length; i += 1) {
      canvas.drawLine(
        _gestureGridCenterFor(selected[i - 1], size),
        _gestureGridCenterFor(selected[i], size),
        pathPaint,
      );
    }

    final current = currentPosition;
    if (selected.isNotEmpty && current != null) {
      canvas.drawLine(
        _gestureGridCenterFor(selected.last, size),
        current,
        pathPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GestureLockPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.currentPosition != currentPosition ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.selectedFillColor != selectedFillColor;
}

Offset _gestureGridCenterFor(int index, Size size) {
  final step = size.shortestSide / _gestureDimension;
  final left = (size.width - size.shortestSide) / 2;
  final top = (size.height - size.shortestSide) / 2;
  return Offset(
    left + step * (index % _gestureDimension) + step / 2,
    top + step * (index ~/ _gestureDimension) + step / 2,
  );
}
