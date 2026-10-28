import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/ui_problem.dart';
import 'package:pars_gui/widgets/failure_notice.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets('failure details ignore a scroll offset stored for the same page', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);

    Future<void> pump({required bool showDetails}) {
      return tester.pumpWidget(
        buildLocalizedTestApp(
          child: CustomScrollView(
            key: const PageStorageKey<String>('vault-destination'),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Column(
                  children: <Widget>[
                    if (showDetails)
                      const FailureNotice(
                        problem: UiProblem(
                          summary: 'Could not load the vault.',
                          diagnostics: 'connection refused',
                        ),
                      ),
                    const SizedBox(height: 2400),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // The shell keys the whole vault page. Scrolling stores a double in that
    // slot; the details tile is created afterwards, as it is after a failed
    // refresh.
    await pump(showDetails: false);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await pump(showDetails: true);
    await tester.pumpAndSettle();

    expect(find.text('Could not load the vault.'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('connection refused'), findsNothing);

    // The saved offset leaves the new banner above the viewport.
    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.textContaining('connection refused'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });
}
