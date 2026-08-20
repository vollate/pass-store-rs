import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/screens/onboarding/onboarding_screen.dart';
import 'package:pars_gui/screens/security/lock_screen.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/screens/shell/shell_view_state.dart';
import 'package:pars_gui/screens/vault/entry_detail_sheet.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';

import 'support/gui_test_harness.dart';

void main() {
  const repository = FakeParsRepository();

  testWidgets('Vault compact English light visual baseline', (tester) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_compact_en_light.png'),
    );
  });

  testWidgets('Vault selection compact English visual baseline', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final state = VaultDestinationState()..enterSelection('work/dev/github');
    addTearDown(state.dispose);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
          viewState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_selection_compact_en_light.png'),
    );
  });

  testWidgets('Vault search compact Chinese dark visual baseline', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final state = VaultDestinationState()..setQuery('stripe');
    addTearDown(state.dispose);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
        brightness: Brightness.dark,
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
          viewState: state,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_search_compact_zh_dark.png'),
    );
  });

  testWidgets('entry detail compact English dark visual baseline', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final entry = repository.entries.firstWhere((entry) => !entry.isDirectory);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        brightness: Brightness.dark,
        child: EntryDetailSheet(entry: entry, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/entry_detail_compact_en_dark.png'),
    );
  });

  testWidgets('entry detail error compact English visual baseline', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final failing = _FailingVisualRepository();
    final entry = failing.entries.firstWhere((entry) => !entry.isDirectory);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: EntryDetailSheet(entry: entry, repository: failing),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/entry_detail_error_compact_en_light.png'),
    );
  });

  testWidgets('entry detail loading compact English visual baseline', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final loading = _LoadingVisualRepository();
    final entry = loading.entries.firstWhere((entry) => !entry.isDirectory);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: EntryDetailSheet(entry: entry, repository: loading),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/entry_detail_loading_compact_en_light.png'),
    );
    loading.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Settings compact Chinese light visual baseline', (tester) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
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

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_compact_zh_light.png'),
    );
  });

  testWidgets('Settings expanded English dark visual baseline', (tester) async {
    await configureGuiTestViewport(tester, viewport: GuiTestViewport.expanded);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        brightness: Brightness.dark,
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

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_expanded_en_dark.png'),
    );
  });

  testWidgets('onboarding compact Chinese visual baseline', (tester) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/onboarding_compact_zh_light.png'),
    );
  });

  testWidgets('lock compact Chinese dark visual baseline', (tester) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
        brightness: Brightness.dark,
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

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lock_compact_zh_dark.png'),
    );
  });
}

class _FailingVisualRepository extends FakeParsRepository {
  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    throw StateError('visual failure');
  }
}

class _LoadingVisualRepository extends FakeParsRepository {
  final Completer<SecretContent> _completer = Completer<SecretContent>();

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(
        const SecretContent(
          password: 'loaded',
          fields: <ParsedSecretField>[],
          rawNotes: '',
        ),
      );
    }
  }
}
