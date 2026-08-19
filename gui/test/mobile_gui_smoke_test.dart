import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/app/pars_theme.dart';
import 'package:pars_gui/l10n/app_localizations.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/models/pgp_key_import.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/git_repository.dart';
import 'package:pars_gui/services/key_repository.dart';
import 'package:pars_gui/services/pass_entry_parser.dart';
import 'package:pars_gui/services/path_picker_service.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/settings_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/services/vault_repository.dart';
import 'package:pars_gui/screens/manage/manage_screen.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/screens/vault/entry_detail_sheet.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';
import 'package:pars_gui/widgets/pgp_key_import_body.dart';

const _testPgpFingerprint = '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF';
const _publicKeyInspection = PgpKeyInspection(
  kind: PgpKeyKind.public,
  fingerprint: _testPgpFingerprint,
  identity: 'Vollate <me@example.com>',
  hasPrivateKey: false,
  requiresPassphrase: false,
  armored: true,
);
const _testPgpKey = KeyRecord(
  type: KeyRecordType.pgp,
  name: 'Vollate <me@example.com>',
  fingerprint: _testPgpFingerprint,
  source: 'Generated on device',
  hasPrivateKey: true,
);
const _settingsPrimaryPgpKey = KeyRecord(
  type: KeyRecordType.pgp,
  name: 'Primary User <primary@example.com>',
  fingerprint: 'PGP-PRIMARY',
  source: 'Generated on device',
  hasPrivateKey: true,
);
const _settingsPrimaryPgpUsername = 'Primary User';
const _settingsBackupPgpKey = KeyRecord(
  type: KeyRecordType.pgp,
  name: 'Backup User <backup@example.com>',
  fingerprint: 'PGP-BACKUP',
  source: 'Imported from text',
  hasPrivateKey: true,
);
const _settingsSshKey = KeyRecord(
  type: KeyRecordType.ssh,
  name: 'github-mobile',
  fingerprint: 'SHA256:github-mobile',
  source: 'Generated on device',
  hasPrivateKey: true,
);
const _settingsStoreKeyReference = KeyRecord(
  type: KeyRecordType.pgp,
  name: 'alice@example.com',
  fingerprint: 'alice@example.com',
  source: '.gpg-id',
  hasPrivateKey: false,
  hasLocalKeyMaterial: false,
  referencedByStores: <String>['Imported Store'],
);

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

  testWidgets('store diagnostics do not reopen completed onboarding', (
    tester,
  ) async {
    final repository = _ManagedPathDiagnosticRepository(storeReady: true);

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          onboardingComplete: true,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Set up password store'), findsNothing);
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

  testWidgets('onboarding system back returns to the previous setup step', (
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

    await tester.tap(find.text('Use PGP key'));
    await tester.pumpAndSettle();

    expect(find.text('Set up SSH for GitHub'), findsOneWidget);

    expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Choose PGP key'), findsOneWidget);
    expect(find.text('Set up SSH for GitHub'), findsNothing);
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
      final pathPicker = _FakePathPickerService(
        folderResults: <String?>[
          switch (branch) {
            _StoreBranch.create => '/tmp',
            _StoreBranch.import => '/tmp/imported',
            _StoreBranch.clone => '/tmp',
          },
        ],
      );

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
          pathPickerService: pathPicker,
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
          await tester.tap(find.widgetWithText(TextButton, 'Choose'));
          await tester.pumpAndSettle();
          expect(find.text('PGP keys'), findsNothing);
          await tester.tap(find.widgetWithText(FilledButton, 'Create').last);
          break;
        case _StoreBranch.import:
          await tester.tap(find.text('Import local store'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Choose'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
          break;
        case _StoreBranch.clone:
          await tester.tap(find.text('Clone Git store'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).at(0),
            'git@example.com:org/pass.git',
          );
          await tester.tap(find.widgetWithText(TextButton, 'Choose'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Clone').last);
          break;
      }
      await tester.pumpAndSettle();

      expect(repository.storeActions.single, startsWith(branch.actionPrefix));
      if (branch == _StoreBranch.create) {
        expect(
          repository.storeActions.single,
          'create:Personal:/tmp/personal:ABCD 1234:git:true',
        );
      }
      expect(find.text('Review setup'), findsOneWidget);
    });
  }

  testWidgets('mobile onboarding uses app-managed store paths', (tester) async {
    final repository = _ManagedPathOnboardingRepository(storeReady: false);

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
    await tester.tap(find.text('Skip SSH'));
    await tester.pumpAndSettle();

    expect(find.text('Import local store'), findsOneWidget);
    await tester.tap(find.text('Create local store'));
    await tester.pumpAndSettle();

    expect(find.text('Local path'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Work Store');
    await tester.tap(find.widgetWithText(FilledButton, 'Create').last);
    await tester.pumpAndSettle();

    expect(
      repository.storeActions.single,
      'create:Work Store:/app/support/stores/work-store:ABCD 1234:git:false',
    );
  });

  testWidgets('mobile onboarding copies a local store into app storage', (
    tester,
  ) async {
    final repository = _ManagedPathDiagnosticRepository(storeReady: false);
    final pathPicker = _FakePathPickerService(
      managedImportResults: <Object?>['/app/support/stores/existing-store'],
    );

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
        pathPickerService: pathPicker,
      ),
    );
    await tester.tap(find.text('Use PGP key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip SSH'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import local store'));
    await tester.pumpAndSettle();
    expect(find.text('Copy into app storage'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Choose folder and import'),
    );
    await tester.pumpAndSettle();

    expect(
      pathPicker.managedImportDestinationBaseDirectories.single,
      '/app/support/stores',
    );
    expect(
      repository.storeActions.single,
      'import:/app/support/stores/existing-store',
    );
    expect(find.text('Review setup'), findsOneWidget);
    expect(find.text('Configured'), findsWidgets);
    expect(find.text('Git remote missing'), findsNothing);
    expect(find.text('PGP key missing'), findsNothing);
  });

  testWidgets('onboarding store forms use native folder picker rows', (
    tester,
  ) async {
    final repository = _OnboardingBranchRepository(storeReady: false);
    final pathPicker = _FakePathPickerService(
      folderResults: <String?>[
        '/Users/alice/Stores',
        '/Users/alice/Imported Store',
        '/Users/alice/Clones',
      ],
    );

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
        pathPickerService: pathPicker,
      ),
    );

    await tester.tap(find.text('Use PGP key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip SSH'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create local store'));
    await tester.pumpAndSettle();
    expect(find.text('Store folder'), findsOneWidget);
    expect(find.text('Default: /tmp/personal'), findsOneWidget);
    expect(find.text('Local path'), findsNothing);
    expect(
      tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .last
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: /Users/alice/Stores/personal'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create').last);
    await tester.pumpAndSettle();
    expect(
      repository.storeActions.single,
      'create:Personal:/Users/alice/Stores/personal:ABCD 1234:git:true',
    );
    expect(pathPicker.folderInitialDirectories.first, '/tmp');

    repository.storeReady = false;
    repository.storeActions.clear();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Set up password store'), findsOneWidget);
    await tester.tap(find.text('Import local store'));
    await tester.pumpAndSettle();
    expect(find.text('Store folder'), findsOneWidget);
    expect(find.text('Local path'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: /Users/alice/Imported Store'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
    await tester.pumpAndSettle();
    expect(
      repository.storeActions.single,
      'import:/Users/alice/Imported Store',
    );
  });

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
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
          break;
      }
      await tester.pumpAndSettle();

      expect(repository.keyActions, contains(startsWith(branch.actionPrefix)));
      expect(repository.keyActions.last, startsWith('add-pgp:'));
      expect(find.text('Set up SSH for GitHub'), findsOneWidget);
    });
  }

  testWidgets(
    'onboarding protected PGP import advances only after validation',
    (tester) async {
      const passphrase = 'onboarding passphrase';
      final repository =
          _OnboardingBranchRepository()
            ..pgpInspection = const PgpKeyInspection(
              kind: PgpKeyKind.private,
              fingerprint: 'PROTECTED ABC',
              identity: 'Protected <protected@example.com>',
              hasPrivateKey: true,
              requiresPassphrase: true,
              armored: true,
            )
            ..pgpImportFailure = const PgpImportException(
              PgpImportFailureKind.incorrectPassphrase,
              'the PGP private key passphrase is incorrect',
            );
      final security = InMemorySecurityRepository.withPattern(
        const <int>[0, 1, 2, 5],
        biometricUnlockEnabled: true,
        onboardingComplete: false,
        lastUnlockedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ParsGuiApp(
          vaultRepository: repository,
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: security,
        ),
      );

      await tester.tap(find.text('Import PGP key'));
      await tester.pumpAndSettle();
      // Onboarding offers the same Text/File choice as Settings.
      expect(find.byType(PgpKeyImportBody), findsOneWidget);
      expect(
        find.widgetWithText(SegmentedButton<PgpImportSource>, 'File'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField).last,
        '-----BEGIN PGP PRIVATE KEY BLOCK-----',
      );
      await tester.pumpAndSettle();
      await _tapImportSubmit(tester, 'Import');
      expect(find.text('PGP passphrase'), findsOneWidget);

      // An incorrect passphrase must not advance to SSH.
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.pumpAndSettle();
      await _tapImportSubmit(tester, 'Unlock and import');
      expect(find.text('Set up SSH for GitHub'), findsNothing);
      expect(security.hasActivePgpSession, isFalse);
      expect(repository.keyActions, isNot(contains(startsWith('add-pgp:'))));

      // The correct passphrase selects the returned fingerprint and advances.
      repository.pgpImportFailure = null;
      await tester.enterText(find.byType(TextField).last, passphrase);
      await tester.pumpAndSettle();
      await _tapImportSubmit(tester, 'Unlock and import');

      expect(security.hasActivePgpSession, isTrue);
      final session = await security.readActivePgpPassphrase();
      expect(session?.fingerprint, 'PROTECTED ABC');
      expect(repository.keyActions.last, 'add-pgp:PROTECTED ABC');
      expect(find.text('Set up SSH for GitHub'), findsOneWidget);
      expect(find.textContaining(passphrase), findsNothing);
    },
  );

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
              keys: const <KeyRecord>[_testPgpKey],
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
        const PgpPassphraseCache(
          fingerprint: _testPgpFingerprint,
          passphrase: 'session-passphrase',
        ),
      );
      expect(repository.readCount, 1);
      expect(find.text('session-passphrase'), findsNothing);
    },
  );

  testWidgets('entry passphrase sheet stays above the software keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final repository = _SecretActionRepository();
    final securityRepository = InMemorySecurityRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed:
                        () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder:
                              (_) => EntryDetailSheet(
                                entry: repository.entries.single,
                                repository: repository,
                                securityRepository: securityRepository,
                                keys: const <KeyRecord>[_testPgpKey],
                              ),
                        ),
                    child: const Text('Open entry'),
                  ),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    const keyboardTop = 844.0 - 320.0;
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThan(keyboardTop),
    );
    expect(
      tester
          .getBottomLeft(find.widgetWithText(FilledButton, 'Unlock entry'))
          .dy,
      lessThanOrEqualTo(keyboardTop),
    );
  });

  testWidgets('entry detail surfaces use the active dark theme', (
    tester,
  ) async {
    final darkTheme = ParsTheme.dark();
    final repository = _SecretActionRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: EntryDetailSheet(
            entry: repository.entries.single,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final passwordSurfaceFinder = find.byKey(
      const ValueKey<String>('entry-password-surface'),
    );
    final passwordSurface = tester.widget<DecoratedBox>(passwordSurfaceFinder);
    final passwordDecoration = passwordSurface.decoration as BoxDecoration;
    expect(passwordDecoration.color, darkTheme.inputDecorationTheme.fillColor);
    final passwordText = tester.widget<Text>(
      find.descendant(of: passwordSurfaceFinder, matching: find.byType(Text)),
    );
    expect(passwordText.style?.color, darkTheme.colorScheme.onSurface);
    final revealButton = tester.widget<IconButton>(
      find.descendant(
        of: passwordSurfaceFinder,
        matching: find.byType(IconButton),
      ),
    );
    expect(revealButton.color, darkTheme.colorScheme.onSurfaceVariant);

    final securityRepository = InMemorySecurityRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: EntryDetailSheet(
            key: const ValueKey<String>('passphrase-entry-detail'),
            entry: repository.entries.single,
            repository: repository,
            securityRepository: securityRepository,
            keys: const <KeyRecord>[_testPgpKey],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final passphraseDecorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator),
    );
    expect(passphraseDecorator.decoration.filled, isTrue);
    expect(
      passphraseDecorator.decoration.fillColor,
      darkTheme.inputDecorationTheme.fillColor,
    );
  });

  testWidgets('entry detail modal adapts to phone and wider route widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final viewportWidth in <double>[390, 900]) {
      tester.view.physicalSize = Size(viewportWidth, 844);
      final repository = _ControlledSecretActionRepository();
      await _openEntryDetailModal(tester, repository: repository);

      final expectedWidth = viewportWidth <= 640 ? viewportWidth : 640.0;
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('entry-detail-sheet')))
            .width,
        expectedWidth,
      );

      Navigator.of(
        tester.element(
          find.byKey(const ValueKey<String>('entry-detail-sheet')),
        ),
      ).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('entry detail modal keeps its width after secret reads finish', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _ControlledSecretActionRepository();
    await _openEntryDetailModal(tester, repository: repository);
    final detailFinder = find.byKey(
      const ValueKey<String>('entry-detail-sheet'),
    );
    final loadingWidth = tester.getSize(detailFinder).width;

    repository.completeRead();
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(tester.getSize(detailFinder).width, loadingWidth);

    Navigator.of(tester.element(detailFinder)).pop();
    await tester.pumpAndSettle();

    final failingRepository = _ControlledSecretActionRepository();
    await _openEntryDetailModal(tester, repository: failingRepository);
    final failingLoadingWidth = tester.getSize(detailFinder).width;

    failingRepository.failRead();
    await tester.pumpAndSettle();

    expect(find.text('Could not decrypt entry'), findsOneWidget);
    expect(tester.getSize(detailFinder).width, failingLoadingWidth);
  });

  testWidgets('entry detail modal keeps its width after passphrase unlock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _ControlledSecretActionRepository();
    final securityRepository = InMemorySecurityRepository();
    await _openEntryDetailModal(
      tester,
      repository: repository,
      securityRepository: securityRepository,
      keys: const <KeyRecord>[_testPgpKey],
    );
    final detailFinder = find.byKey(
      const ValueKey<String>('entry-detail-sheet'),
    );
    final passphraseWidth = tester.getSize(detailFinder).width;

    await tester.enterText(find.byType(TextField), 'session-passphrase');
    await tester.tap(find.text('Unlock entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(detailFinder).width, passphraseWidth);

    repository.completeRead();
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(tester.getSize(detailFinder).width, passphraseWidth);
  });

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
    expect(find.text('Path: work/first'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();

    expect(find.text('Type First Entry to confirm.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'work/first');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();
    expect(repository.deletedPaths, isEmpty);
    expect(find.text('Type First Entry to confirm.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'First Entry');
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

  testWidgets('settings system autofill sheet refreshes and clears data', (
    tester,
  ) async {
    final repository = _InjectedRepository();
    final autofillRepository = FakeAutofillRepository();
    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      autofillRepository: autofillRepository,
    );

    await tester.scrollUntilVisible(
      find.text('System autofill'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('System autofill'));
    await tester.tap(find.widgetWithText(FilledButton, 'Rebuild paths'));
    await tester.pumpAndSettle();

    expect(autofillRepository.lastRebuiltEntries, isNotEmpty);
    expect(autofillRepository.status.available, isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Read URL fields'));
    await tester.pumpAndSettle();
    expect(find.text('Read encrypted URL fields?'), findsOneWidget);
    await tester.tap(find.text('Read selected entries'));
    await tester.pumpAndSettle();
    expect(autofillRepository.lastEnrichedPaths, isNotEmpty);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear all'));
    await tester.pumpAndSettle();

    expect(autofillRepository.cleared, isTrue);
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

  testWidgets('settings keeps PGP and SSH key sheets separate', (tester) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
    );
    expect(find.text('PGP keys'), findsWidgets);
    expect(find.text(_settingsPrimaryPgpKey.name), findsOneWidget);
    expect(find.text(_settingsSshKey.name), findsNothing);
    Navigator.of(tester.element(find.text('PGP keys').last)).pop();
    await tester.pumpAndSettle();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.ssh,
    );
    expect(find.text('SSH keys'), findsWidgets);
    expect(find.text(_settingsSshKey.name), findsOneWidget);
    expect(find.text(_settingsPrimaryPgpKey.name), findsNothing);
  });

  testWidgets('settings shows store key references without local-key actions', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository(
      additionalKeys: const <KeyRecord>[_settingsStoreKeyReference],
    );

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
    );

    expect(find.text(_settingsStoreKeyReference.name), findsOneWidget);
    expect(
      find.textContaining('Referenced by Imported Store (.gpg-id)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Local key material is not installed'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Actions for PGP key ${_settingsStoreKeyReference.name}'),
      findsNothing,
    );
  });

  testWidgets('settings key sheets expose only create and import globally', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
    );
    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Import'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Import file'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Export public'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Export private'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Add to .gpg-id'), findsNothing);
    Navigator.of(tester.element(find.text('PGP keys').last)).pop();
    await tester.pumpAndSettle();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.ssh,
    );
    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Import'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Import file'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Export public'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Export private'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'GitHub settings'),
      findsNothing,
    );
  });

  testWidgets('settings import action handles text and file imports', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();
    final pathPicker = _FakePathPickerService(
      fileResults: <String?>['/tmp/deploy.key'],
    );

    // PGP goes straight to the shared source-independent body: no Text/File
    // dialog, and no guessing the kind from the source.
    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
      pathPickerService: pathPicker,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.byType(PgpKeyImportBody), findsOneWidget);
    expect(
      find.widgetWithText(SegmentedButton<PgpImportSource>, 'Text'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SegmentedButton<PgpImportSource>, 'File'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'PGP PUBLIC KEY');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('PGP keys').last)).pop();
    await tester.pumpAndSettle();

    // SSH keeps its own Text/File dialog because it needs a key name.
    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.ssh,
      pathPickerService: pathPicker,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Text'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'File'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'File'));
    await tester.pumpAndSettle();
    expect(find.text('Key file'), findsOneWidget);
    expect(find.text('Path'), findsNothing);
    expect(find.text('Default: /tmp'), findsOneWidget);
    expect(
      tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Import'))
          .last
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).at(0), 'deploy-key');
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: /tmp/deploy.key'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(repository.keyActions, <String>[
      'inspect-pgp-text:PGP PUBLIC KEY',
      'import-pgp-text:PGP PUBLIC KEY:',
      'import-ssh-file:deploy-key:/tmp/deploy.key',
    ]);
    expect(pathPicker.fileInitialDirectories.single, '/tmp');
  });

  testWidgets('settings PGP import follows detected kind for a picked file', (
    tester,
  ) async {
    // The old flow always called the private-key API for files, so a public key
    // from a file failed. Source must not decide the kind.
    final repository = _KeyManagementSettingsRepository();
    final pathPicker = _FakePathPickerService(
      fileResults: <String?>['/tmp/alice.gpg'],
    );

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
      pathPickerService: pathPicker,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    // Nothing picked yet, so Import stays disabled.
    expect(
      tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Import'))
          .last
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
    await tester.pumpAndSettle();

    expect(repository.keyActions, <String>[
      'inspect-pgp-file:/tmp/alice.gpg',
      'import-pgp-file:/tmp/alice.gpg:',
    ]);
    // A public key, even though it came from a file.
    expect(find.textContaining('Imported'), findsWidgets);
  });

  testWidgets('settings PGP import reports a cancelled or failing picker', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();
    final pathPicker = _FakePathPickerService(
      fileResults: <Object?>[
        null,
        const PathPickerException('File picker unavailable.'),
      ],
    );

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
      pathPickerService: pathPicker,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    // Cancelling leaves the form untouched and inspects nothing.
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(repository.keyActions, isEmpty);

    // A picker error is shown inline.
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.textContaining('File picker unavailable.'), findsOneWidget);
    expect(repository.keyActions, isEmpty);
  });

  testWidgets(
    'settings protected PGP import validates the passphrase before completing',
    (tester) async {
      const passphrase = 'correct horse battery staple';
      final repository =
          _KeyManagementSettingsRepository()
            ..pgpInspection = const PgpKeyInspection(
              kind: PgpKeyKind.private,
              fingerprint: 'PGP-BACKUP',
              identity: 'Backup User <backup@example.com>',
              hasPrivateKey: true,
              requiresPassphrase: true,
              armored: true,
            )
            ..pgpImportFailure = const PgpImportException(
              PgpImportFailureKind.incorrectPassphrase,
              'the PGP private key passphrase is incorrect',
            );
      final security = InMemorySecurityRepository();

      await _pumpKeyManagementSheet(
        tester,
        repository: repository,
        type: KeyRecordType.pgp,
        securityRepository: security,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '-----BEGIN PGP PRIVATE KEY BLOCK-----',
      );
      await tester.pumpAndSettle();

      // Inspection reveals the key is protected, so the passphrase step appears
      // instead of the import completing.
      await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
      await tester.pumpAndSettle();
      expect(find.text('PGP passphrase'), findsOneWidget);
      expect(find.text('Remember in Keychain/KMS'), findsOneWidget);
      expect(repository.keyActions, <String>[
        'inspect-pgp-text:-----BEGIN PGP PRIVATE KEY BLOCK-----',
      ]);
      // Remember defaults off.
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );

      // A wrong passphrase keeps the user in the flow with a sanitized error.
      await tester.enterText(find.byType(TextField).last, 'wrong passphrase');
      await tester.pumpAndSettle();
      await _tapImportSubmit(tester, 'Unlock and import');
      expect(find.byType(PgpKeyImportBody), findsOneWidget);
      expect(
        find.text('That passphrase did not unlock this key. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('wrong passphrase'), findsNothing);
      expect(security.hasActivePgpSession, isFalse);
      expect(security.hasStoredPgpPassphrase, isFalse);

      // The correct passphrase starts a session bound to the returned key.
      repository.pgpImportFailure = null;
      await tester.enterText(find.byType(TextField).last, passphrase);
      await tester.pumpAndSettle();
      await _tapImportSubmit(tester, 'Unlock and import');

      expect(
        repository.keyActions.last,
        'import-pgp-text:-----BEGIN PGP PRIVATE KEY BLOCK-----:$passphrase',
      );
      expect(security.hasActivePgpSession, isTrue);
      final session = await security.readActivePgpPassphrase();
      expect(session?.fingerprint, 'PGP-BACKUP');
      // Remember stayed off, so nothing was written to durable storage.
      expect(security.hasStoredPgpPassphrase, isFalse);
      expect(find.textContaining(passphrase), findsNothing);
    },
  );

  testWidgets('settings PGP import can remember the passphrase on request', (
    tester,
  ) async {
    const passphrase = 'correct horse battery staple';
    final repository =
        _KeyManagementSettingsRepository()
          ..pgpInspection = const PgpKeyInspection(
            kind: PgpKeyKind.private,
            fingerprint: 'PGP-BACKUP',
            identity: 'Backup User <backup@example.com>',
            hasPrivateKey: true,
            requiresPassphrase: true,
            armored: true,
          );
    final security = InMemorySecurityRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
      securityRepository: security,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '-----BEGIN PGP PRIVATE KEY BLOCK-----',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, passphrase);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await _tapImportSubmit(tester, 'Unlock and import');

    expect(security.pgpPassphraseStorageEnabled, isTrue);
    final stored = await security.readPgpPassphrase();
    expect(stored?.fingerprint, 'PGP-BACKUP');
    expect(stored?.passphrase, passphrase);
    expect(find.textContaining(passphrase), findsNothing);
  });

  testWidgets(
    'settings reports a secure-storage failure without losing the key',
    (tester) async {
      final repository =
          _KeyManagementSettingsRepository()
            ..pgpInspection = const PgpKeyInspection(
              kind: PgpKeyKind.private,
              fingerprint: 'PGP-BACKUP',
              identity: 'Backup User <backup@example.com>',
              hasPrivateKey: true,
              requiresPassphrase: true,
              armored: true,
            );
      final security = _FailingStorageSecurityRepository();

      await _pumpKeyManagementSheet(
        tester,
        repository: repository,
        type: KeyRecordType.pgp,
        securityRepository: security,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '-----BEGIN PGP PRIVATE KEY BLOCK-----',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'a passphrase');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await _tapImportSubmit(tester, 'Unlock and import');

      // The key stays imported and the session live; only remembering failed.
      expect(
        find.textContaining('remembering the passphrase failed'),
        findsOneWidget,
      );
      expect(security.hasActivePgpSession, isTrue);
      expect(security.hasStoredPgpPassphrase, isFalse);
      expect(find.textContaining('a passphrase'), findsNothing);
    },
  );

  testWidgets('settings store forms use native folder picker rows', (
    tester,
  ) async {
    final repository = _StorePathSettingsRepository();
    final pathPicker = _FakePathPickerService(
      folderResults: <String?>[
        '/Users/alice/Stores',
        '/Users/alice/Existing Store',
        '/Users/alice/Clones',
      ],
    );

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: pathPicker,
    );

    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Store folder'), findsOneWidget);
    expect(
      find.text('Default: /Users/alice/Password Stores/personal'),
      findsOneWidget,
    );
    expect(find.text('Local path'), findsNothing);
    expect(
      tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .last
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: /Users/alice/Stores/personal'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create').last);
    await tester.pumpAndSettle();
    expect(
      repository.storeActions.single,
      'create:Personal:/Users/alice/Stores/personal::git:true',
    );
    expect(
      pathPicker.folderInitialDirectories.first,
      '/Users/alice/Password Stores',
    );

    repository.storeActions.clear();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Store folder'), findsOneWidget);
    expect(find.text('Local path'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: /Users/alice/Existing Store'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
    await tester.pumpAndSettle();
    expect(
      repository.storeActions.single,
      'import:/Users/alice/Existing Store',
    );

    repository.storeActions.clear();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Clone'));
    await tester.pumpAndSettle();
    expect(find.text('Store folder'), findsOneWidget);
    expect(find.text('Local path'), findsNothing);
    await tester.enterText(
      find.byType(TextField).first,
      'git@example.com:org/pass.git',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: /Users/alice/Clones/pass'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clone').last);
    await tester.pumpAndSettle();
    expect(
      repository.storeActions.single,
      'clone:git@example.com:org/pass.git:/Users/alice/Clones/pass',
    );
  });

  testWidgets('settings keeps managed stores inside app storage', (
    tester,
  ) async {
    final repository = _ManagedPathDiagnosticRepository(storeReady: true);
    final pathPicker = _FakePathPickerService(
      managedImportResults: <Object?>['/app/support/stores/existing-store'],
    );

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: pathPicker,
    );
    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Remove from app'), findsNothing);
    expect(find.text('Delete app copy'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Copy into app storage'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Choose folder and import'),
    );
    await tester.pumpAndSettle();
    expect(
      pathPicker.managedImportDestinationBaseDirectories.single,
      '/app/support/stores',
    );
    expect(
      repository.storeActions.single,
      'import:/app/support/stores/existing-store',
    );
    expect(find.text('Import complete: 1 passwords.'), findsOneWidget);
    repository.storeActions.clear();

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Default: /app/support/stores/personal'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Choose'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).first, 'Work Store');
    await tester.tap(find.widgetWithText(FilledButton, 'Create').last);
    await tester.pumpAndSettle();

    expect(
      repository.storeActions.single,
      'create:Work Store:/app/support/stores/work-store::git:false',
    );
  });

  testWidgets('settings localizes an empty Android store import', (
    tester,
  ) async {
    final repository = _ManagedPathDiagnosticRepository(storeReady: true);
    final pathPicker = _FakePathPickerService(
      managedImportResults: <Object?>[
        const PathPickerException(
          'No passwords were found in the selected folder.',
          code: 'store_import_no_passwords',
        ),
      ],
    );

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: pathPicker,
    );
    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Choose folder and import'),
    );
    await tester.pump();

    expect(find.text('No passwords were found.'), findsOneWidget);
    expect(repository.storeActions, isEmpty);
  });

  testWidgets('settings shows progress while Android store import is pending', (
    tester,
  ) async {
    final repository = _ManagedPathDiagnosticRepository(storeReady: true);
    final pathPicker = _PendingManagedImportPathPicker();

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: pathPicker,
    );
    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Choose folder and import'),
    );
    await tester.pump();

    expect(find.text('Working…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repository.storeActions, isEmpty);

    pathPicker.complete('/app/support/stores/imported');
    await tester.pumpAndSettle();
    expect(
      repository.storeActions.single,
      'import:/app/support/stores/imported',
    );
  });

  testWidgets('settings deletes local store with store-name confirmation', (
    tester,
  ) async {
    final repository = _StorePathSettingsRepository();

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: _FakePathPickerService(),
    );

    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete local store'));
    await tester.pumpAndSettle();

    expect(find.text('/Users/alice/Password Stores/personal'), findsOneWidget);
    expect(find.text('Type personal to confirm'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'personal');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      repository.storeActions.single,
      'delete:/Users/alice/Password Stores/personal:personal',
    );
  });

  testWidgets('settings deletes an app-managed copy instead of orphaning it', (
    tester,
  ) async {
    final repository = _ManagedPathDiagnosticRepository(storeReady: true);

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: _FakePathPickerService(),
    );
    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Remove from app'), findsNothing);
    await tester.tap(find.text('Delete app copy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'existing-store');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      repository.storeActions.single,
      'delete:/app/support/stores/existing-store:existing-store',
    );
  });

  testWidgets('settings picker rows handle cancellation and errors', (
    tester,
  ) async {
    final repository = _StorePathSettingsRepository();
    final pathPicker = _FakePathPickerService(
      folderResults: <Object?>[
        null,
        const PathPickerException('Picker unavailable'),
      ],
    );

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: pathPicker,
    );
    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Default: /Users/alice/Password Stores'), findsOneWidget);
    expect(find.textContaining('Selected:'), findsNothing);
    expect(
      tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Import'))
          .last
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Picker unavailable'), findsOneWidget);
    expect(repository.storeActions, isEmpty);
  });

  testWidgets('settings keeps store and key path pickers separate', (
    tester,
  ) async {
    final repository = _StorePathSettingsRepository();

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
      pathPickerService: _FakePathPickerService(),
    );
    await tester.scrollUntilVisible(
      find.text('Password stores'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('Password stores'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Import local store'), findsOneWidget);
    expect(find.text('Store folder'), findsOneWidget);
    expect(find.text('Key file'), findsNothing);
    Navigator.of(tester.element(find.text('Import local store'))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Password stores').last)).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('PGP keys'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('PGP keys'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    // PGP import opens the shared body directly, with File as a source choice.
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.byType(PgpKeyImportBody), findsOneWidget);
    expect(find.text('Key file'), findsOneWidget);
    expect(find.text('Store folder'), findsNothing);
  });

  testWidgets('settings PGP row menu targets the selected key', (tester) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
    );
    await tester.tap(
      find.byTooltip('Actions for PGP key ${_settingsBackupPgpKey.name}'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Export public'), findsOneWidget);
    expect(find.text('Export private'), findsOneWidget);
    expect(find.text('Add to .gpg-id'), findsOneWidget);
    expect(find.text('Delete key'), findsOneWidget);

    await tester.tap(find.text('Export public'));
    await tester.pumpAndSettle();
    expect(repository.keyActions, <String>['export-pgp-public:PGP-BACKUP']);
    Navigator.of(tester.element(find.text('Exported key'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('Actions for PGP key ${_settingsBackupPgpKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to .gpg-id'));
    await tester.pumpAndSettle();
    expect(repository.keyActions, <String>[
      'export-pgp-public:PGP-BACKUP',
      'add-pgp:PGP-BACKUP',
    ]);
  });

  testWidgets('settings SSH row menu targets the selected key', (tester) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.ssh,
    );
    await tester.tap(
      find.byTooltip('Actions for SSH key ${_settingsSshKey.name}'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Export public'), findsOneWidget);
    expect(find.text('Export private'), findsOneWidget);
    expect(find.text('Delete key'), findsOneWidget);
    expect(find.text('Add to .gpg-id'), findsNothing);

    await tester.tap(find.text('Export public'));
    await tester.pumpAndSettle();
    expect(repository.keyActions, <String>['export-ssh-public:github-mobile']);
  });

  testWidgets(
    'settings deletes PGP key using name without email and clears cache',
    (tester) async {
      final repository = _KeyManagementSettingsRepository();
      final securityRepository = InMemorySecurityRepository();
      await securityRepository.savePgpPassphrase(
        fingerprint: _settingsPrimaryPgpKey.fingerprint,
        passphrase: 'stored-passphrase',
      );
      await securityRepository.startPgpSession(
        fingerprint: _settingsPrimaryPgpKey.fingerprint,
        passphrase: 'active-passphrase',
      );

      await _pumpSettingsScreen(
        tester,
        repository: repository,
        securityRepository: securityRepository,
      );

      await tester.tap(find.text('PGP keys'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Actions for PGP key ${_settingsPrimaryPgpKey.name}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete key'));
      await tester.pumpAndSettle();

      expect(find.text('Delete PGP key'), findsOneWidget);
      expect(
        find.textContaining(_settingsPrimaryPgpKey.fingerprint),
        findsWidgets,
      );
      expect(
        find.textContaining('Type $_settingsPrimaryPgpUsername to delete it.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byType(TextField).last,
        _settingsPrimaryPgpKey.fingerprint,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byType(TextField).last,
        _settingsPrimaryPgpKey.name,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byType(TextField).last,
        _settingsPrimaryPgpUsername,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.deleteActions, <String>['pgp:PGP-PRIMARY']);
      expect(find.text(_settingsPrimaryPgpKey.name), findsNothing);
      expect(await securityRepository.readPgpPassphrase(), isNull);
      expect(await securityRepository.readActivePgpPassphrase(), isNull);
    },
  );

  testWidgets('PGP delete confirmation stays usable above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _pumpSettingsScreen(
      tester,
      repository: _KeyManagementSettingsRepository(),
      securityRepository: InMemorySecurityRepository(),
    );
    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Actions for PGP key ${_settingsPrimaryPgpKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    const keyboardTop = 844.0 - 320.0;
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThanOrEqualTo(keyboardTop),
    );
    expect(
      tester.getBottomLeft(find.widgetWithText(FilledButton, 'Delete')).dy,
      lessThanOrEqualTo(keyboardTop),
    );
  });

  testWidgets('settings deletes SSH key after exact confirmation', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
    );

    await tester.tap(find.text('SSH keys'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Actions for SSH key ${_settingsSshKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Type github-mobile to delete it.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, _settingsSshKey.name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteActions, <String>['ssh:github-mobile']);
    expect(find.text(_settingsSshKey.name), findsNothing);
  });

  testWidgets('settings key deletion can be canceled', (tester) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: InMemorySecurityRepository(),
    );

    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Actions for PGP key ${_settingsPrimaryPgpKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deleteActions, isEmpty);
    expect(find.text(_settingsPrimaryPgpKey.name), findsOneWidget);
  });

  testWidgets('settings key deletion failure keeps key visible', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository(failPgpDelete: true);
    final securityRepository = InMemorySecurityRepository();
    await securityRepository.savePgpPassphrase(
      fingerprint: _settingsPrimaryPgpKey.fingerprint,
      passphrase: 'stored-passphrase',
    );
    await securityRepository.startPgpSession(
      fingerprint: _settingsPrimaryPgpKey.fingerprint,
      passphrase: 'active-passphrase',
    );

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: securityRepository,
    );

    await tester.tap(find.text('PGP keys'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Actions for PGP key ${_settingsPrimaryPgpKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      _settingsPrimaryPgpUsername,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteActions, <String>['pgp:PGP-PRIMARY']);
    expect(find.textContaining('delete failed visibly'), findsOneWidget);
    expect(find.text(_settingsPrimaryPgpKey.name), findsOneWidget);
    expect(
      (await securityRepository.readPgpPassphrase())?.passphrase,
      'stored-passphrase',
    );
    expect(
      (await securityRepository.readActivePgpPassphrase())?.passphrase,
      'active-passphrase',
    );
  });

  testWidgets(
    'settings reports partial PGP deletion and clears private-key session state',
    (tester) async {
      final repository = _KeyManagementSettingsRepository(
        partialPgpDelete: true,
      );
      final securityRepository = InMemorySecurityRepository();
      await securityRepository.savePgpPassphrase(
        fingerprint: _settingsPrimaryPgpKey.fingerprint,
        passphrase: 'stored-passphrase',
      );
      await securityRepository.startPgpSession(
        fingerprint: _settingsPrimaryPgpKey.fingerprint,
        passphrase: 'active-passphrase',
      );

      await _pumpSettingsScreen(
        tester,
        repository: repository,
        securityRepository: securityRepository,
      );
      await tester.tap(find.text('PGP keys'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Actions for PGP key ${_settingsPrimaryPgpKey.name}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete key'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        _settingsPrimaryPgpUsername,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.deleteActions, <String>['pgp:PGP-PRIMARY']);
      expect(
        find.text(
          'The protected private key was deleted, but its public listing could not be removed.',
        ),
        findsOneWidget,
      );
      expect(
        repository.keys
            .singleWhere(
              (key) => key.fingerprint == _settingsPrimaryPgpKey.fingerprint,
            )
            .hasPrivateKey,
        isFalse,
      );
      expect(await securityRepository.readPgpPassphrase(), isNull);
      expect(await securityRepository.readActivePgpPassphrase(), isNull);
    },
  );

  testWidgets('settings PGP private export confirms with key name phrase', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.pgp,
    );
    await tester.tap(
      find.byTooltip('Actions for PGP key ${_settingsBackupPgpKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export private'));
    await tester.pumpAndSettle();

    final phrase = 'EXPORT PRIVATE KEY ${_settingsBackupPgpKey.name}';
    expect(find.text('Export private key'), findsOneWidget);
    expect(
      find.textContaining(_settingsBackupPgpKey.fingerprint),
      findsWidgets,
    );
    expect(find.textContaining(phrase), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byType(TextField).last,
      'EXPORT PRIVATE KEY ${_settingsBackupPgpKey.fingerprint}',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).last, phrase);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(repository.keyActions, <String>[
      'export-pgp-private:PGP-BACKUP:$phrase',
    ]);
    expect(find.text('pgp private PGP-BACKUP'), findsOneWidget);
  });

  testWidgets('settings SSH private export confirms with key name phrase', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();

    await _pumpKeyManagementSheet(
      tester,
      repository: repository,
      type: KeyRecordType.ssh,
    );
    await tester.tap(
      find.byTooltip('Actions for SSH key ${_settingsSshKey.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export private'));
    await tester.pumpAndSettle();

    const phrase = 'EXPORT PRIVATE KEY github-mobile';
    expect(find.textContaining(_settingsSshKey.fingerprint), findsWidgets);
    expect(find.textContaining(phrase), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).last, phrase);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(repository.keyActions, <String>[
      'export-ssh-private:github-mobile:$phrase',
    ]);
    expect(find.text('ssh private github-mobile'), findsOneWidget);
  });

  testWidgets('settings saves PGP passphrase for selected private key', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository();
    final securityRepository = InMemorySecurityRepository();

    await _pumpSettingsScreen(
      tester,
      repository: repository,
      securityRepository: securityRepository,
    );

    await tester.tap(find.text('KMS / Keychain passphrase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Store PGP passphrase'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pgp-passphrase-key-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_settingsBackupPgpKey.name).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pgp-passphrase');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      await securityRepository.readPgpPassphrase(),
      const PgpPassphraseCache(
        fingerprint: 'PGP-BACKUP',
        passphrase: 'pgp-passphrase',
      ),
    );
    expect(
      find.text('Cached for ${_settingsBackupPgpKey.name}'),
      findsOneWidget,
    );
    expect(find.text('pgp-passphrase'), findsNothing);
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

    await tester.scrollUntilVisible(
      find.text('Delete local repo'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text('Type example-store to delete the local repo.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete local repo'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).last, 'wrong-store');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete local repo'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).last, 'example-store');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete local repo'));
    await tester.pumpAndSettle();

    expect(repository.gitCalls, contains('delete local repo'));
  });

  testWidgets('settings advanced git args show failed output', (tester) async {
    final repository = _GitSettingsRepository(failAdvancedArgs: true);

    await _pumpAdvancedGitArgsSheet(tester, repository);

    await tester.enterText(find.byType(TextField).first, 'status --bad');
    await tester.pumpAndSettle();
    expect(find.text('git status --bad'), findsOneWidget);

    await tester.tap(find.text('Run selected command'));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Exit: 128'), findsOneWidget);
    expect(find.text('fatal: bad revision'), findsOneWidget);
  });

  testWidgets('settings advanced git args opens with hint only', (
    tester,
  ) async {
    final repository = _GitSettingsRepository();

    await _pumpAdvancedGitArgsSheet(tester, repository);

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, isEmpty);
    expect(field.decoration?.hintText, 'status, log');
    expect(find.text('git status'), findsNothing);
    expect(repository.gitCalls, isEmpty);
  });

  testWidgets('settings advanced git args does not execute untouched hint', (
    tester,
  ) async {
    final repository = _GitSettingsRepository();

    await _pumpAdvancedGitArgsSheet(tester, repository);
    await tester.tap(find.text('Run selected command'));
    await tester.pumpAndSettle();

    expect(repository.gitCalls, isEmpty);
    expect(find.text('Enter at least one Git argument.'), findsOneWidget);
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
      activePgpPassphrase: const PgpPassphraseCache(
        fingerprint: _testPgpFingerprint,
        passphrase: 'pgp-passphrase',
      ),
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

    await _backgroundApp(tester);
    await tester.pumpAndSettle();
    await _resumeApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
    expect(securityRepository.hasActivePgpSession, isFalse);
  });

  testWidgets('locks after auto-lock timeout while backgrounded', (
    tester,
  ) async {
    var now = DateTime(2026);
    final securityRepository = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      autoLockTimeout: const Duration(seconds: 1),
      lastUnlockedAt: now,
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: const FakeParsRepository(),
        settingsRepository: const FakeParsRepository(),
        keyRepository: const FakeParsRepository(),
        gitRepository: const FakeParsRepository(),
        securityRepository: securityRepository,
        now: () => now,
      ),
    );

    expect(find.text('Vault'), findsWidgets);

    await _backgroundApp(tester);
    now = now.add(const Duration(milliseconds: 1100));
    await _resumeApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
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
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();

    expect(securityRepository.lockOnResume, isTrue);
    expect(securityRepository.autoLockTimeout, Duration.zero);
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

  testWidgets('automatically unlocks with biometrics when enabled', (
    tester,
  ) async {
    final biometrics = _FakeBiometricAuthAdapter(available: true);
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: biometrics,
    );
    await securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
    );
    await securityRepository.setBiometricUnlockEnabled(true);
    await securityRepository.savePgpPassphrase(
      fingerprint: _testPgpFingerprint,
      passphrase: 'pgp-passphrase',
    );
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

    expect(find.text('Vault'), findsWidgets);
    expect(securityRepository.hasActivePgpSession, isTrue);
    expect(
      await securityRepository.readActivePgpPassphrase(),
      const PgpPassphraseCache(
        fingerprint: _testPgpFingerprint,
        passphrase: 'pgp-passphrase',
      ),
    );
    expect(biometrics.authenticateCount, 2);
  });

  testWidgets('biometric unlock ignores auth lifecycle resume', (tester) async {
    final biometrics = _FakeBiometricAuthAdapter(available: true);
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: biometrics,
    );
    await securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
    );
    await securityRepository.setBiometricUnlockEnabled(true);
    await securityRepository.setLockOnResume(true);
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

    expect(find.text('Vault'), findsWidgets);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Unlock Pars'), findsNothing);
    expect(biometrics.authenticateCount, 2);
  });

  testWidgets('settings enables biometric unlock when available', (
    tester,
  ) async {
    final biometrics = _FakeBiometricAuthAdapter(available: true);
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: biometrics,
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
    expect(biometrics.authenticateCount, 1);
  });

  testWidgets('settings keeps biometric unlock disabled when auth fails', (
    tester,
  ) async {
    final biometrics = _FakeBiometricAuthAdapter(
      available: true,
      authenticateResult: false,
    );
    final securityRepository = await SecureStorageSecurityRepository.load(
      storage: _FakeSecureStorageAdapter(),
      biometricAuth: biometrics,
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

    await tester.tap(find.text('Biometric unlock'));
    await tester.pumpAndSettle();

    expect(securityRepository.biometricUnlockEnabled, isFalse);
    expect(biometrics.authenticateCount, 1);
    expect(find.text('Biometric authentication failed.'), findsOneWidget);
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
    expect(
      await securityRepository.readPgpPassphrase(),
      const PgpPassphraseCache(
        fingerprint: _testPgpFingerprint,
        passphrase: 'pgp-passphrase',
      ),
    );
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

Future<void> _openEntryDetailModal(
  WidgetTester tester, {
  required VaultRepository repository,
  ThemeData? theme,
  SecurityRepository? securityRepository,
  List<KeyRecord> keys = const <KeyRecord>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ParsTheme.light(),
      home: Builder(
        builder:
            (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: false,
                        builder:
                            (_) => EntryDetailSheet(
                              entry: repository.entries.single,
                              repository: repository,
                              securityRepository: securityRepository,
                              keys: keys,
                            ),
                      ),
                  child: const Text('Open entry detail'),
                ),
              ),
            ),
      ),
    ),
  );

  await tester.tap(find.text('Open entry detail'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required _InjectedRepository repository,
  required SecurityRepository securityRepository,
  AutofillRepository? autofillRepository,
  PathPickerService? pathPickerService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsScreen(
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: securityRepository,
          autofillRepository: autofillRepository,
          vaultRepository: repository,
          pathPickerService: pathPickerService ?? _FakePathPickerService(),
        ),
      ),
    ),
  );
}

