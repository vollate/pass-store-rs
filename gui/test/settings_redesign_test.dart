import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/l10n/app_localizations_en.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/ui_problem.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets('Settings prioritizes routine groups over advanced support', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: SettingsScreen(
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository(),
          autofillRepository: FakeAutofillRepository(),
          vaultRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('SECURITY AND PRIVACY'), findsOneWidget);
    expect(find.text('Advanced Git args'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Advanced Git args'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('ADVANCED AND SUPPORT'), findsOneWidget);
    expect(find.text('Runtime diagnostics'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('Autofill failure is concise until Details is expanded', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    final autofill = FakeAutofillRepository();
    const diagnostics =
        'failed to parse /data/user/0/app/files/index.json: unknown field websites';
    autofill.recordSyncFailure(diagnostics);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: SettingsScreen(
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository(),
          autofillRepository: autofill,
          vaultRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('System Autofill'),
      260,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Needs rebuild'), findsOneWidget);
    expect(find.textContaining('/data/user/0'), findsNothing);
    await tester.tap(find.text('System Autofill'));
    await tester.pumpAndSettle();

    expect(find.text('Needs rebuild'), findsWidgets);
    expect(find.text('Diagnostic details'), findsOneWidget);
    expect(find.textContaining('/data/user/0'), findsNothing);
    await tester.tap(find.text('Diagnostic details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/data/user/0'), findsOneWidget);
  });

  testWidgets('wide key management uses a constrained dialog', (tester) async {
    await configureGuiTestViewport(tester, viewport: GuiTestViewport.expanded);
    const repository = FakeParsRepository();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: SettingsScreen(
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('PGP keys'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expectNoFlutterOverflow(tester);
  });

  test('UiProblem localizes summary and redacts secret diagnostics', () {
    final localizations = AppLocalizationsEn();
    final problem = UiProblem.fromError(
      localizations,
      StateError('password=hunter2 failed at /internal/path'),
    );
    expect(problem.summary, localizations.operationFailed);
    expect(problem.diagnostics, isNot(contains('hunter2')));

    final privateKey = UiProblem.fromError(
      localizations,
      StateError('BEGIN PGP PRIVATE KEY BLOCK secret'),
    );
    expect(privateKey.diagnostics, isNull);
  });
}
