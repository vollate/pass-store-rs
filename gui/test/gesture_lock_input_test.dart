import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';

void main() {
  testWidgets('gesture input uses a larger default touch area', (tester) async {
    final completed = <List<int>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: GestureLockInput(onCompleted: completed.add)),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(GestureLockInput));
    expect(box.size.shortestSide, greaterThanOrEqualTo(300));
  });

  testWidgets('gesture input completes selected dots in order', (tester) async {
    final completed = <List<int>>[];
    await _pumpGestureInput(tester, completed);

    await _drawGesture(tester, const <int>[0, 1, 2, 5]);

    expect(completed.single, const <int>[0, 1, 2, 5]);
  });

  testWidgets('gesture input records only the dots actually touched', (
    tester,
  ) async {
    final completed = <List<int>>[];
    await _pumpGestureInput(tester, completed);

    await _drawGesture(tester, const <int>[0, 8]);
    expect(completed.single, const <int>[0, 8]);

    await _drawGesture(tester, const <int>[0, 2, 1, 7, 4]);
    expect(completed.last, const <int>[0, 2, 1, 7, 4]);
  });

  testWidgets('gesture input preserves deliberate node jumps', (tester) async {
    final completed = <List<int>>[];
    await _pumpGestureInput(tester, completed);

    await _drawGesture(tester, const <int>[1, 0, 1, 2]);

    expect(completed.single, const <int>[1, 0, 1, 2]);
  });
}

Future<void> _pumpGestureInput(
  WidgetTester tester,
  List<List<int>> completed,
) async {
  const inputSize = 240.0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: GestureLockInput(size: inputSize, onCompleted: completed.add),
        ),
      ),
    ),
  );
}

Future<void> _drawGesture(WidgetTester tester, List<int> pattern) async {
  final box = tester.renderObject<RenderBox>(find.byType(GestureLockInput));
  final topLeft = box.localToGlobal(Offset.zero);
  const dimension = 3;
  final shortestSide = box.size.shortestSide;
  final left = (box.size.width - shortestSide) / 2;
  final top = (box.size.height - shortestSide) / 2;
  final step = shortestSide / dimension;
  Offset dot(int index) {
    return topLeft +
        Offset(
          left + step * (index % dimension) + step / 2,
          top + step * (index ~/ dimension) + step / 2,
        );
  }

  final gesture = await tester.createGesture();
  await gesture.down(dot(pattern.first));
  await tester.pump();
  await gesture.moveTo(dot(pattern.first) + const Offset(1, 0));
  await tester.pump();
  for (final index in pattern.skip(1)) {
    await gesture.moveTo(dot(index));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}