/// Taps the import body's submit button, scrolling it into view first.
///
/// The passphrase step grows the sheet past the viewport, so the button ends up
/// below the fold.
Future<void> _tapImportSubmit(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label).last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _pumpKeyManagementSheet(
  WidgetTester tester, {
  required _InjectedRepository repository,
  required KeyRecordType type,
  PathPickerService? pathPickerService,
  SecurityRepository? securityRepository,
}) async {
  await _pumpSettingsScreen(
    tester,
    repository: repository,
    securityRepository: securityRepository ?? InMemorySecurityRepository(),
    pathPickerService: pathPickerService,
  );
  await tester.tap(
    find.text(type == KeyRecordType.pgp ? 'PGP keys' : 'SSH keys'),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAdvancedGitArgsSheet(
  WidgetTester tester,
  _GitSettingsRepository repository,
) async {
  await _pumpSettingsScreen(
    tester,
    repository: repository,
    securityRepository: InMemorySecurityRepository(),
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
}

Future<void> _backgroundApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<void> _resumeApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
  _FakeBiometricAuthAdapter({
    this.available = false,
    this.authenticateResult = true,
  });

  final bool available;
  final bool authenticateResult;
  int authenticateCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    authenticateCount += 1;
    return authenticateResult;
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
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async =>
      _publicKeyInspection;

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async =>
      _publicKeyInspection;

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async =>
      PgpImportResult(key: keys.first, inspection: _publicKeyInspection);

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async =>
      PgpImportResult(key: keys.first, inspection: _publicKeyInspection);

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
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async =>
      PgpPrivateKeyPreparation(fingerprint: fingerprint, migrated: false);

  @override
  Future<PgpKeyDeletionOutcome> deletePgpKey(String fingerprint) async =>
      PgpKeyDeletionOutcome(
        fingerprint: fingerprint,
        hadPrivateKey: true,
        privateKeyAbsent: true,
        publicKeyAbsent: true,
        publicCleanupFailed: false,
      );

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
  Future<void> deleteSshKey(String name) async {}

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

class _KeyManagementSettingsRepository extends _InjectedRepository {
  _KeyManagementSettingsRepository({
    this.failPgpDelete = false,
    this.partialPgpDelete = false,
    List<KeyRecord> additionalKeys = const <KeyRecord>[],
  }) : _keys = <KeyRecord>[
         _settingsPrimaryPgpKey,
         _settingsBackupPgpKey,
         _settingsSshKey,
         ...additionalKeys,
       ];

  final bool failPgpDelete;
  final bool partialPgpDelete;
  final List<KeyRecord> _keys;
  final List<String> deleteActions = <String>[];
  final List<String> keyActions = <String>[];

  /// What inspection reports for the next import. Tests override it to exercise
  /// the protected-private branch.
  PgpKeyInspection pgpInspection = _publicKeyInspection;

  /// Set to fail the next import, e.g. with an incorrect passphrase.
  PgpImportException? pgpImportFailure;

  @override
  List<KeyRecord> get keys => List<KeyRecord>.unmodifiable(_keys);

  @override
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async {
    keyActions.add('inspect-pgp-text:$armoredText');
    return pgpInspection;
  }

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async {
    keyActions.add('inspect-pgp-file:$path');
    return pgpInspection;
  }

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async {
    keyActions.add('import-pgp-text:$armoredText:${passphrase ?? ''}');
    return _pgpImportResult();
  }

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async {
    keyActions.add('import-pgp-file:$path:${passphrase ?? ''}');
    return _pgpImportResult();
  }

  PgpImportResult _pgpImportResult() {
    final failure = pgpImportFailure;
    if (failure != null) {
      throw failure;
    }
    return PgpImportResult(
      key: _settingsBackupPgpKey,
      inspection: pgpInspection,
    );
  }

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async {
    keyActions.add('import-pgp-public:$armoredText');
    return _settingsBackupPgpKey;
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async {
    keyActions.add('import-pgp-private:$armoredText');
    return _settingsBackupPgpKey;
  }

  @override
  Future<KeyRecord> importPgpPrivateKeyFile(String path) async {
    keyActions.add('import-pgp-file:$path');
    return _settingsBackupPgpKey;
  }

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) async {
    keyActions.add('import-ssh-text:$name:$privateKey');
    return _settingsSshKey;
  }

  @override
  Future<KeyRecord> importSshPrivateKeyFile({
    required String name,
    required String path,
  }) async {
    keyActions.add('import-ssh-file:$name:$path');
    return _settingsSshKey;
  }

  @override
  Future<String> exportPgpPublicKey(String fingerprint) async {
    keyActions.add('export-pgp-public:$fingerprint');
    return 'pgp public $fingerprint';
  }

  @override
  Future<String> exportPgpPrivateKey({
    required String fingerprint,
    required String confirmation,
  }) async {
    keyActions.add('export-pgp-private:$fingerprint:$confirmation');
    return 'pgp private $fingerprint';
  }

  @override
  Future<void> addPgpKeyToSelectedStore(String fingerprint) async {
    keyActions.add('add-pgp:$fingerprint');
  }

  @override
  Future<String> exportSshPublicKey(String name) async {
    keyActions.add('export-ssh-public:$name');
    return 'ssh public $name';
  }

  @override
  Future<String> exportSshPrivateKey({
    required String name,
    required String confirmation,
  }) async {
    keyActions.add('export-ssh-private:$name:$confirmation');
    return 'ssh private $name';
  }

  @override
  Future<PgpKeyDeletionOutcome> deletePgpKey(String fingerprint) async {
    deleteActions.add('pgp:$fingerprint');
    if (failPgpDelete) {
      throw Exception('delete failed visibly');
    }
    if (partialPgpDelete) {
      final index = _keys.indexWhere(
        (key) =>
            key.type == KeyRecordType.pgp && key.fingerprint == fingerprint,
      );
      final existing = _keys[index];
      _keys[index] = KeyRecord(
        type: existing.type,
        name: existing.name,
        fingerprint: existing.fingerprint,
        source: existing.source,
        hasPrivateKey: false,
        hasLocalKeyMaterial: true,
        referencedByStores: existing.referencedByStores,
      );
      return PgpKeyDeletionOutcome(
        fingerprint: fingerprint,
        hadPrivateKey: true,
        privateKeyAbsent: true,
        publicKeyAbsent: false,
        publicCleanupFailed: true,
      );
    }
    _keys.removeWhere(
      (key) => key.type == KeyRecordType.pgp && key.fingerprint == fingerprint,
    );
    return PgpKeyDeletionOutcome(
      fingerprint: fingerprint,
      hadPrivateKey: true,
      privateKeyAbsent: true,
      publicKeyAbsent: true,
      publicCleanupFailed: false,
    );
  }

  @override
  Future<void> deleteSshKey(String name) async {
    deleteActions.add('ssh:$name');
    _keys.removeWhere(
      (key) => key.type == KeyRecordType.ssh && key.name == name,
    );
  }
}

class _StorePathSettingsRepository extends _KeyManagementSettingsRepository {
  final List<String> storeActions = <String>[];

  @override
  StoreLifecycleSnapshot get lifecycle => const StoreLifecycleSnapshot(
    configPath: '/Users/alice/.config/pars/config.toml',
    configExists: true,
    selectedStoreId: 'personal',
    selectedStoreRoot: '/Users/alice/Password Stores/personal',
    onboardingState: StoreOnboardingState.ready,
    issues: <String>[],
    stores: <StoreStatus>[
      StoreStatus(
        id: 'personal',
        name: 'Personal',
        root: '/Users/alice/Password Stores/personal',
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
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool setDefault,
    required bool initializeGit,
  }) async {
    storeActions.add(
      'create:$name:$root:${pgpKeys.join(',')}:git:$initializeGit',
    );
  }

  @override
  Future<void> importLocalStore({
    required String root,
    required bool setDefault,
  }) async {
    storeActions.add('import:$root');
  }

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    required bool setDefault,
  }) async {
    storeActions.add('clone:$remoteUrl:$root');
  }

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {
    storeActions.add('delete:$root:$confirmation');
  }
}

/// Rejects durable writes while behaving normally for in-memory sessions.
class _FailingStorageSecurityRepository extends InMemorySecurityRepository {
  @override
  Future<void> savePgpPassphrase({
    required String fingerprint,
    required String passphrase,
  }) async {
    throw StateError('Keychain is unavailable');
  }
}

class _FakePathPickerService implements PathPickerService {
  _FakePathPickerService({
    List<Object?>? folderResults,
    List<Object?>? fileResults,
    List<Object?>? managedImportResults,
  }) : _folderResults = List<Object?>.of(folderResults ?? const <Object?>[]),
       _fileResults = List<Object?>.of(fileResults ?? const <Object?>[]),
       _managedImportResults = List<Object?>.of(
         managedImportResults ?? const <Object?>[],
       );

  final List<Object?> _folderResults;
  final List<Object?> _fileResults;
  final List<Object?> _managedImportResults;
  final List<String> folderInitialDirectories = <String>[];
  final List<String> fileInitialDirectories = <String>[];
  final List<String> managedImportDestinationBaseDirectories = <String>[];

  @override
  Future<String?> pickFolder({required String initialDirectory}) async {
    folderInitialDirectories.add(initialDirectory);
    return _next(_folderResults);
  }

  @override
  Future<String?> pickFile({required String initialDirectory}) async {
    fileInitialDirectories.add(initialDirectory);
    return _next(_fileResults);
  }

  @override
  Future<String?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
  }) async {
    managedImportDestinationBaseDirectories.add(destinationBaseDirectory);
    return _next(_managedImportResults);
  }

  String? _next(List<Object?> results) {
    if (results.isEmpty) {
      return null;
    }
    final result = results.removeAt(0);
    if (result is Exception) {
      throw result;
    }
    return result as String?;
  }
}

