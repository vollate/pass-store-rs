import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/l10n/app_localizations_en.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/git_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
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

  testWidgets('wide SSH management uses a constrained dialog', (tester) async {
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
      find.text('Git sync and remotes'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Git sync and remotes'));
    await tester.pumpAndSettle();
    expect(find.text('SSH keys'), findsOneWidget);
    await tester.tap(find.text('SSH keys'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsWidgets);
    expect(find.byType(BottomSheet), findsNothing);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('Settings exposes one password store and no PGP management', (
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Password store'), findsOneWidget);
    expect(find.text('Password stores'), findsNothing);
    expect(find.text('PGP keys'), findsNothing);
    await tester.tap(find.text('Password store'));
    await tester.pumpAndSettle();
    expect(find.text('~/.password-store'), findsWidgets);
    expect(find.text('Select'), findsNothing);
    expect(find.text('Set default'), findsNothing);
    expect(find.text('Create'), findsNothing);
    expect(find.text('Import'), findsNothing);
    expect(find.text('Clone'), findsNothing);
    expect(find.text('Disconnect password store'), findsOneWidget);
  });

  testWidgets(
    'Settings presents optional Git separately from store readiness',
    (tester) async {
      await configureGuiTestViewport(tester);
      final repository = _LocalOnlyRepository();
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

      expect(find.text('Local Git · no remote'), findsOneWidget);
      expect(find.text('Password store'), findsOneWidget);
      expect(find.text('Configured'), findsNothing);
    },
  );

  testWidgets('SSH management appears only in Git remote context', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _LocalOnlyRepository();
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Git sync and remotes'));
    await tester.tap(find.text('Git sync and remotes'));
    await tester.pumpAndSettle();

    expect(find.text('SSH keys'), findsNothing);
    final remoteUrl = find.widgetWithText(TextField, 'Remote URL');
    await tester.enterText(remoteUrl, 'https://example.com/pass.git');
    await tester.pump();
    expect(find.text('SSH keys'), findsNothing);
    await tester.enterText(remoteUrl, 'git@example.com:pass.git');
    await tester.pump();
    expect(find.text('SSH keys'), findsOneWidget);
    expect(find.text('SSH key required for this remote'), findsOneWidget);
  });

  testWidgets('SSH deletion requires the human-readable key name', (
    tester,
  ) async {
    await configureGuiTestViewport(tester, viewport: GuiTestViewport.expanded);
    final repository = _SshRecordingRepository();
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
    await tester.tap(find.text('Git sync and remotes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH keys'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('github-mobile-ed25519'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pump();
    expect(repository.deletedName, isNull);
    await tester.enterText(
      find.byType(TextField).last,
      'github-mobile-ed25519',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(repository.deletedName, 'github-mobile-ed25519');
  });

  test('UiProblem localizes summary and redacts secret diagnostics', () {
    final localizations = AppLocalizationsEn();
    final problem = UiProblem.fromError(
      localizations,
      StateError('password=hunter2 failed at /internal/path'),
    );
    expect(problem.summary, localizations.operationFailed);
    expect(problem.diagnostics, isNot(contains('hunter2')));
    expect(problem.diagnostics, isNot(contains('/internal/path')));

    final remoteProblem = UiProblem.fromError(
      localizations,
      StateError(
        'provider content://documents/private-id failed for '
        'https://token@example.com/pass.git?access_token=secret#fragment',
      ),
    );
    expect(remoteProblem.diagnostics, contains('[uri]'));
    expect(
      remoteProblem.diagnostics,
      contains('https://***@example.com/pass.git'),
    );
    expect(remoteProblem.diagnostics, isNot(contains('private-id')));
    expect(remoteProblem.diagnostics, isNot(contains('access_token')));

    final privateKey = UiProblem.fromError(
      localizations,
      StateError('BEGIN PGP PRIVATE KEY BLOCK secret'),
    );
    expect(privateKey.diagnostics, isNull);
  });
}

class _SshRecordingRepository extends FakeParsRepository {
  String? deletedName;

  @override
  Future<void> deleteSshKey(String name) async {
    deletedName = name;
  }
}

class _LocalOnlyRepository extends FakeParsRepository {
  static const StoreStatus _localStore = StoreStatus(
    name: 'Local vault',
    root: '/tmp/local-vault',
    exists: true,
    hasGpgId: true,
    pgpRecipients: <String>['ABCD'],
    pgpKeyMissing: false,
    issues: <String>[],
    gitMode: StoreGitMode.local,
  );

  @override
  StoreStatus? get store => _localStore;

  @override
  StoreGitMode get gitMode => StoreGitMode.local;

  @override
  Future<List<GitRemote>> listRemotes() async => const <GitRemote>[];

  @override
  StoreLifecycleSnapshot get lifecycle => const StoreLifecycleSnapshot(
    configPath: '/tmp/config.toml',
    configExists: true,
    onboardingState: StoreOnboardingState.ready,
    issues: <String>[],
    store: _localStore,
  );
}
