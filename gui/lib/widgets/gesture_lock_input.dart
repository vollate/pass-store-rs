import 'package:flutter/material.dart';
import 'package:pattern_lock/pattern_lock.dart';

const int _patternDimension = 3;
const double _patternPointRadius = 19;
const double _patternRelativePadding = 0.5;
const int _patternSelectThreshold = 28;

class GestureLockInput extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Gesture pattern input',
      child: SizedBox.square(
        dimension: size,
        child: AbsorbPointer(
          absorbing: !enabled,
          child: PatternLock(
            dimension: _patternDimension,
            relativePadding: _patternRelativePadding,
            selectedColor: colorScheme.primary,
            notSelectedColor: colorScheme.outline,
            pointRadius: _patternPointRadius,
            showInput: true,
            selectThreshold: _patternSelectThreshold,
            fillPoints: false,
            onInputComplete: (input) {
              onCompleted(_normalizePattern(input));
            },
          ),
        ),
      ),
    );
  }
}

List<int> _normalizePattern(List<int> input) {
  final normalized = <int>[];
  for (final dot in input) {
    if (dot < 0 || dot >= _patternDimension * _patternDimension) {
      continue;
    }
    if (normalized.isNotEmpty) {
      final skipped = _skippedDotBetween(normalized.last, dot);
      if (skipped != null && !normalized.contains(skipped)) {
        normalized.add(skipped);
      }
    }
    if (!normalized.contains(dot)) {
      normalized.add(dot);
    }
  }
  return List<int>.unmodifiable(normalized);
}

int? _skippedDotBetween(int from, int to) {
  final fromRow = from ~/ _patternDimension;
  final fromColumn = from % _patternDimension;
  final toRow = to ~/ _patternDimension;
  final toColumn = to % _patternDimension;
  final rowDelta = toRow - fromRow;
  final columnDelta = toColumn - fromColumn;

  final skipsRow = rowDelta.abs() == 2;
  final skipsColumn = columnDelta.abs() == 2;
  final straightSkip =
      (skipsRow && columnDelta == 0) || (skipsColumn && rowDelta == 0);
  final diagonalSkip = skipsRow && skipsColumn;
  if (!straightSkip && !diagonalSkip) {
    return null;
  }

  final skippedRow = (fromRow + toRow) ~/ 2;
  final skippedColumn = (fromColumn + toColumn) ~/ 2;
  return skippedRow * _patternDimension + skippedColumn;
}
