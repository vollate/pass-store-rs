import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets('GUI harness configures every supported viewport', (
    tester,
  ) async {
    for (final viewport in GuiTestViewport.values) {
      await configureGuiTestViewport(tester, viewport: viewport);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: const Text('Harness'),
          textScale: viewport == GuiTestViewport.expanded ? 2 : 1,
        ),
      );
      await tester.pump();

      expect(tester.view.physicalSize, viewport.size);
      expect(tester.view.viewInsets.bottom, viewport.keyboardInset);
      expect(find.text('Harness'), findsOneWidget);
      expectNoFlutterOverflow(tester);
    }
  });

  testWidgets('GUI harness renders English and Chinese in both themes', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);

    for (final locale in const <Locale>[Locale('en'), Locale('zh')]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          buildLocalizedTestApp(
            locale: locale,
            brightness: brightness,
            child: const Text(
              'Localized surface',
              key: ValueKey<String>('localized-surface'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(
          find.byKey(const ValueKey<String>('localized-surface')),
        );
        expect(
          Localizations.localeOf(context).languageCode,
          locale.languageCode,
        );
        expect(Theme.of(context).brightness, brightness);
        expectNoFlutterOverflow(tester);
      }
    }
  });
}
