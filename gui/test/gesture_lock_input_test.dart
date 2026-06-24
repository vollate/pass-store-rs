import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';

void main() {
  testWidgets('gesture dots sit on the same grid centers used by the path', (
    tester,
  ) async {
    const inputSize = 240.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureLockInput(size: inputSize, onCompleted: (_) {}),
          ),
        ),
      ),
    );

    final inputTopLeft = tester.getTopLeft(find.byType(GestureLockInput));
    final cell = inputSize / 3;

    for (var index = 0; index < 9; index += 1) {
      final expectedCenter =
          inputTopLeft +
          Offset(cell * (index % 3) + cell / 2, cell * (index ~/ 3) + cell / 2);
      final actualCenter = tester.getCenter(
        find.byKey(ValueKey<String>('gesture-dot-$index')),
      );
      expect(actualCenter.dx, closeTo(expectedCenter.dx, 0.01));
      expect(actualCenter.dy, closeTo(expectedCenter.dy, 0.01));
    }
  });
}
