import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/git_repository.dart';
import 'package:pars_gui/services/key_repository.dart';
import 'package:pars_gui/services/pass_entry_parser.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/settings_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/services/vault_repository.dart';
import 'package:pars_gui/screens/manage/manage_screen.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/screens/vault/entry_detail_sheet.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';

void main() {
  testWidgets('shows onboarding before entering the vault', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.text('Draw at least 4 dots.'), findsOneWidget);
  });

  testWidgets('enters the mobile shell after onboarding', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    await _completeReadyOnboarding(tester);

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('onboarding captures gesture before key setup', (tester) async {
    const repository = _StoreSetupRepository();

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository(),
      ),
    );

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.text('Set up password store'), findsNothing);

    await _completeGestureSetup(tester);

    expect(find.text('Enable biometric unlock'), findsWidgets);

    await tester.tap(find.text('Skip biometrics'));
    await tester.pumpAndSettle();

    expect(find.text('Choose PGP key'), findsOneWidget);
    expect(find.text('Set up password store'), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('existing gesture resumes prerequisite key setup', (
    tester,
  ) async {
    const repository = _StoreSetupRepository();

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(const <int>[
          0,
          1,
          2,
          5,
        ], lastUnlockedAt: DateTime.now()),
      ),
    );

    expect(find.text('Choose PGP key'), findsOneWidget);
    expect(find.text('Set up password store'), findsNothing);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('onboarding prepares PGP and SSH before store setup', (
    tester,
  ) async {
    final repository = _OnboardingBranchRepository(storeReady: false);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          biometricUnlockEnabled: true,
          onboardingComplete: false,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );

    expect(find.text('Choose PGP key'), findsOneWidget);
    expect(find.text('Set up password store'), findsNothing);

    await tester.tap(find.text('Use PGP key'));
    await tester.pumpAndSettle();

    expect(find.text('Set up SSH for GitHub'), findsOneWidget);
    expect(find.text('Set up password store'), findsNothing);

    await tester.tap(find.text('Skip SSH'));
    await tester.pumpAndSettle();

    expect(find.text('Set up password store'), findsOneWidget);
    final cloneButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Clone Git store'),
    );
    expect(cloneButton.onPressed, isNull);
  });

  testWidgets('onboarding setup steps can return to the previous page', (
    tester,
  ) async {
    final repository = _OnboardingBranchRepository(storeReady: false);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          biometricUnlockEnabled: true,
          onboardingComplete: false,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );

    expect(find.text('Choose PGP key'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.text('Use PGP key'));
    await tester.pumpAndSettle();

    expect(find.text('Set up SSH for GitHub'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Choose PGP key'), findsOneWidget);
  });

  for (final branch in <_StoreBranch>[
    _StoreBranch.create,
    _StoreBranch.import,
    _StoreBranch.clone,
  ]) {
    testWidgets('onboarding completes ${branch.label} store branch', (
      tester,
    ) async {
      final repository = _OnboardingBranchRepository(storeReady: false);

      await tester.pumpWidget(
        ParsGuiApp(
          vaultRepository: repository,
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            onboardingComplete: false,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      );

      await tester.tap(find.text('Use PGP key'));
      await tester.pumpAndSettle();
      if (branch == _StoreBranch.clone) {
        await tester.tap(find.text('Generate SSH key'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'github-test');
        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.text('Skip SSH'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Set up password store'), findsOneWidget);

      switch (branch) {
        case _StoreBranch.create:
          await tester.tap(find.text('Create local store'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).at(1), '/tmp/pass');
          expect(find.text('PGP keys'), findsNothing);
          await tester.tap(find.widgetWithText(FilledButton, 'Create'));
          break;
        case _StoreBranch.import:
          await tester.tap(find.text('Import local store'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).last, '/tmp/imported');
          await tester.tap(find.widgetWithText(FilledButton, 'Import'));
          break;
        case _StoreBranch.clone:
          await tester.tap(find.text('Clone Git store'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).at(0),
            'git@example.com:org/pass.git',
          );
          await tester.enterText(find.byType(TextField).at(1), '/tmp/cloned');
          await tester.tap(find.widgetWithText(FilledButton, 'Clone'));
          break;
      }
      await tester.pumpAndSettle();

      expect(repository.storeActions.single, startsWith(branch.actionPrefix));
      if (branch == _StoreBranch.create) {
        expect(
          repository.storeActions.single,
          'create:Personal:/tmp/pass:ABCD 1234',
        );
      }
      expect(find.text('Review setup'), findsOneWidget);
    });
  }

  for (final branch in <_PgpBranch>[
    _PgpBranch.create,
    _PgpBranch.importPrivate,
  ]) {
    testWidgets('onboarding completes ${branch.label} PGP key branch', (
      tester,
    ) async {
      final repository = _OnboardingBranchRepository(
        initialKeys: const <KeyRecord>[],
      );

      await tester.pumpWidget(
        ParsGuiApp(
          vaultRepository: repository,
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
            onboardingComplete: false,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      );

      expect(find.text('Choose PGP key'), findsOneWidget);

      switch (branch) {
        case _PgpBranch.create:
          await tester.tap(find.text('Create PGP key'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).at(0), 'Alice');
          await tester.enterText(
            find.byType(TextField).at(1),
            'alice@example.com',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Create'));
          break;
        case _PgpBranch.importPrivate:
          await tester.tap(find.text('Import PGP key'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).last,
            '-----BEGIN PGP PRIVATE KEY BLOCK-----',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Import'));
          break;
      }
      await tester.pumpAndSettle();

      expect(repository.keyActions, contains(startsWith(branch.actionPrefix)));
      expect(repository.keyActions.last, startsWith('add-pgp:'));
      expect(find.text('Set up SSH for GitHub'), findsOneWidget);
    });
  }

  testWidgets(
    'onboarding key form shows inline errors above the action button',
    (tester) async {
      final repository = _FailingOnboardingRepository(
        error: Exception('PGP failed visibly'),
      );

      await tester.pumpWidget(
        ParsGuiApp(
          vaultRepository: repository,
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
            onboardingComplete: false,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      );

      await tester.tap(find.text('Create PGP key'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pump();

      final bottomSheet = find.byType(BottomSheet);
      final error = find.textContaining('PGP failed visibly');
      expect(find.descendant(of: bottomSheet, matching: error), findsOneWidget);
      final errorTop = tester.getTopLeft(error).dy;
      final buttonTop =
          tester.getTopLeft(find.widgetWithText(FilledButton, 'Create')).dy;
      expect(errorTop, lessThan(buttonTop));
    },
  );

  testWidgets('onboarding key form shows progress while generating keys', (
    tester,
  ) async {
    final repository = _SlowOnboardingRepository();

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          biometricUnlockEnabled: true,
          onboardingComplete: false,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );

    await tester.tap(find.text('Create PGP key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(repository.started, isTrue);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);

    repository.complete();
    await tester.pumpAndSettle();

    expect(find.text('Set up SSH for GitHub'), findsOneWidget);
  });

  for (final branch in <_SshBranch>[_SshBranch.generate, _SshBranch.import]) {
    testWidgets('onboarding completes ${branch.label} SSH key branch', (
      tester,
    ) async {
      final repository = _OnboardingBranchRepository();

      await tester.pumpWidget(
        ParsGuiApp(
          vaultRepository: repository,
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
            onboardingComplete: false,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      );

      await tester.tap(find.text('Use PGP key'));
      await tester.pumpAndSettle();
      expect(find.text('Set up SSH for GitHub'), findsOneWidget);

      switch (branch) {
        case _SshBranch.generate:
          await tester.tap(find.text('Generate SSH key'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).last, 'github-test');
          await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
          break;
        case _SshBranch.import:
          await tester.tap(find.text('Import SSH key'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).at(0), 'imported');
          await tester.enterText(
            find.byType(TextField).at(1),
            '-----BEGIN OPENSSH PRIVATE KEY-----',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Import'));
          break;
      }
      await tester.pumpAndSettle();

      expect(repository.keyActions, contains(startsWith(branch.actionPrefix)));
      expect(find.text('Review setup'), findsOneWidget);
    });
  }

  testWidgets('onboarding exposes GitHub SSH settings URL', (tester) async {
    final repository = _OnboardingBranchRepository();

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          biometricUnlockEnabled: true,
          onboardingComplete: false,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );

    await tester.tap(find.text('Use PGP key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub settings'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub SSH settings'), findsOneWidget);
    expect(find.text('https://github.com/settings/keys'), findsOneWidget);
  });

  testWidgets('settings reset returns to onboarding', (tester) async {
    final securityRepository = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      lastUnlockedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesture lock and biometrics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset onboarding'));
    await tester.pumpAndSettle();

    expect(securityRepository.onboardingComplete, isFalse);
    expect(find.text('Enable biometric unlock'), findsWidgets);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('vault searches entries and opens detail sheet', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeReadyOnboarding(tester);

    expect(find.text('GitHub'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'stripe');
    await tester.pumpAndSettle();

    expect(find.text('Stripe'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);

    await tester.tap(find.text('Stripe'));
    await tester.pumpAndSettle();

    expect(find.text('PGP passphrase required'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'test-passphrase');
    await tester.tap(find.text('Unlock entry'));
    await tester.pumpAndSettle();

    expect(find.text('Copy password'), findsOneWidget);
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.text('Raw notes'), findsNothing);
  });

  testWidgets('entry detail reads real secret and supports safe actions', (
    tester,
  ) async {
    final repository = _SecretActionRepository();
    final copiedTexts = <String>[];
    final openedUris = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryDetailSheet(
            entry: repository.entries.single,
            repository: repository,
            copyText: (text) async => copiedTexts.add(text),
            onOpenUri: (uri) async => openedUris.add(uri),
            clipboardClearDelay: Duration.zero,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(repository.readCount, 1);
    expect(find.text('loaded-secret'), findsNothing);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);

    await tester.tap(find.text('Copy password'));
    await tester.pumpAndSettle();

    expect(repository.copyCount, 1);
    expect(copiedTexts.last, 'loaded-secret');

    await tester.tap(find.text('QR code'));
    await tester.pumpAndSettle();

    expect(find.text('Password QR code'), findsOneWidget);
    await tester.tap(find.byTooltip('Close QR code'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Copy').first);
    await tester.pumpAndSettle();

    expect(copiedTexts.last, 'alice');

    await tester.tap(find.text('Open URL'));
    await tester.pumpAndSettle();

    expect(openedUris.single.toString(), 'https://example.com');
  });

  testWidgets('entry detail offers decrypt recovery actions and retry', (
    tester,
  ) async {
    final repository = _SecretActionRepository(failReads: true);
    var chooseKeyCount = 0;
    var openKeyManagementCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryDetailSheet(
            entry: repository.entries.single,
            repository: repository,
            onChooseKey: () => chooseKeyCount += 1,
            onOpenKeyManagement: () => openKeyManagementCount += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not decrypt entry'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Choose/import key'), findsOneWidget);
    expect(find.text('Open key management'), findsOneWidget);

    await tester.tap(find.text('Choose/import key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open key management'));
    await tester.pumpAndSettle();

    expect(chooseKeyCount, 1);
    expect(openKeyManagementCount, 1);

    repository.failReads = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.readCount, 2);
    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets(
    'entry detail prompts for PGP passphrase when session is locked',
    (tester) async {
      final repository = _SecretActionRepository();
      final securityRepository = InMemorySecurityRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntryDetailSheet(
              entry: repository.entries.single,
              repository: repository,
              securityRepository: securityRepository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PGP passphrase required'), findsOneWidget);
      expect(repository.readCount, 0);

      await tester.enterText(find.byType(TextField), 'session-passphrase');
      await tester.tap(find.text('Unlock entry'));
      await tester.pumpAndSettle();

      expect(securityRepository.hasActivePgpSession, isTrue);
      expect(
        await securityRepository.readActivePgpPassphrase(),
        'session-passphrase',
      );
      expect(repository.readCount, 1);
      expect(find.text('session-passphrase'), findsNothing);
    },
  );

  testWidgets('vault refresh loads bridge-backed entries and git status', (
    tester,
  ) async {
    final repository = _RefreshingVaultRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultScreen(
            vaultRepository: repository,
            gitRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.refreshCount, 1);
    expect(find.text('Bridge Entry'), findsOneWidget);
    expect(find.text('Need pull'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
    await tester.pumpAndSettle();

    expect(repository.refreshCount, 2);

    await tester.enterText(find.byType(TextField), 'bridge/path');
    await tester.pumpAndSettle();

    expect(find.text('Bridge Entry'), findsOneWidget);
  });

  testWidgets('vault browses directories and toggles favorites', (
    tester,
  ) async {
    final repository = _DirectoryVaultRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultScreen(
            vaultRepository: repository,
            gitRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BROWSE'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Work GitHub'), findsNothing);

    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();

    expect(find.text('BROWSE: WORK'), findsOneWidget);
    expect(find.text('Work GitHub'), findsOneWidget);

    await tester.tap(find.text('Work GitHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();

    expect(repository.favoritePaths, contains('work/github'));
    expect(find.text('Unfavorite'), findsOneWidget);
  });

  testWidgets('vault shows empty and retry states', (tester) async {
    final repository = _EmptyVaultRepository(failNextRefresh: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultScreen(
            vaultRepository: repository,
            gitRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load vault'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.refreshCount, 2);
    expect(find.text('No recent entries yet.'), findsOneWidget);
    expect(find.text('No entries in this store.'), findsOneWidget);
  });

  testWidgets('manage tab exposes batch management workflows', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeReadyOnboarding(tester);

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(find.text('Generate and save'), findsOneWidget);
    expect(find.text('Save existing password'), findsOneWidget);
    expect(find.text('Batch delete'), findsOneWidget);
    expect(find.text('Regenerate selected'), findsOneWidget);
  });

  testWidgets('manage generates and saves a new entry', (tester) async {
    final repository = _ManageVaultRepository();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManageScreen(repository: repository))),
    );

    await tester.tap(find.text('Generate and save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'work/new-entry');
    await tester.tap(find.text('Save generated password'));
    await tester.pumpAndSettle();

    expect(repository.generatedPaths, <String>['work/new-entry']);
    expect(find.text('Saved work/new-entry'), findsOneWidget);
  });

  testWidgets('manage saves an existing password', (tester) async {
    final repository = _ManageVaultRepository();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManageScreen(repository: repository))),
    );

    await tester.tap(find.text('Save existing password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'work/existing');
    await tester.enterText(find.byType(TextField).at(1), 'existing-secret');
    await tester.enterText(find.byType(TextField).at(2), 'username: alice');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(repository.savedPaths, <String>['work/existing']);
    expect(repository.savedContents.single, 'existing-secret\nusername: alice');
    expect(find.text('Saved work/existing'), findsOneWidget);
    expect(find.text('existing-secret'), findsNothing);
  });

  testWidgets('manage edits raw notes and replaces the first line', (
    tester,
  ) async {
    final repository = _ManageVaultRepository();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManageScreen(repository: repository))),
    );

    await tester.scrollUntilVisible(
      find.text('Edit entries'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Edit entries'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'rotated note');
    await tester.tap(find.text('Save edited entry'));
    await tester.pumpAndSettle();

    expect(repository.editedPaths, <String>['work/first']);
    expect(
      repository.editedContents.single,
      'old-secret\nusername: alice\nrotated note',
    );
    expect(find.text('Edited work/first (overwrote existing)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Edit entries'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Edit entries'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'new-secret');
    await tester.tap(find.text('Replace first line'));
    await tester.pumpAndSettle();

    expect(repository.replacedPaths, <String>['work/first']);
    expect(
      repository.replacedContents.single,
      'new-secret\nusername: alice\nraw note',
    );
  });

  testWidgets('manage moves renames and deletes single entries', (
    tester,
  ) async {
    final repository = _ManageVaultRepository();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManageScreen(repository: repository))),
    );

    await tester.scrollUntilVisible(
      find.text('Move entry'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Move entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'archive');
    await tester.tap(find.widgetWithText(FilledButton, 'Move entry'));
    await tester.pumpAndSettle();

    expect(repository.movedFrom, <String>['work/first']);
    expect(repository.movedTo, <String>['archive/first']);

    await tester.scrollUntilVisible(
      find.text('Rename entry'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Rename entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'work/renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename entry'));
    await tester.pumpAndSettle();

    expect(repository.movedFrom.last, 'work/first');
    expect(repository.movedTo.last, 'work/renamed');

    await tester.scrollUntilVisible(
      find.text('Delete entry'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();

    expect(find.text('Type full path to confirm.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'work/first');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();

    expect(repository.deletedPaths, <String>['work/first']);
  });

  testWidgets('manage batch operations use selected entries', (tester) async {
    final repository = _ManageVaultRepository();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManageScreen(repository: repository))),
    );

    await tester.scrollUntilVisible(
      find.text('First Entry'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('First Entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Entry'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Move selected'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'archive');
    await tester.tap(find.widgetWithText(FilledButton, 'Move selected'));
    await tester.pumpAndSettle();

    expect(repository.batchMoveDestinations, <String>['archive']);
    expect(repository.batchMovePaths.single, <String>[
      'work/first',
      'work/second',
    ]);

    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Rename selected'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Rename selected'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'old-');
    await tester.enterText(find.byType(TextField).at(1), '-2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename selected'));
    await tester.pumpAndSettle();

    expect(repository.batchRenamePrefixes, <String>['old-']);
    expect(repository.batchRenameSuffixes, <String>['-2026']);

    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Regenerate batch'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Regenerate batch'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Regenerate batch'));
    await tester.pumpAndSettle();

    expect(repository.batchRegeneratedPaths.single, <String>[
      'work/first',
      'work/second',
    ]);

    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Delete selected'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete selected'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DELETE');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete selected'));
    await tester.pumpAndSettle();

    expect(repository.batchDeletedPaths.single, <String>[
      'work/first',
      'work/second',
    ]);
  });

  testWidgets('manage shows conflict errors and optional commits', (
    tester,
  ) async {
    final repository = _ManageVaultRepository()..failNextWith = 'target exists';

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManageScreen(repository: repository))),
    );

    await tester.tap(find.text('Generate and save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'work/conflict');
    await tester.tap(find.text('Save generated password'));
    await tester.pumpAndSettle();

    expect(find.text('Exception: target exists'), findsOneWidget);

    await tester.tap(find.text('Commit after operation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save generated password'));
    await tester.pumpAndSettle();

    expect(repository.generatedPaths, <String>['work/conflict']);
    expect(repository.commitMessages, <String>[
      'Generate password work/conflict',
    ]);
    expect(find.text('Saved work/conflict and committed'), findsOneWidget);
  });

  testWidgets('settings tab exposes security keys stores and git sections', (
    tester,
  ) async {
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeReadyOnboarding(tester);

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
    expect(find.text('Runtime diagnostics'), findsOneWidget);

    await tester.tap(find.text('Advanced git args'));
    await tester.pumpAndSettle();
    expect(find.text('git'), findsOneWidget);
    expect(find.text('Run selected command'), findsOneWidget);
  });

  testWidgets('settings shows runtime diagnostics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            settingsRepository: const FakeParsRepository(),
            keyRepository: const FakeParsRepository(),
            gitRepository: const FakeParsRepository(),
            securityRepository: InMemorySecurityRepository(),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Runtime diagnostics'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Runtime diagnostics'));

    expect(find.text('Bridge loaded'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Core version'), findsOneWidget);
    expect(find.text('pars-core 0.2.5'), findsOneWidget);
    expect(find.text('PGP backend'), findsOneWidget);
    expect(find.text('Mock system GPG'), findsOneWidget);
    expect(find.text('Git backend'), findsOneWidget);
    expect(find.text('Mock git command'), findsOneWidget);
    expect(find.text('Key storage backend'), findsOneWidget);
    expect(find.text('In-memory test storage'), findsOneWidget);
  });

  testWidgets('settings shows empty key and store states', (tester) async {
    const repository = _StoreSetupRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            settingsRepository: repository,
            keyRepository: repository,
            gitRepository: repository,
            securityRepository: InMemorySecurityRepository(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();
    expect(find.text('No PGP keys'), findsOneWidget);
    Navigator.of(tester.element(find.text('No PGP keys'))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    expect(find.text('No password stores'), findsOneWidget);
  });

  testWidgets('settings runs git sync and remote operations', (tester) async {
    final repository = _GitSettingsRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            settingsRepository: repository,
            keyRepository: repository,
            gitRepository: repository,
            securityRepository: InMemorySecurityRepository(),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Git sync and remotes'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Git sync and remotes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    expect(repository.gitCalls, contains('pull'));
    expect(find.text('git pull'), findsOneWidget);
    expect(find.text('Already up to date.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Sync now');
    await tester.tap(find.text('Push after commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(repository.gitCalls, contains('commit Sync now'));
    expect(repository.gitCalls, contains('push'));
    expect(find.textContaining('git commit -m "Sync now"'), findsOneWidget);
    expect(find.textContaining('git push'), findsOneWidget);

    await tester.tap(find.text('List remotes'));
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
    expect(find.textContaining('git@example.com:org/pass.git'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(1), 'backup');
    await tester.enterText(
      find.byType(TextField).at(2),
      'git@example.com:backup/pass.git',
    );
    await tester.scrollUntilVisible(
      find.text('Add remote'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Add remote'));
    await tester.pumpAndSettle();

    expect(repository.gitCalls, contains('remote add backup'));
    expect(
      find.text('git remote add backup git@example.com:backup/pass.git'),
      findsOneWidget,
    );
  });

  testWidgets('settings advanced git args show failed output', (tester) async {
    final repository = _GitSettingsRepository(failAdvancedArgs: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            settingsRepository: repository,
            keyRepository: repository,
            gitRepository: repository,
            securityRepository: InMemorySecurityRepository(),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Advanced git args'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced git args'));
    await tester.pumpAndSettle();

    expect(find.text('git status'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'status --bad');
    await tester.pumpAndSettle();
    expect(find.text('git status --bad'), findsOneWidget);

    await tester.tap(find.text('Run selected command'));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Exit: 128'), findsOneWidget);
    expect(find.text('fatal: bad revision'), findsOneWidget);
  });

  testWidgets('accepts repository interfaces for app state', (tester) async {
    const repository = _InjectedRepository();

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository(),
      ),
    );
    await _completeReadyOnboarding(tester);

    expect(find.text('Example Store'), findsWidgets);
    expect(find.text('Injected Entry'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();

    expect(find.text('Injected User <injected@example.com>'), findsOneWidget);
  });

  testWidgets('locks and unlocks an existing app session', (tester) async {
    final securityRepository = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      autoLockTimeout: const Duration(seconds: 1),
      lastUnlockedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    expect(find.text('Vault'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);

    await _drawGesture(tester);
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
  });

  testWidgets('background lock clears active PGP session', (tester) async {
    final securityRepository = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      lockOnResume: true,
      activePgpPassphrase: 'pgp-passphrase',
      lastUnlockedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    expect(find.text('Vault'), findsWidgets);
    expect(securityRepository.hasActivePgpSession, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
    expect(securityRepository.hasActivePgpSession, isFalse);
  });

  testWidgets('entry detail clears parsed secret when closed', (tester) async {
    var secretCleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryDetailSheet(
            entry: const PasswordEntry(
              path: 'personal/test',
              displayName: 'Test Entry',
              repoName: 'Example Store',
              encryptedContent: 'super-secret\nusername: alice\nplain note',
            ),
            repository: const FakeParsRepository(),
            onSecretCleared: () => secretCleared = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reveal'));
    await tester.pumpAndSettle();

    expect(find.text('super-secret'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(secretCleared, isTrue);
    expect(find.text('super-secret'), findsNothing);
    expect(find.text('alice'), findsNothing);
  });

  testWidgets('settings updates local unlock controls', (tester) async {
    final securityRepository = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      lastUnlockedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesture lock and biometrics'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Require unlock on app resume'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();

    expect(securityRepository.lockOnResume, isTrue);
    expect(securityRepository.autoLockTimeout, const Duration(minutes: 5));
  });

  testWidgets('settings changes gesture lock pattern', (tester) async {
    final securityRepository = InMemorySecurityRepository.withPattern(
      const <int>[6, 3, 0, 1],
      lastUnlockedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesture lock and biometrics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change gesture'));
    await tester.pumpAndSettle();

    const newPattern = <int>[0, 1, 2, 5];
    await _drawGesture(tester, newPattern);
    await tester.pumpAndSettle();
    expect(
      find.text('Gesture captured. Confirm it once more.'),
      findsOneWidget,
    );
    await _drawGesture(tester, newPattern);
    await tester.pumpAndSettle();

    expect(
      await securityRepository.verifyGesture(const <int>[6, 3, 0, 1]),
      isFalse,
    );
    expect(await securityRepository.verifyGesture(newPattern), isTrue);
  });

  testWidgets('settings updates PGP session timeout', (tester) async {
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: _FakeBiometricAuthAdapter(),
    );
    await securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
    );
    await securityRepository.markUnlocked(DateTime.now());
    await securityRepository.setOnboardingComplete(true);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PGP session timeout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 hour'));
    await tester.pumpAndSettle();

    expect(
      securityRepository.pgpSessionExpiration,
      PgpSessionExpiration.oneHour,
    );
  });

  testWidgets('unlocks with biometrics when enabled', (tester) async {
    final biometrics = _FakeBiometricAuthAdapter(available: true);
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: biometrics,
    );
    await securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
    );
    await securityRepository.setBiometricUnlockEnabled(true);
    await securityRepository.savePgpPassphrase('pgp-passphrase');
    await securityRepository.setOnboardingComplete(true);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
    expect(find.text('Unlock with biometrics'), findsOneWidget);

    await tester.tap(find.text('Unlock with biometrics'));
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
    expect(securityRepository.hasActivePgpSession, isTrue);
    expect(
      await securityRepository.readActivePgpPassphrase(),
      'pgp-passphrase',
    );
    expect(biometrics.authenticateCount, 1);
  });

  testWidgets('settings enables biometric unlock when available', (
    tester,
  ) async {
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: _FakeBiometricAuthAdapter(available: true),
    );
    await securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
    );
    await securityRepository.markUnlocked(DateTime.now());
    await securityRepository.setOnboardingComplete(true);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesture lock and biometrics'));
    await tester.pumpAndSettle();

    expect(find.text('Available on this device'), findsOneWidget);
    await tester.tap(find.text('Biometric unlock'));
    await tester.pumpAndSettle();

    expect(securityRepository.biometricUnlockEnabled, isTrue);
  });

  testWidgets('settings stores and clears PGP passphrase cache', (
    tester,
  ) async {
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: _FakeBiometricAuthAdapter(),
    );
    await securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
    );
    await securityRepository.markUnlocked(DateTime.now());
    await securityRepository.setOnboardingComplete(true);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KMS / Keychain passphrase'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Store PGP passphrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pgp-passphrase');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(securityRepository.hasStoredPgpPassphrase, isTrue);
    expect(await securityRepository.readPgpPassphrase(), 'pgp-passphrase');
    expect(find.text('pgp-passphrase'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(securityRepository.hasStoredPgpPassphrase, isFalse);
    expect(await securityRepository.readPgpPassphrase(), isNull);
  });

  testWidgets('mobile shell fits a phone-sized viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeReadyOnboarding(tester);

    expect(find.text('Vault'), findsWidgets);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Runtime diagnostics'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Runtime diagnostics'), findsOneWidget);
  });
}

Future<void> _completeGestureSetup(WidgetTester tester) async {
  await _drawGesture(tester);
  await tester.pumpAndSettle();
  expect(find.text('Gesture captured. Confirm it once more.'), findsOneWidget);
  await _drawGesture(tester);
  await tester.pumpAndSettle();
}

Future<void> _completeReadyOnboarding(WidgetTester tester) async {
  await _completeGestureSetup(tester);
  for (var i = 0; i < 8; i += 1) {
    await tester.pumpAndSettle();
    if (find.text('Vault').evaluate().isNotEmpty) {
      return;
    }
    if (find.text('Skip biometrics').evaluate().isNotEmpty) {
      await _tapVisible(tester, find.text('Skip biometrics'));
      continue;
    }
    if (find.text('Continue').evaluate().isNotEmpty) {
      await _tapVisible(tester, find.text('Continue').first);
      continue;
    }
    if (find.text('Use PGP key').evaluate().isNotEmpty) {
      await _tapVisible(tester, find.text('Use PGP key').first);
      continue;
    }
    if (find.text('Skip SSH').evaluate().isNotEmpty) {
      await _tapVisible(tester, find.text('Skip SSH'));
      continue;
    }
    if (find.text('Finish setup').evaluate().isNotEmpty) {
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Finish setup'),
      );
      continue;
    }
  }
  fail('Onboarding did not reach the vault.');
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _drawGesture(
  WidgetTester tester, [
  List<int> pattern = const <int>[0, 1, 2, 5],
]) async {
  final box = tester.renderObject<RenderBox>(find.byType(GestureLockInput));
  final topLeft = box.localToGlobal(Offset.zero);
  final cell = box.size.width / 3;
  Offset dot(int index) =>
      topLeft +
      Offset(cell * (index % 3) + cell / 2, cell * (index ~/ 3) + cell / 2);

  final gesture = await tester.createGesture();
  await gesture.down(dot(pattern.first));
  await tester.pump();
  await gesture.moveTo(dot(pattern.first) + Offset(cell / 4, 0));
  await tester.pump();
  for (final index in pattern.skip(1)) {
    await gesture.moveTo(dot(index));
    await tester.pump();
  }
  await gesture.up();
}

class _FakeSecureStorageAdapter implements SecureStorageAdapter {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FakeBiometricAuthAdapter implements BiometricAuthAdapter {
  _FakeBiometricAuthAdapter({this.available = false});

  final bool available;
  int authenticateCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    authenticateCount += 1;
    return true;
  }
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
  StoreLifecycleSnapshot get lifecycle => const StoreLifecycleSnapshot(
    configPath: '/tmp/example-config.toml',
    configExists: true,
    selectedStoreId: 'example-store',
    selectedStoreRoot: '/tmp/example-store',
    onboardingState: StoreOnboardingState.ready,
    issues: <String>[],
    stores: <StoreStatus>[
      StoreStatus(
        id: 'example-store',
        name: 'Example Store',
        root: '/tmp/example-store',
        isDefault: true,
        exists: true,
        hasGpgId: true,
        hasGitRemote: true,
        pgpKeyMissing: false,
        issues: <String>[],
      ),
    ],
  );

  @override
  List<StoreStatus> get stores => lifecycle.stores;

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
  Future<void> refresh() async {}

  @override
  Future<void> selectStore(String root) async {}

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool setDefault,
    required bool initializeGit,
  }) async {}

  @override
  Future<void> importLocalStore({
    required String root,
    required bool setDefault,
  }) async {}

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    required bool setDefault,
  }) async {}

  @override
  Future<void> removeStore({required String root}) async {}

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {}

  @override
  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  }) async => keys.first;

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async =>
      keys.first;

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async =>
      keys.first;

  @override
  Future<KeyRecord> importPgpPrivateKeyFile(String path) async => keys.first;

  @override
  Future<String> exportPgpPublicKey(String fingerprint) async => 'public';

  @override
  Future<String> exportPgpPrivateKey({
    required String fingerprint,
    required String confirmation,
  }) async => 'private';

  @override
  Future<void> addPgpKeyToSelectedStore(String fingerprint) async {}

  @override
  Future<KeyRecord> generateSshKey(String name) async => const KeyRecord(
    type: KeyRecordType.ssh,
    name: 'Injected SSH',
    fingerprint: 'SHA256:injected',
    source: 'Injected test',
    hasPrivateKey: true,
  );

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) async => generateSshKey(name);

  @override
  Future<KeyRecord> importSshPrivateKeyFile({
    required String name,
    required String path,
  }) async => generateSshKey(name);

  @override
  Future<String> exportSshPublicKey(String name) async =>
      'ssh-ed25519 injected';

  @override
  Future<String> exportSshPrivateKey({
    required String name,
    required String confirmation,
  }) async => 'private';

  @override
  Future<Uri> githubSshSettingsUri() async =>
      Uri.parse('https://github.com/settings/keys');

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

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) {
    return entries
        .where(
          (entry) => entry.parentPath == (directoryPath ?? currentRepoName),
        )
        .toList(growable: false);
  }

  @override
  List<PasswordEntry> recentEntries() => entries;

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    return SecretContent(
      password: entry.encryptedContent,
      fields: const <ParsedSecretField>[],
      rawNotes: '',
    );
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async =>
      entry.encryptedContent;

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {}

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);
}

enum _StoreBranch {
  create('create', 'create:'),
  import('import', 'import:'),
  clone('clone', 'clone:');

  const _StoreBranch(this.label, this.actionPrefix);

  final String label;
  final String actionPrefix;
}

enum _PgpBranch {
  create('create', 'generate-pgp:'),
  importPrivate('import private', 'import-pgp-private:');

  const _PgpBranch(this.label, this.actionPrefix);

  final String label;
  final String actionPrefix;
}

enum _SshBranch {
  generate('generate', 'generate-ssh:'),
  import('import', 'import-ssh:');

  const _SshBranch(this.label, this.actionPrefix);

  final String label;
  final String actionPrefix;
}

class _OnboardingBranchRepository extends _InjectedRepository {
  _OnboardingBranchRepository({
    this.storeReady = true,
    List<KeyRecord>? initialKeys,
  }) : _keys = List<KeyRecord>.of(
         initialKeys ??
             const <KeyRecord>[
               KeyRecord(
                 type: KeyRecordType.pgp,
                 name: 'Onboarding User <onboarding@example.com>',
                 fingerprint: 'ABCD 1234',
                 source: 'Onboarding test',
                 hasPrivateKey: true,
               ),
             ],
       );

  bool storeReady;
  final List<KeyRecord> _keys;
  final List<String> storeActions = <String>[];
  final List<String> keyActions = <String>[];

  @override
  String get currentRepoName =>
      storeReady ? 'Onboarding Store' : 'No store selected';

  @override
  StoreLifecycleSnapshot get lifecycle {
    if (!storeReady) {
      return const StoreLifecycleSnapshot(
        configPath: '/tmp/pars_config.toml',
        configExists: false,
        onboardingState: StoreOnboardingState.noConfig,
        issues: <String>['no_config'],
        stores: <StoreStatus>[],
      );
    }
    const store = StoreStatus(
      id: 'onboarding-store',
      name: 'Onboarding Store',
      root: '/tmp/pass',
      isDefault: true,
      exists: true,
      hasGpgId: true,
      hasGitRemote: true,
      pgpKeyMissing: false,
      issues: <String>[],
    );
    return const StoreLifecycleSnapshot(
      configPath: '/tmp/pars_config.toml',
      configExists: true,
      selectedStoreId: 'onboarding-store',
      selectedStoreRoot: '/tmp/pass',
      onboardingState: StoreOnboardingState.ready,
      issues: <String>[],
      stores: <StoreStatus>[store],
    );
  }

  @override
  List<StoreStatus> get stores => lifecycle.stores;

  @override
  List<KeyRecord> get keys => List<KeyRecord>.unmodifiable(_keys);

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool setDefault,
    required bool initializeGit,
  }) async {
    storeActions.add('create:$name:$root:${pgpKeys.join(',')}');
    storeReady = true;
  }

  @override
  Future<void> importLocalStore({
    required String root,
    required bool setDefault,
  }) async {
    storeActions.add('import:$root');
    storeReady = true;
  }

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    required bool setDefault,
  }) async {
    storeActions.add('clone:$remoteUrl:$root');
    storeReady = true;
  }

  @override
  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  }) async {
    keyActions.add('generate-pgp:$name:$email:${passphrase != null}');
    final key = KeyRecord(
      type: KeyRecordType.pgp,
      name: '$name <$email>',
      fingerprint: 'GENERATED PGP',
      source: 'Generated during onboarding',
      hasPrivateKey: true,
    );
    _keys.add(key);
    return key;
  }

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async {
    keyActions.add('import-pgp-public:$armoredText');
    final key = const KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Imported Public PGP',
      fingerprint: 'IMPORTED PUBLIC PGP',
      source: 'Imported during onboarding',
      hasPrivateKey: false,
    );
    _keys.add(key);
    return key;
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async {
    keyActions.add('import-pgp-private:$armoredText');
    final key = const KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Imported Private PGP',
      fingerprint: 'IMPORTED PRIVATE PGP',
      source: 'Imported during onboarding',
      hasPrivateKey: true,
    );
    _keys.add(key);
    return key;
  }

  @override
  Future<void> addPgpKeyToSelectedStore(String fingerprint) async {
    keyActions.add('add-pgp:$fingerprint');
  }

  @override
  Future<KeyRecord> generateSshKey(String name) async {
    keyActions.add('generate-ssh:$name');
    final key = KeyRecord(
      type: KeyRecordType.ssh,
      name: name,
      fingerprint: 'SHA256:generated',
      source: 'Generated during onboarding',
      hasPrivateKey: true,
    );
    _keys.add(key);
    return key;
  }

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) async {
    keyActions.add('import-ssh:$name:$privateKey');
    final key = KeyRecord(
      type: KeyRecordType.ssh,
      name: name,
      fingerprint: 'SHA256:imported',
      source: 'Imported during onboarding',
      hasPrivateKey: true,
    );
    _keys.add(key);
    return key;
  }
}

class _FailingOnboardingRepository extends _OnboardingBranchRepository {
  _FailingOnboardingRepository({required this.error})
    : super(initialKeys: const <KeyRecord>[]);

  final Object error;

  @override
  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  }) async {
    throw error;
  }
}

class _SlowOnboardingRepository extends _OnboardingBranchRepository {
  _SlowOnboardingRepository() : super(initialKeys: const <KeyRecord>[]);

  final Completer<KeyRecord> _completer = Completer<KeyRecord>();
  bool started = false;

  @override
  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  }) {
    started = true;
    keyActions.add('generate-pgp:$name:$email:${passphrase != null}');
    return _completer.future;
  }

  void complete() {
    final key = const KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Generated Slow PGP',
      fingerprint: 'SLOW PGP',
      source: 'Generated during onboarding',
      hasPrivateKey: true,
    );
    _keys.add(key);
    _completer.complete(key);
  }
}

class _GitSettingsRepository extends _InjectedRepository
    implements GitOperationsRepository {
  _GitSettingsRepository({this.failAdvancedArgs = false});

  final bool failAdvancedArgs;
  final List<String> gitCalls = <String>[];

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.uncommitted;

  @override
  Future<GitOperationResult> refreshGitStatus() async {
    gitCalls.add('status');
    return const GitOperationResult(
      command: 'git status --short --branch',
      stdout: '## main\n M work/first.gpg\n',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> pull() async {
    gitCalls.add('pull');
    return const GitOperationResult(
      command: 'git pull',
      stdout: 'Already up to date.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> push() async {
    gitCalls.add('push');
    return const GitOperationResult(
      command: 'git push',
      stdout: 'Pushed.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> commit(String message) async {
    gitCalls.add('commit $message');
    return GitOperationResult(
      command: 'git commit -m "$message"',
      stdout: 'Committed.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> runArgs(List<String> args) async {
    final joined = args.join(' ');
    gitCalls.add(joined);
    if (failAdvancedArgs) {
      return GitOperationResult(
        command: 'git $joined',
        stdout: '',
        stderr: 'fatal: bad revision',
        exitCode: 128,
        success: false,
      );
    }
    return GitOperationResult(
      command: 'git $joined',
      stdout:
          joined == 'remote -v'
              ? 'origin\tgit@example.com:org/pass.git (fetch)\norigin\tgit@example.com:org/pass.git (push)\n'
              : 'ok',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<List<GitRemote>> listRemotes() async {
    gitCalls.add('remote -v');
    return const <GitRemote>[
      GitRemote(
        name: 'origin',
        fetchUrl: 'git@example.com:org/pass.git',
        pushUrl: 'git@example.com:org/pass.git',
      ),
    ];
  }

  @override
  Future<GitOperationResult> addRemote({
    required String name,
    required String url,
  }) async {
    gitCalls.add('remote add $name');
    return GitOperationResult(
      command: 'git remote add $name $url',
      stdout: '',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> editRemote({
    required String name,
    required String url,
  }) async {
    gitCalls.add('remote set-url $name');
    return GitOperationResult(
      command: 'git remote set-url $name $url',
      stdout: '',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> removeRemote(String name) async {
    gitCalls.add('remote remove $name');
    return GitOperationResult(
      command: 'git remote remove $name',
      stdout: '',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> autoPullOnOpen() => pull();

  @override
  Future<GitOperationResult> recoverByPull() => pull();

  @override
  Future<GitOperationResult> deleteLocalRepo({
    required String confirmation,
  }) async {
    gitCalls.add('delete local repo');
    return const GitOperationResult(
      command: 'delete local repo',
      stdout: 'Deleted local repository.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }
}

class _EmptyVaultRepository implements VaultRepository, GitRepository {
  _EmptyVaultRepository({this.failNextRefresh = false});

  bool failNextRefresh;
  int refreshCount = 0;

  @override
  String get currentRepoName => 'Empty Store';

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.clean;

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[];

  @override
  Future<void> refresh() async {
    refreshCount += 1;
    if (failNextRefresh) {
      failNextRefresh = false;
      throw Exception('offline');
    }
  }

  @override
  List<PasswordEntry> search(String query) => entries;

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) => entries;

  @override
  List<PasswordEntry> recentEntries() => entries;

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async =>
      throw UnimplementedError();

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async =>
      throw UnimplementedError();

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {}

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async => throw UnimplementedError();

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async => throw UnimplementedError();
}

class _RefreshingVaultRepository implements VaultRepository, GitRepository {
  var refreshCount = 0;
  List<PasswordEntry> _entries = const <PasswordEntry>[];
  RepoGitStatus _gitStatus = RepoGitStatus.syncFailed;

  @override
  String get currentRepoName => 'Bridge Store';

  @override
  RepoGitStatus get gitStatus => _gitStatus;

  @override
  List<PasswordEntry> get entries => _entries;

  @override
  Future<void> refresh() async {
    refreshCount += 1;
    _gitStatus = RepoGitStatus.needPull;
    _entries = const <PasswordEntry>[
      PasswordEntry(
        path: 'bridge/path',
        displayName: 'Bridge Entry',
        repoName: 'Bridge Store',
        encryptedContent: 'bridge-secret',
      ),
    ];
  }

  @override
  List<PasswordEntry> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) =>
              entry.displayName.toLowerCase().contains(normalized) ||
              entry.path.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) {
    return entries
        .where(
          (entry) => entry.parentPath == (directoryPath ?? currentRepoName),
        )
        .toList(growable: false);
  }

  @override
  List<PasswordEntry> recentEntries() => entries;

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    return SecretContent(
      password: entry.encryptedContent,
      fields: const <ParsedSecretField>[],
      rawNotes: '',
    );
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async =>
      entry.encryptedContent;

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {}

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);
}

class _SecretActionRepository implements VaultRepository {
  _SecretActionRepository({this.failReads = false});

  bool failReads;
  var readCount = 0;
  var copyCount = 0;

  @override
  String get currentRepoName => 'Secret Store';

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[
    PasswordEntry(
      path: 'work/example',
      displayName: 'Example',
      repoName: 'Secret Store',
      encryptedContent: '',
    ),
  ];

  @override
  Future<void> refresh() async {}

  @override
  List<PasswordEntry> search(String query) => entries;

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) => entries;

  @override
  List<PasswordEntry> recentEntries() => entries;

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    readCount += 1;
    if (failReads) {
      throw Exception('missing private key');
    }
    return const SecretContent(
      password: 'loaded-secret',
      fields: <ParsedSecretField>[
        ParsedSecretField(key: 'username', label: 'Username', value: 'alice'),
        ParsedSecretField(
          key: 'url',
          label: 'URL',
          value: 'https://example.com',
        ),
      ],
      rawNotes: '',
    );
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async {
    copyCount += 1;
    return 'loaded-secret';
  }

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {}

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);
}

class _DirectoryVaultRepository implements VaultRepository, GitRepository {
  final Set<String> favoritePaths = <String>{};

  @override
  String get currentRepoName => 'Directory Store';

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.clean;

  @override
  List<PasswordEntry> get entries => <PasswordEntry>[
    PasswordEntry(
      path: 'work',
      displayName: 'work',
      repoName: currentRepoName,
      encryptedContent: '',
      isDirectory: true,
      childCount: 1,
    ),
    PasswordEntry(
      path: 'work/github',
      displayName: 'Work GitHub',
      repoName: currentRepoName,
      encryptedContent: 'loaded-secret',
      isFavorite: favoritePaths.contains('work/github'),
    ),
  ];

  @override
  Future<void> refresh() async {}

  @override
  List<PasswordEntry> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return entries;
    }
    return entries
        .where((entry) => entry.path.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) {
    return entries
        .where(
          (entry) => entry.parentPath == (directoryPath ?? currentRepoName),
        )
        .toList(growable: false);
  }

  @override
  List<PasswordEntry> recentEntries() => const <PasswordEntry>[];

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    return const SecretContent(
      password: 'loaded-secret',
      fields: <ParsedSecretField>[],
      rawNotes: '',
    );
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async =>
      'loaded-secret';

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {
    if (!favoritePaths.add(entry.path)) {
      favoritePaths.remove(entry.path);
    }
  }

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async => EntryOperationResult(path: path, overwroteExisting: false);
}

class _ManageVaultRepository implements ManageRepository {
  final List<String> generatedPaths = <String>[];
  final List<String> savedPaths = <String>[];
  final List<String> savedContents = <String>[];
  final List<String> editedPaths = <String>[];
  final List<String> editedContents = <String>[];
  final List<String> replacedPaths = <String>[];
  final List<String> replacedContents = <String>[];
  final List<String> movedFrom = <String>[];
  final List<String> movedTo = <String>[];
  final List<String> deletedPaths = <String>[];
  final List<List<String>> batchMovePaths = <List<String>>[];
  final List<String> batchMoveDestinations = <String>[];
  final List<String> batchRenamePrefixes = <String>[];
  final List<String> batchRenameSuffixes = <String>[];
  final List<List<String>> batchDeletedPaths = <List<String>>[];
  final List<List<String>> batchRegeneratedPaths = <List<String>>[];
  final List<String> commitMessages = <String>[];
  String? failNextWith;

  @override
  String get currentRepoName => 'Manage Store';

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[
    PasswordEntry(
      path: 'work/first',
      displayName: 'First Entry',
      repoName: 'Manage Store',
      encryptedContent: 'old-secret\nusername: alice\nraw note',
    ),
    PasswordEntry(
      path: 'work/second',
      displayName: 'Second Entry',
      repoName: 'Manage Store',
      encryptedContent: 'second-secret\nusername: bob\nsecond note',
    ),
  ];

  @override
  Future<void> refresh() async {}

  @override
  List<PasswordEntry> search(String query) => entries;

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) => entries;

  @override
  List<PasswordEntry> recentEntries() => entries;

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async =>
      PassEntryParser.parse(entry.encryptedContent);

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async =>
      throw UnimplementedError();

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {}

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async {
    _maybeFail();
    generatedPaths.add(path);
    return EntryOperationResult(path: path, overwroteExisting: false);
  }

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async {
    _maybeFail();
    savedPaths.add(path);
    savedContents.add(content);
    return EntryOperationResult(path: path, overwroteExisting: false);
  }

  @override
  Future<EntryOperationResult> editEntry({
    required String path,
    required String content,
  }) async {
    _maybeFail();
    editedPaths.add(path);
    editedContents.add(content);
    return EntryOperationResult(
      path: path,
      overwroteExisting: true,
      action: 'Edited',
    );
  }

  @override
  Future<EntryOperationResult> replaceEntryPassword({
    required PasswordEntry entry,
    required String password,
  }) async {
    _maybeFail();
    final secret = await readEntry(entry);
    final content = _secretContent(password, secret.fields, secret.rawNotes);
    replacedPaths.add(entry.path);
    replacedContents.add(content);
    return EntryOperationResult(
      path: entry.path,
      overwroteExisting: true,
      action: 'Replaced password for',
    );
  }

  @override
  Future<EntryOperationResult> moveEntry({
    required String fromPath,
    required String toPath,
    required bool overwrite,
  }) async {
    _maybeFail();
    movedFrom.add(fromPath);
    movedTo.add(toPath);
    return EntryOperationResult(
      path: toPath,
      overwroteExisting: overwrite,
      action: 'Moved',
    );
  }

  @override
  Future<EntryOperationResult> deleteEntry({
    required String path,
    required bool recursive,
  }) async {
    _maybeFail();
    deletedPaths.add(path);
    return EntryOperationResult(
      path: path,
      overwroteExisting: false,
      action: 'Deleted',
    );
  }

  @override
  Future<BatchOperationResult> batchMoveEntries({
    required List<PasswordEntry> entries,
    required String destinationDirectory,
    required bool overwrite,
  }) async {
    _maybeFail();
    final paths = entries.map((entry) => entry.path).toList(growable: false);
    batchMovePaths.add(paths);
    batchMoveDestinations.add(destinationDirectory);
    return BatchOperationResult(action: 'Moved', affectedPaths: paths);
  }

  @override
  Future<BatchOperationResult> batchRenameEntries({
    required List<PasswordEntry> entries,
    required String prefix,
    required String suffix,
    required bool overwrite,
  }) async {
    _maybeFail();
    final paths = entries.map((entry) => entry.path).toList(growable: false);
    batchRenamePrefixes.add(prefix);
    batchRenameSuffixes.add(suffix);
    return BatchOperationResult(action: 'Renamed', affectedPaths: paths);
  }

  @override
  Future<BatchOperationResult> batchDeleteEntries({
    required List<PasswordEntry> entries,
  }) async {
    _maybeFail();
    final paths = entries.map((entry) => entry.path).toList(growable: false);
    batchDeletedPaths.add(paths);
    return BatchOperationResult(action: 'Deleted', affectedPaths: paths);
  }

  @override
  Future<BatchOperationResult> batchRegenerateEntries({
    required List<PasswordEntry> entries,
    required int length,
    required bool noSymbols,
  }) async {
    _maybeFail();
    final paths = entries.map((entry) => entry.path).toList(growable: false);
    batchRegeneratedPaths.add(paths);
    return BatchOperationResult(action: 'Regenerated', affectedPaths: paths);
  }

  @override
  Future<GitOperationResult> commitChanges(String message) async {
    _maybeFail();
    commitMessages.add(message);
    return GitOperationResult(
      command: 'git commit -m "$message"',
      stdout: 'Committed',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  void _maybeFail() {
    final message = failNextWith;
    if (message == null) {
      return;
    }
    failNextWith = null;
    throw Exception(message);
  }

  String _secretContent(
    String password,
    List<ParsedSecretField> fields,
    String rawNotes,
  ) {
    final lines = <String>[password];
    for (final field in fields) {
      lines.add('${field.key}: ${field.value}');
    }
    final notes = rawNotes.trim();
    if (notes.isNotEmpty) {
      lines.add(notes);
    }
    return lines.join('\n');
  }
}

class _StoreSetupRepository
    implements
        VaultRepository,
        SettingsRepository,
        KeyRepository,
        GitRepository {
  const _StoreSetupRepository();

  @override
  String get currentRepoName => 'No store selected';

  @override
  StoreLifecycleSnapshot get lifecycle => const StoreLifecycleSnapshot(
    configPath: '/tmp/pars_config.toml',
    configExists: false,
    onboardingState: StoreOnboardingState.noConfig,
    issues: <String>['no_config'],
    stores: <StoreStatus>[],
  );

  @override
  List<StoreStatus> get stores => lifecycle.stores;

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.syncFailed;

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[];

  @override
  List<KeyRecord> get keys => const <KeyRecord>[];

  @override
  Future<void> refresh() async {}

  @override
  List<PasswordEntry> search(String query) => entries;

  @override
  List<PasswordEntry> browseEntries(String? directoryPath) => entries;

  @override
  List<PasswordEntry> recentEntries() => entries;

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async =>
      throw UnimplementedError();

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async =>
      throw UnimplementedError();

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {}

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async => throw UnimplementedError();

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async => throw UnimplementedError();

  @override
  Future<void> selectStore(String root) async {}

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool setDefault,
    required bool initializeGit,
  }) async {}

  @override
  Future<void> importLocalStore({
    required String root,
    required bool setDefault,
  }) async {}

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    required bool setDefault,
  }) async {}

  @override
  Future<void> removeStore({required String root}) async {}

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {}

  @override
  Future<KeyRecord> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
  }) async => throw UnimplementedError();

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async =>
      throw UnimplementedError();

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async =>
      throw UnimplementedError();

  @override
  Future<KeyRecord> importPgpPrivateKeyFile(String path) async =>
      throw UnimplementedError();

  @override
  Future<String> exportPgpPublicKey(String fingerprint) async =>
      throw UnimplementedError();

  @override
  Future<String> exportPgpPrivateKey({
    required String fingerprint,
    required String confirmation,
  }) async => throw UnimplementedError();

  @override
  Future<void> addPgpKeyToSelectedStore(String fingerprint) async {}

  @override
  Future<KeyRecord> generateSshKey(String name) async =>
      throw UnimplementedError();

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) async => throw UnimplementedError();

  @override
  Future<KeyRecord> importSshPrivateKeyFile({
    required String name,
    required String path,
  }) async => throw UnimplementedError();

  @override
  Future<String> exportSshPublicKey(String name) async =>
      throw UnimplementedError();

  @override
  Future<String> exportSshPrivateKey({
    required String name,
    required String confirmation,
  }) async => throw UnimplementedError();

  @override
  Future<Uri> githubSshSettingsUri() async => throw UnimplementedError();
}
