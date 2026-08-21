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
import 'package:pars_gui/widgets/app_notification.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';

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
void main() {
  setUp(AppNotification.dismiss);
  tearDown(AppNotification.dismiss);

  testWidgets('shows onboarding before entering the vault', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.text('Draw at least 4 dots.'), findsOneWidget);
  });

  testWidgets('enters the mobile shell after onboarding', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    await _completeReadyOnboarding(tester);

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('missing required PGP key reopens onboarding repair', (
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

    expect(find.text('Vault'), findsNothing);
    expect(find.text('Repair password store'), findsOneWidget);
    expect(find.text('Required private PGP key missing'), findsOneWidget);
  });

  for (final repairCase in <({String name, StoreStatus store, String title})>[
    (
      name: 'missing gpg id',
      title: 'Encryption recipients are missing',
      store: StoreStatus(
        name: 'Missing recipients',
        root: '/app/support/stores/missing-recipients',
        exists: true,
        hasGpgId: false,
        pgpKeyMissing: false,
        issues: <String>['missing_gpg_id'],
        gitMode: StoreGitMode.disabled,
      ),
    ),
    (
      name: 'invalid git',
      title: 'Git metadata is invalid',
      store: StoreStatus(
        name: 'Broken Git',
        root: '/app/support/stores/broken-git',
        exists: true,
        hasGpgId: true,
        pgpRecipients: <String>[_testPgpFingerprint],
        pgpKeyMissing: false,
        issues: <String>['git_invalid'],
        gitMode: StoreGitMode.invalid,
      ),
    ),
  ]) {
    testWidgets('root routes ${repairCase.name} to store repair', (
      tester,
    ) async {
      final repository = _MutableAppStoreRepository(
        initialStore: repairCase.store,
      );
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
      await tester.pumpAndSettle();

      expect(find.text('Vault'), findsNothing);
      expect(find.text('Repair password store'), findsOneWidget);
      expect(find.text(repairCase.title), findsOneWidget);
    });
  }

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

    expect(find.text('Set up password store'), findsOneWidget);
    expect(find.text('Import local store'), findsOneWidget);
    expect(find.text('Clone Git store'), findsOneWidget);
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
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          biometricUnlockEnabled: true,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );

    expect(find.text('Set up password store'), findsOneWidget);
    expect(find.text('Import local store'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
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

  testWidgets('removing state unmounts shell before store mutation', (
    tester,
  ) async {
    final repository = _MutableAppStoreRepository();
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
    await tester.pumpAndSettle();
    expect(find.text('Vault'), findsWidgets);

    repository.beginRemovalForTest();
    await tester.pump();
    expect(find.text('Removing password store…'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);

    repository.cancelRemovalForTest();
    await tester.pump();
    expect(find.text('Vault'), findsWidgets);
  });

  testWidgets('lifecycle source unmounts shell and closes sensitive routes', (
    tester,
  ) async {
    final repository = _MutableAppStoreRepository();
    final security = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      onboardingComplete: true,
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
    await tester.pumpAndSettle();
    expect(find.text('Vault'), findsWidgets);

    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Vault').first),
        builder:
            (context) =>
                const AlertDialog(content: Text('Sensitive route content')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sensitive route content'), findsOneWidget);

    await repository.removeStore(root: _mutableAppStore.root);
    await tester.pumpAndSettle();

    expect(find.text('Sensitive route content'), findsNothing);
    expect(find.text('Set up password store'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets(
    'deleting the canonical app store exits the shell without resetting security',
    (tester) async {
      final repository = _MutableAppStoreRepository();
      final security = InMemorySecurityRepository.withPattern(
        const <int>[0, 1, 2, 5],
        onboardingComplete: true,
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
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await _openSettingsTile(tester, 'Password store');
      await tester.ensureVisible(find.text('Delete app copy'));
      await tester.tap(find.text('Delete app copy'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'personal');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.store, isNull);
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | ');
      expect(
        find.text('Set up password store'),
        findsOneWidget,
        reason: visibleText,
      );
      final setupScrollable =
          find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first;
      await tester.scrollUntilVisible(
        find.text('Import local store'),
        160,
        scrollable: setupScrollable,
      );
      expect(find.text('Import local store'), findsOneWidget);
      expect(find.text('Vault'), findsNothing);
      expect(security.onboardingComplete, isTrue);
      expect(security.hasGestureVerifier, isTrue);
    },
  );

  testWidgets('failed physical deletion keeps the shell and retryable store', (
    tester,
  ) async {
    final repository = _MutableAppStoreRepository(failDelete: true);
    final security = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      onboardingComplete: true,
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await _openSettingsTile(tester, 'Password store');
    await tester.ensureVisible(find.text('Delete app copy'));
    await tester.tap(find.text('Delete app copy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'personal');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.store, isNotNull);
    expect(repository.deleteAttempts, 1);
    expect(find.text('Import local store'), findsNothing);
    expect(find.text('Delete'), findsWidgets);
  });

  testWidgets('lock takes precedence over no-store setup after restart', (
    tester,
  ) async {
    final repository = _MutableAppStoreRepository(initialStore: null);
    final security = InMemorySecurityRepository.withPattern(const <int>[
      0,
      1,
      2,
      5,
    ], onboardingComplete: true);
    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: security,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
    expect(find.text('Import local store'), findsNothing);
    await _drawGesture(tester);
    await tester.pumpAndSettle();
    expect(find.text('Import local store'), findsOneWidget);
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
    expect(find.byTooltip('Reveal'), findsOneWidget);
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

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
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

  testWidgets('entry detail offers retry without dead key-management routes', (
    tester,
  ) async {
    final repository = _SecretActionRepository(failReads: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryDetailSheet(
            entry: repository.entries.single,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not decrypt entry'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Choose/import key'), findsNothing);
    expect(find.text('Open key management'), findsNothing);

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

  testWidgets('entry detail keeps stable geometry after secret reads finish', (
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
    final loadingSize = tester.getSize(detailFinder);

    repository.completeRead();
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(tester.getSize(detailFinder), loadingSize);

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
    expect(find.text('Pull needed'), findsOneWidget);

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
    await tester.tap(find.byTooltip('Favorite').last);
    await tester.pumpAndSettle();

    expect(repository.favoritePaths, contains('work/github'));
    expect(find.byTooltip('Unfavorite'), findsWidgets);
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

    expect(find.textContaining('Could not load the vault'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.refreshCount, 2);
    expect(find.text('No recent entries yet.'), findsOneWidget);
    expect(find.text('No entries in this store.'), findsOneWidget);
  });

  testWidgets('Vault exposes contextual create and selection workflows', (
    tester,
  ) async {
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeReadyOnboarding(tester);

    expect(find.text('Manage'), findsNothing);
    expect(find.text('Create password'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);

    await tester.tap(find.text('Create password'));
    await tester.pumpAndSettle();
    expect(find.text('Generate and save'), findsOneWidget);
    expect(find.text('Save existing password'), findsOneWidget);
  });

  testWidgets('manage generates and saves a new entry', (tester) async {
    final repository = _ManageVaultRepository();

    await _openManageSurface(
      tester,
      (context) => showCreateGeneratedEntrySurface(
        context: context,
        repository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'work/new-entry');
    await tester.tap(find.text('Save generated password'));
    await tester.pumpAndSettle();

    expect(repository.generatedPaths, <String>['work/new-entry']);
    expect(find.text('Saved work/new-entry'), findsOneWidget);
  });

  testWidgets('manage saves an existing password', (tester) async {
    final repository = _ManageVaultRepository();

    await _openManageSurface(
      tester,
      (context) => showSaveExistingEntrySurface(
        context: context,
        repository: repository,
      ),
    );
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

    await _openManageSurface(
      tester,
      (context) => showFocusedEditEntrySheet(
        context: context,
        entry: repository.entries.first,
        repository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).at(1), 'rotated note');
    await tester.tap(find.text('Save edited entry'));
    await tester.pumpAndSettle();

    expect(repository.editedPaths, <String>['work/first']);
    expect(
      repository.editedContents.single,
      'old-secret\nusername: alice\nrotated note',
    );
    expect(find.text('Edited work/first (overwrote existing)'), findsOneWidget);

    await _openManageSurface(
      tester,
      (context) => showFocusedEditEntrySheet(
        context: context,
        entry: repository.entries.first,
        repository: repository,
      ),
    );
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

    await _openManageSurface(
      tester,
      (context) => showFocusedMoveOrRenameEntrySurface(
        context: context,
        entry: repository.entries.first,
        repository: repository,
        rename: false,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'archive');
    await tester.tap(find.widgetWithText(FilledButton, 'Move entry'));
    await tester.pumpAndSettle();

    expect(repository.movedFrom, <String>['work/first']);
    expect(repository.movedTo, <String>['archive/first']);

    await _openManageSurface(
      tester,
      (context) => showFocusedMoveOrRenameEntrySurface(
        context: context,
        entry: repository.entries.first,
        repository: repository,
        rename: true,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'work/renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename entry'));
    await tester.pumpAndSettle();

    expect(repository.movedFrom.last, 'work/first');
    expect(repository.movedTo.last, 'work/renamed');

    await _openManageSurface(
      tester,
      (context) => showFocusedDeleteEntrySheet(
        context: context,
        entry: repository.entries.first,
        repository: repository,
      ),
    );
    expect(find.text('Path: work/first'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();

    expect(find.text('Type First Entry to confirm'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'work/first');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();
    expect(repository.deletedPaths, isEmpty);
    expect(find.text('Type First Entry to confirm'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'First Entry');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();

    expect(repository.deletedPaths, <String>['work/first']);
  });

  testWidgets('manage batch operations use selected entries', (tester) async {
    final repository = _ManageVaultRepository();

    final selected = repository.entries
        .where((entry) => !entry.isDirectory)
        .toList(growable: false);
    await _openManageSurface(
      tester,
      (context) => showBatchMoveEntriesSurface(
        context: context,
        entries: selected,
        repository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'archive');
    await tester.tap(find.widgetWithText(FilledButton, 'Move selected'));
    await tester.pumpAndSettle();

    expect(repository.batchMoveDestinations, <String>['archive']);
    expect(repository.batchMovePaths.single, <String>[
      'work/first',
      'work/second',
    ]);

    await _openManageSurface(
      tester,
      (context) => showBatchRenameEntriesSurface(
        context: context,
        entries: selected,
        repository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'old-');
    await tester.enterText(find.byType(TextField).at(1), '-2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename selected'));
    await tester.pumpAndSettle();

    expect(repository.batchRenamePrefixes, <String>['old-']);
    expect(repository.batchRenameSuffixes, <String>['-2026']);

    await _openManageSurface(
      tester,
      (context) => showBatchRegenerateEntriesSurface(
        context: context,
        entries: selected,
        repository: repository,
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Regenerate batch'));
    await tester.pumpAndSettle();

    expect(repository.batchRegeneratedPaths.single, <String>[
      'work/first',
      'work/second',
    ]);

    await _openManageSurface(
      tester,
      (context) => showBatchDeleteEntriesSurface(
        context: context,
        entries: selected,
        repository: repository,
      ),
    );
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

    await _openManageSurface(
      tester,
      (context) => showCreateGeneratedEntrySurface(
        context: context,
        repository: repository,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'work/conflict');
    await tester.tap(find.text('Save generated password'));
    await tester.pumpAndSettle();

    expect(
      find.text('Operation failed. Try again or open Details.'),
      findsOneWidget,
    );

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
      find.text('System Autofill'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await _tapVisible(tester, find.text('System Autofill'));
    await tester.tap(find.widgetWithText(FilledButton, 'Rebuild paths'));
    await tester.pumpAndSettle();

    expect(autofillRepository.lastRebuiltEntries, isNotEmpty);
    expect(autofillRepository.status.available, isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Read URL fields'));
    await tester.pumpAndSettle();
    expect(find.text('Read encrypted URL fields?'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read selected entries'));
    await tester.pumpAndSettle();
    expect(autofillRepository.lastEnrichedPaths, hasLength(1));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Setup'));
    await tester.pumpAndSettle();
    expect(autofillRepository.operations, contains('open-settings'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
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
    expect(repository.keyActions, contains('prepare:PGP-BACKUP'));
    expect(find.text(_settingsPrimaryPgpKey.name), findsNothing);
    expect(find.text('pgp-passphrase'), findsNothing);
  });

  testWidgets('settings does not persist an unvalidated PGP passphrase', (
    tester,
  ) async {
    final repository = _KeyManagementSettingsRepository(failPreparation: true);
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
    await tester.enterText(find.byType(TextField).last, 'incorrect');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await securityRepository.readPgpPassphrase(), isNull);
    expect(securityRepository.hasStoredPgpPassphrase, isFalse);
    expect(repository.keyActions, contains('prepare:PGP-BACKUP'));
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
    await _openSettingsTile(tester, 'Git sync and remotes');
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

    await tester.scrollUntilVisible(
      find.text('origin'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
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

    expect(find.text('Delete local repo'), findsNothing);
  });

  testWidgets(
    'settings offers explicit Git initialization for local-only store',
    (tester) async {
      final repository = _GitSettingsRepository(
        status: RepoGitStatus.disabled,
        mode: StoreGitMode.disabled,
      );

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
      await _openSettingsTile(tester, 'Git sync and remotes');
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Initialize Git'),
        findsOneWidget,
      );
      expect(find.text('List remotes'), findsNothing);
      expect(find.text('Add remote'), findsNothing);
      expect(find.text('SSH keys'), findsNothing);
      await tester.tap(find.text('Initialize Git'));
      await tester.pumpAndSettle();
      expect(repository.gitCalls, contains('init'));
      expect(find.text('git init'), findsOneWidget);
    },
  );

  testWidgets('settings disables remote actions for local Git', (tester) async {
    final repository = _GitSettingsRepository(mode: StoreGitMode.local);
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
    await _openSettingsTile(tester, 'Git sync and remotes');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Pull'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Push'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Commit'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('invalid Git hides remote mutation controls', (tester) async {
    final repository = _GitSettingsRepository(
      status: RepoGitStatus.invalid,
      mode: StoreGitMode.invalid,
    );
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
    await _openSettingsTile(tester, 'Git sync and remotes');
    await tester.pumpAndSettle();
    expect(find.text('Git metadata is invalid'), findsWidgets);
    expect(find.text('List remotes'), findsNothing);
    expect(find.text('Add remote'), findsNothing);
    expect(find.text('SSH keys'), findsNothing);
  });

  testWidgets('SSH management appears only for configured SSH URLs', (
    tester,
  ) async {
    for (final remoteUrl in <String>[
      'https://example.com/pass.git',
      'git@example.com:org/pass.git',
    ]) {
      final repository = _GitSettingsRepository(remoteUrl: remoteUrl);
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
      await _openSettingsTile(tester, 'Git sync and remotes');
      await tester.pumpAndSettle();
      expect(
        find.text('SSH key required for this remote'),
        remoteUrl.startsWith('https://') ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Git and SSH sheet remains usable at 200 percent text scale', (
    tester,
  ) async {
    final repository = _GitSettingsRepository(
      remoteUrl: 'https://example.com/pass.git',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
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
    await _openSettingsTile(tester, 'Git sync and remotes');
    await tester.pumpAndSettle();
    expect(find.text('SSH keys'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Remote URL'),
      'git@example.com:org/pass.git',
    );
    await tester.pumpAndSettle();
    expect(find.text('SSH keys'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('SSH keys')).label,
      contains('SSH keys'),
    );
    await tester.scrollUntilVisible(
      find.text('SSH keys'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('SSH keys'));
    await tester.pumpAndSettle();
    expect(find.text('Generate SSH key'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(
      find.text('Operation failed. Try again or open Details.'),
      findsOneWidget,
    );
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

Future<void> _openManageSurface(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) showSurface,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder:
            (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  final result = await showSurface(context);
                  if (!context.mounted || result == null) return;
                  final summary = switch (result) {
                    EntryOperationResult(:final summary) => summary,
                    BatchOperationResult(:final summary) => summary,
                    _ => result.toString(),
                  };
                  AppNotification.show(context, summary);
                },
                child: const Text('Open workflow'),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('Open workflow'));
  await tester.pumpAndSettle();
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
  for (var i = 0; i < 12; i += 1) {
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
    if (find.text('Review setup').evaluate().isNotEmpty &&
        find.text('Finish setup').evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
      await tester.pumpAndSettle();
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
  fail(
    'Onboarding did not reach the vault. Visible text: '
    '${tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).whereType<String>().join(' | ')}',
  );
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

Future<void> _openSettingsTile(WidgetTester tester, String label) async {
  final tile = find.text(label);
  await tester.scrollUntilVisible(
    tile,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.drag(find.byType(Scrollable).last, const Offset(0, 100));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(of: tile, matching: find.byType(ListTile)).last,
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
    find.text('Advanced Git args'),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -260));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Advanced Git args'));
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
    onboardingState: StoreOnboardingState.ready,
    issues: <String>[],
    store: StoreStatus(
      name: 'Example Store',
      root: '/tmp/example-store',
      exists: true,
      hasGpgId: true,
      pgpKeyMissing: false,
      issues: <String>[],
    ),
  );

  @override
  StoreStatus? get store => lifecycle.store;

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
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool initializeGit,
  }) async {}

  @override
  Future<void> importLocalStore({required String root}) async {}

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
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
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async =>
      PgpPrivateKeyPreparation(fingerprint: fingerprint, migrated: false);

  @override
  Future<void> initializeStoreRecipients(List<String> fingerprints) async {}

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
    List<KeyRecord> additionalKeys = const <KeyRecord>[],
    this.failPreparation = false,
  }) : _keys = <KeyRecord>[
         _settingsPrimaryPgpKey,
         _settingsBackupPgpKey,
         _settingsSshKey,
         ...additionalKeys,
       ];

  final List<KeyRecord> _keys;
  final bool failPreparation;
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
  StoreStatus? get store => const StoreStatus(
    name: 'Example Store',
    root: '/tmp/example-store',
    exists: true,
    hasGpgId: true,
    pgpRecipients: <String>['PGP-BACKUP'],
    pgpKeyMissing: false,
    issues: <String>[],
    gitMode: StoreGitMode.remote,
  );

  @override
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async {
    keyActions.add('prepare:$fingerprint');
    if (failPreparation) throw StateError('Incorrect passphrase');
    return PgpPrivateKeyPreparation(fingerprint: fingerprint, migrated: false);
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
    return PgpImportResult(
      key: _settingsBackupPgpKey,
      inspection: pgpInspection,
    );
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
  Future<void> deleteSshKey(String name) async {
    deleteActions.add('ssh:$name');
    _keys.removeWhere(
      (key) => key.type == KeyRecordType.ssh && key.name == name,
    );
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
  Future<ManagedStoreImportTransaction?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
    required ManagedStoreGitDecisionResolver resolveMissingGit,
  }) async {
    managedImportDestinationBaseDirectories.add(destinationBaseDirectory);
    final path = _next(_managedImportResults);
    return path == null
        ? null
        : ManagedStoreImportTransaction(
          root: path,
          commit: () async {},
          rollback: () async {},
        );
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
        store: null,
      );
    }
    const store = StoreStatus(
      name: 'Onboarding Store',
      root: '/tmp/pass',
      exists: true,
      hasGpgId: true,
      pgpKeyMissing: false,
      issues: <String>[],
    );
    return const StoreLifecycleSnapshot(
      configPath: '/tmp/pars_config.toml',
      configExists: true,
      onboardingState: StoreOnboardingState.ready,
      issues: <String>[],
      store: store,
    );
  }

  @override
  StoreStatus? get store => lifecycle.store;

  @override
  List<KeyRecord> get keys => List<KeyRecord>.unmodifiable(_keys);

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool initializeGit,
  }) async {
    storeActions.add(
      'create:$name:$root:${pgpKeys.join(',')}:git:$initializeGit',
    );
    storeReady = true;
  }

  @override
  Future<void> importLocalStore({required String root}) async {
    storeActions.add('import:$root');
    storeReady = true;
  }

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
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
      onboardingState: StoreOnboardingState.gitInvalid,
      issues: <String>['git_remote_missing', 'pgp_key_missing'],
      store: StoreStatus(
        name: 'existing-store',
        root: '/app/support/stores/existing-store',
        exists: true,
        hasGpgId: true,
        pgpKeyMissing: true,
        issues: <String>['git_remote_missing', 'pgp_key_missing'],
      ),
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

const _mutableAppStore = StoreStatus(
  name: 'Personal',
  root: '/app/support/stores/personal',
  exists: true,
  hasGpgId: true,
  pgpRecipients: <String>[_testPgpFingerprint],
  pgpKeyMissing: false,
  issues: <String>[],
  gitMode: StoreGitMode.disabled,
);

class _MutableAppStoreRepository extends FakeParsRepository
    implements AppManagedPathRepository, StoreLifecycleChangeSource {
  _MutableAppStoreRepository({
    this.failDelete = false,
    StoreStatus? initialStore = _mutableAppStore,
  }) : _store = initialStore;

  final bool failDelete;
  StoreStatus? _store;
  bool _removing = false;
  int deleteAttempts = 0;

  @override
  final ValueNotifier<int> lifecycleRevision = ValueNotifier<int>(0);

  @override
  bool get storeRemovalInProgress => _removing;

  void beginRemovalForTest() {
    _removing = true;
    lifecycleRevision.value += 1;
  }

  void cancelRemovalForTest() {
    _removing = false;
    lifecycleRevision.value += 1;
  }

  @override
  StoreStatus? get store => _store;

  @override
  StoreLifecycleSnapshot get lifecycle => StoreLifecycleSnapshot(
    configPath: '/app/support/pars_config.toml',
    configExists: true,
    onboardingState:
        _store == null
            ? StoreOnboardingState.storeMissing
            : StoreOnboardingState.ready,
    issues: _store == null ? const <String>['store_missing'] : const <String>[],
    store: _store,
  );

  @override
  Future<void> removeStore({required String root}) async {
    _store = null;
    lifecycleRevision.value += 1;
  }

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {
    deleteAttempts += 1;
    if (failDelete) throw StateError('physical delete failed');
    _store = null;
    lifecycleRevision.value += 1;
  }

  @override
  bool get usesAppManagedPaths => true;

  @override
  bool isAppManagedStoreRoot(String root) =>
      root.startsWith('/app/support/stores/');

  @override
  String storeRootForName(String name) => '/app/support/stores/$name';

  @override
  String storeRootForRemote(String remoteUrl) => '/app/support/stores/clone';
}

class _GitSettingsRepository extends _InjectedRepository
    implements GitOperationsRepository {
  _GitSettingsRepository({
    this.failAdvancedArgs = false,
    this.status = RepoGitStatus.uncommitted,
    this.mode = StoreGitMode.remote,
    this.remoteUrl = 'git@example.com:org/pass.git',
  });

  final bool failAdvancedArgs;
  final RepoGitStatus status;
  final StoreGitMode mode;
  final String remoteUrl;

  @override
  StoreGitMode get gitMode => mode;

  @override
  StoreLifecycleSnapshot get lifecycle => StoreLifecycleSnapshot(
    configPath: '/tmp/example-config.toml',
    configExists: true,
    onboardingState: StoreOnboardingState.ready,
    issues: const <String>[],
    store: StoreStatus(
      name: 'Example Store',
      root: '/tmp/example-store',
      exists: true,
      hasGpgId: true,
      pgpKeyMissing: false,
      issues: const <String>[],
      gitMode: mode,
    ),
  );
  final List<String> gitCalls = <String>[];

  @override
  RepoGitStatus get gitStatus => status;

  @override
  Future<GitOperationResult> initializeRepository() async {
    gitCalls.add('init');
    return const GitOperationResult(
      command: 'git init',
      stdout: 'Initialized.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

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
    return <GitRemote>[
      GitRemote(name: 'origin', fetchUrl: remoteUrl, pushUrl: remoteUrl),
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
    store: null,
  );

  @override
  StoreStatus? get store => lifecycle.store;

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
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool initializeGit,
  }) async {}

  @override
  Future<void> importLocalStore({required String root}) async {}

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
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
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async => throw UnimplementedError();

  @override
  Future<void> initializeStoreRecipients(List<String> fingerprints) async =>
      throw UnimplementedError();

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