class _PendingManagedImportPathPicker extends _FakePathPickerService {
  final Completer<String?> _result = Completer<String?>();

  @override
  Future<String?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
  }) {
    managedImportDestinationBaseDirectories.add(destinationBaseDirectory);
    return _result.future;
  }

  void complete(String? path) => _result.complete(path);
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
  importPrivate('import private', 'import-pgp-text:');

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

  /// What inspection reports for the next import.
  PgpKeyInspection pgpInspection = const PgpKeyInspection(
    kind: PgpKeyKind.private,
    fingerprint: 'IMPORTED PRIVATE PGP',
    identity: 'Imported Private PGP',
    hasPrivateKey: true,
    requiresPassphrase: false,
    armored: true,
  );

  /// Set to fail the next import, e.g. with an incorrect passphrase.
  PgpImportException? pgpImportFailure;

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
    storeActions.add(
      'create:$name:$root:${pgpKeys.join(',')}:git:$initializeGit',
    );
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
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async {
    keyActions.add('inspect-pgp-text:$armoredText');
    return pgpInspection;
  }

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async {
    keyActions.add('inspect-pgp-file:$path');
    return pgpInspection;
  }

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async {
    keyActions.add('import-pgp-text:$armoredText:${passphrase ?? ''}');
    return _pgpImportResult();
  }

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async {
    keyActions.add('import-pgp-file:$path:${passphrase ?? ''}');
    return _pgpImportResult();
  }

  PgpImportResult _pgpImportResult() {
    final failure = pgpImportFailure;
    if (failure != null) {
      throw failure;
    }
    final key = KeyRecord(
      type: KeyRecordType.pgp,
      name: pgpInspection.identity,
      fingerprint: pgpInspection.fingerprint,
      source: 'Imported during onboarding',
      hasPrivateKey: pgpInspection.hasPrivateKey,
    );
    _keys.add(key);
    return PgpImportResult(key: key, inspection: pgpInspection);
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

class _ManagedPathOnboardingRepository extends _OnboardingBranchRepository
    implements AppManagedPathRepository {
  _ManagedPathOnboardingRepository({super.storeReady});

  @override
  bool get usesAppManagedPaths => true;

  @override
  bool isAppManagedStoreRoot(String root) =>
      root.startsWith('/app/support/stores/');

  @override
  String storeRootForName(String name) {
    return '/app/support/stores/${_slug(name)}';
  }

  @override
  String storeRootForRemote(String remoteUrl) {
    final withoutQuery = remoteUrl.split('?').first;
    final last = withoutQuery.split(RegExp(r'[:/]')).last;
    return '/app/support/stores/${_slug(last.replaceFirst(RegExp(r'\.git$'), ''))}';
  }

  String _slug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'password-store' : slug;
  }
}

