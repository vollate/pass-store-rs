import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/git_repository.dart';
import 'package:pars_gui/services/key_repository.dart';
import 'package:pars_gui/services/settings_repository.dart';
import 'package:pars_gui/services/vault_repository.dart';

void main() {
  testWidgets('shows onboarding before entering the vault', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('enters the mobile shell after onboarding', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('vault searches entries and opens detail sheet', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'stripe');
    await tester.pumpAndSettle();

    expect(find.text('Stripe'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);

    await tester.tap(find.text('Stripe'));
    await tester.pumpAndSettle();

    expect(find.text('Copy password'), findsOneWidget);
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.text('Raw notes'), findsNothing);
  });

  testWidgets('manage tab exposes batch management workflows', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(find.text('Generate and save'), findsOneWidget);
    expect(find.text('Save existing password'), findsOneWidget);
    expect(find.text('Batch delete'), findsOneWidget);
    expect(find.text('Regenerate selected'), findsOneWidget);
  });

  testWidgets('settings tab exposes security keys stores and git sections', (
    tester,
  ) async {
    await tester.pumpWidget(const ParsGuiApp());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Gesture lock and biometrics'), findsOneWidget);
    expect(find.text('PGP keys'), findsOneWidget);
    expect(find.text('SSH keys'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Advanced git args'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('Advanced git args'), findsOneWidget);

    await tester.tap(find.text('Advanced git args'));
    await tester.pumpAndSettle();
    expect(find.text('git'), findsOneWidget);
    expect(find.text('Run selected command'), findsOneWidget);
  });

  testWidgets('accepts repository interfaces for app state', (tester) async {
    const repository = _InjectedRepository();

    await tester.pumpWidget(
      const ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Example Store'), findsWidgets);
    expect(find.text('Injected Entry'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();

    expect(find.text('Injected User <injected@example.com>'), findsOneWidget);
  });
}

class _InjectedRepository
    implements
        VaultRepository,
        SettingsRepository,
        KeyRepository,
        GitRepository {
  const _InjectedRepository();

  @override
  String get currentRepoName => 'Example Store';

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.needPull;

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[
    PasswordEntry(
      path: 'personal/injected',
      displayName: 'Injected Entry',
      repoName: 'Example Store',
      encryptedContent: 'secret',
    ),
  ];

  @override
  List<KeyRecord> get keys => const <KeyRecord>[
    KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Injected User <injected@example.com>',
      fingerprint: 'ABCD 1234',
      source: 'Injected test',
      hasPrivateKey: true,
    ),
  ];

  @override
  List<PasswordEntry> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return entries;
    }
    return entries
        .where((entry) => entry.path.toLowerCase().contains(normalized))
        .toList();
  }
}
