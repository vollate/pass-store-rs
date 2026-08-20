import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/screens/security/lock_screen.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/screens/vault/entry_detail_sheet.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';

import 'support/gui_test_harness.dart';

void main() {
  const repository = FakeParsRepository();

  testWidgets('landscape shell selects adaptive rail without overflow', (
    tester,
  ) async {
    await configureGuiTestViewport(
      tester,
      viewport: GuiTestViewport.compactLandscape,
    );
    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: _readySecurity(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('entry detail remains scrollable at 200 percent text scale', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final entry = repository.entries.firstWhere((entry) => !entry.isDirectory);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: EntryDetailSheet(entry: entry, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reveal'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('Chinese Settings remains scrollable at large text', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
        textScale: 2,
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
      find.text('运行时诊断'),
      350,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('高级与支持'), findsOneWidget);
    expect(find.text('运行时诊断'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('lock remains scrollable in landscape at 200 percent text', (
    tester,
  ) async {
    await configureGuiTestViewport(
      tester,
      viewport: GuiTestViewport.compactLandscape,
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: LockScreen(
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
          ),
          unlockWithBiometrics: () async => false,
          onUnlocked: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Unlock Pars'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('Vault and detail expose named semantic actions and states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
          onLock: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel(RegExp('GitHub, work/dev')), findsWidgets);
    expect(find.byTooltip('Copy password'), findsWidgets);
    expect(find.byTooltip('Favorite'), findsWidgets);
    expect(find.byTooltip('Lock now'), findsOneWidget);
    semantics.dispose();
  });
}

InMemorySecurityRepository _readySecurity() {
  return InMemorySecurityRepository.withPattern(
    const <int>[0, 1, 2, 5],
    onboardingComplete: true,
    lastUnlockedAt: DateTime.now(),
  );
}