class _ManagedPathDiagnosticRepository
    extends _ManagedPathOnboardingRepository {
  _ManagedPathDiagnosticRepository({required super.storeReady});

  @override
  StoreLifecycleSnapshot get lifecycle {
    if (!storeReady) {
      return super.lifecycle;
    }
    return const StoreLifecycleSnapshot(
      configPath: '/app/support/pars_config.toml',
      configExists: true,
      selectedStoreId: 'imported-store',
      selectedStoreRoot: '/app/support/stores/existing-store',
      onboardingState: StoreOnboardingState.gitRemoteMissing,
      issues: <String>['git_remote_missing', 'pgp_key_missing'],
      stores: <StoreStatus>[
        StoreStatus(
          id: 'imported-store',
          name: 'existing-store',
          root: '/app/support/stores/existing-store',
          isDefault: true,
          exists: true,
          hasGpgId: true,
          hasGitRemote: false,
          pgpKeyMissing: true,
          issues: <String>['git_remote_missing', 'pgp_key_missing'],
        ),
      ],
    );
  }

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {
    storeActions.add('delete:$root:$confirmation');
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

class _ControlledSecretActionRepository extends _SecretActionRepository {
  final Completer<SecretContent> _readCompleter = Completer<SecretContent>();

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) {
    readCount += 1;
    return _readCompleter.future;
  }

  void completeRead() {
    _readCompleter.complete(
      const SecretContent(
        password: 'loaded-secret',
        fields: <ParsedSecretField>[
          ParsedSecretField(key: 'username', label: 'Username', value: 'alice'),
        ],
        rawNotes: '',
      ),
    );
  }

  void failRead() {
    _readCompleter.completeError(Exception('missing private key'));
  }
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
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async =>
      throw UnimplementedError();

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async =>
      throw UnimplementedError();

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async => throw UnimplementedError();

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
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
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async => throw UnimplementedError();

  @override
  Future<PgpKeyDeletionOutcome> deletePgpKey(String fingerprint) async =>
      throw UnimplementedError();

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
  Future<void> deleteSshKey(String name) async => throw UnimplementedError();

  @override
  Future<Uri> githubSshSettingsUri() async => throw UnimplementedError();
}
