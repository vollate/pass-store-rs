import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_design_tokens.dart';
import 'package:pars_gui/app/pars_theme.dart';
import 'package:pars_gui/widgets/pars_action_group.dart';
import 'package:pars_gui/widgets/pars_adaptive_surface.dart';
import 'package:pars_gui/widgets/pars_page_header.dart';
import 'package:pars_gui/widgets/pars_status_badge.dart';

import 'support/gui_test_harness.dart';

void main() {
  test('semantic themes expose contrast-safe section colors', () {
    for (final theme in <ThemeData>[ParsTheme.light(), ParsTheme.dark()]) {
      expect(theme.extension<ParsSemanticColors>(), isNotNull);
      expect(
        _contrast(
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('status and destructive actions use matching semantics', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: Column(
          children: <Widget>[
            const ParsStatusBadge(label: 'Failed', kind: ParsStatusKind.error),
            ParsActionGroup(
              actions: <ParsActionItem>[
                ParsActionItem(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  onPressed: () {},
                  kind: ParsActionKind.destructive,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final delete = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Delete'),
    );
    final foreground = delete.style?.foregroundColor?.resolve(<WidgetState>{});
    expect(foreground, ParsTheme.light().colorScheme.error);
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Delete')).height,
      greaterThanOrEqualTo(ParsSizes.minimumTouchTarget),
    );
    expectNoFlutterOverflow(tester);
  });

  testWidgets('shared headers and actions wrap at 200 percent text scale', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              const ParsSectionHeader(
                title: 'A deliberately long localized section heading',
              ),
              ParsActionGroup(
                actions: <ParsActionItem>[
                  ParsActionItem(
                    label: 'A long primary action',
                    icon: Icons.check,
                    onPressed: () {},
                    kind: ParsActionKind.primary,
                  ),
                  ParsActionItem(
                    label: 'A long secondary action',
                    icon: Icons.info_outline,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectNoFlutterOverflow(tester);
  });

  testWidgets('adaptive helper uses sheet on compact and dialog on wide', (
    tester,
  ) async {
    for (final viewport in <GuiTestViewport>[
      GuiTestViewport.compactPhone,
      GuiTestViewport.expanded,
    ]) {
      await configureGuiTestViewport(tester, viewport: viewport);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: Builder(
            builder:
                (context) => FilledButton(
                  onPressed:
                      () => showParsAdaptiveSurface<void>(
                        context: context,
                        title: 'Surface',
                        builder: (_) => const Text('Body'),
                      ),
                  child: const Text('Open'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      if (viewport == GuiTestViewport.compactPhone) {
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
      } else {
        expect(find.byType(Dialog), findsOneWidget);
      }
      expect(find.text('Body'), findsOneWidget);
      expectNoFlutterOverflow(tester);

      Navigator.of(tester.element(find.text('Body'))).pop();
      await tester.pumpAndSettle();
    }
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance();
  final darker = background.computeLuminance();
  final high = lighter > darker ? lighter : darker;
  final low = lighter > darker ? darker : lighter;
  return (high + 0.05) / (low + 0.05);
}
