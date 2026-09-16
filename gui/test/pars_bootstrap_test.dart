import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_bootstrap.dart';
import 'package:pars_gui/app/pars_gui_app.dart';

void main() {
  testWidgets('bootstrap paints before startup finishes', (tester) async {
    final started = Completer<Widget>();

    await tester.pumpWidget(ParsBootstrapApp(start: () => started.future));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Set gesture lock'), findsNothing);

    started.complete(ParsGuiApp.fake());
    await tester.pump();

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('bootstrap can retry after a failed start', (tester) async {
    var attempts = 0;
    final started = Completer<Widget>();

    await tester.pumpWidget(
      ParsBootstrapApp(
        start: () async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('startup exploded');
          }
          return started.future;
        },
      ),
    );
    await tester.pump();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('startup exploded'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    started.complete(ParsGuiApp.fake());
    await tester.pump();

    expect(find.text('Set gesture lock'), findsOneWidget);
  });
}
