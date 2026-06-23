import 'package:flutter/material.dart';

class GestureLockInput extends StatefulWidget {
  const GestureLockInput({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.size = 220,
  });

  final ValueChanged<List<int>> onCompleted;
  final bool enabled;
  final double size;

  @override
  State<GestureLockInput> createState() => _GestureLockInputState();
}

class _GestureLockInputState extends State<GestureLockInput> {
  final List<int> _selected = <int>[];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Gesture pattern input',
      child: SizedBox.square(
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
              child: CustomPaint(
                painter: _GestureLockPainter(
                  selected: List<int>.unmodifiable(_selected),
                  activeColor: colorScheme.primary,
                  inactiveColor: colorScheme.outlineVariant,
                ),
                child: Stack(
                  children: List<Widget>.generate(9, (index) {
                    final alignment = Alignment(
                      (-1 + (index % 3)).toDouble(),
                      (-1 + (index ~/ 3)).toDouble(),
                    );
                    final isSelected = _selected.contains(index);
                    return Align(
                      alignment: alignment,
                      child: _GestureDot(
                        index: index,
                        selected: isSelected,
                        enabled: widget.enabled,
                        onTap: () => _toggleDot(index),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _toggleDot(int index) {
    if (!widget.enabled) {
      return;
    }
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  void _selectDotAt(Offset position, Size size) {
    final cell = size.width / 3;
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > size.width ||
        position.dy > size.height) {
      return;
    }
    final column = (position.dx / cell).floor().clamp(0, 2);
    final row = (position.dy / cell).floor().clamp(0, 2);
    final index = row * 3 + column;
    if (_selected.contains(index)) {
      return;
    }
    setState(() => _selected.add(index));
  }

  void _completePattern() {
    if (_selected.isEmpty) {
      return;
    }
    widget.onCompleted(List<int>.unmodifiable(_selected));
    setState(_selected.clear);
  }
}

class _GestureDot extends StatelessWidget {
  const _GestureDot({
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.outline;
    return Semantics(
      button: true,
      label: 'Gesture dot ${index + 1}',
      child: InkResponse(
        key: ValueKey<String>('gesture-dot-$index'),
        onTap: enabled ? onTap : null,
        radius: 28,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? colorScheme.primaryContainer : Colors.white,
            border: Border.all(color: color, width: selected ? 3 : 2),
          ),
        ),
      ),
    );
  }
}

class _GestureLockPainter extends CustomPainter {
  const _GestureLockPainter({
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<int> selected;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (selected.length < 2) {
      return;
    }
    final paint =
        Paint()
          ..color = activeColor
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5;
    for (var i = 1; i < selected.length; i += 1) {
      canvas.drawLine(
        _centerFor(selected[i - 1], size),
        _centerFor(selected[i], size),
        paint,
      );
    }
  }

  Offset _centerFor(int index, Size size) {
    final cell = size.width / 3;
    return Offset(
      cell * (index % 3) + cell / 2,
      cell * (index ~/ 3) + cell / 2,
    );
  }

  @override
  bool shouldRepaint(_GestureLockPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}
