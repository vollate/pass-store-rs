import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/pgp_key_import.dart';
import 'package:pars_gui/screens/onboarding/onboarding_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/key_repository.dart';
import 'package:pars_gui/services/path_picker_service.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/settings_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets(
    'onboarding uses required progress instead of disabled chip rail',
    (tester) async {
      await configureGuiTestViewport(tester);
      await tester.pumpWidget(ParsGuiApp.fake());
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Step '), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expectNoFlutterOverflow(tester);
    },
  );

  testWidgets('biometrics is visibly optional and deferrable', (tester) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    final security = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
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
    await tester.pumpAndSettle();

    expect(find.text('Enable biometric unlock'), findsWidgets);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.text('Skip biometrics'), findsOneWidget);
  });

  testWidgets('store-first setup makes import and clone primary', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up password store'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Import local store'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Clone Git store'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Create local store'),
      findsOneWidget,
    );
    expect(find.text('Choose PGP key'), findsNothing);
    expect(find.text('Set up SSH for GitHub'), findsNothing);
    expect(find.text('Review setup'), findsNothing);
  });

  testWidgets('HTTPS clone does not request SSH while SSH clone does', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository(keysOverride: const <KeyRecord>[]);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Clone Git store'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/pass.git',
    );
    await tester.pump();
    expect(find.text('SSH key required for this remote'), findsNothing);

    await tester.enterText(
      find.byType(TextField).first,
      'git@example.com:pass.git',
    );
    await tester.pump();
    expect(find.text('SSH key required for this remote'), findsOneWidget);
    expect(find.text('Generate SSH key'), findsOneWidget);
    expect(find.text('Import SSH key'), findsOneWidget);
    await tester.tap(find.text('Generate SSH key'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Generate SSH key').last,
    );
    await tester.pumpAndSettle();
    expect(find.text('SSH key required for this remote'), findsNothing);
  });

  testWidgets('repair exposes only matching private PGP keys', (tester) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository(
      storeOverride: const StoreStatus(
        name: 'Imported',
        root: '/tmp/imported',
        exists: true,
        hasGpgId: true,
        pgpRecipients: <String>['MATCH-ABC'],
        pgpKeyMissing: true,
        issues: <String>['pgp_key_missing'],
        gitMode: StoreGitMode.disabled,
      ),
      keysOverride: const <KeyRecord>[
        KeyRecord(
          type: KeyRecordType.pgp,
          name: 'Matching',
          fingerprint: '0000 MATCH-ABC',
          source: 'Imported private key',
          hasPrivateKey: true,
        ),
        KeyRecord(
          type: KeyRecordType.pgp,
          name: 'Unrelated',
          fingerprint: 'UNRELATED',
          source: 'Imported private key',
          hasPrivateKey: true,
        ),
        KeyRecord(
          type: KeyRecordType.pgp,
          name: 'Public only',
          fingerprint: 'MATCH-ABC',
          source: 'Imported public key',
          hasPrivateKey: false,
        ),
      ],
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
            onboardingComplete: true,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair password store'), findsOneWidget);
    expect(find.text('Matching'), findsOneWidget);
    expect(find.text('Unrelated'), findsNothing);
    expect(find.text('Public only'), findsNothing);
    expect(find.text('Create PGP key'), findsNothing);
    expect(find.text('Import PGP key'), findsOneWidget);
  });

  testWidgets('missing .gpg-id offers contextual recipient creation', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository(
      storeOverride: const StoreStatus(
        name: 'Imported',
        root: '/tmp/imported',
        exists: true,
        hasGpgId: false,
        pgpKeyMissing: false,
        issues: <String>['missing_gpg_id'],
        gitMode: StoreGitMode.disabled,
      ),
    );
    var completed = false;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () => completed = true,
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            onboardingComplete: true,
            biometricUnlockEnabled: true,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Encryption recipients are missing'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pump();
    expect(find.text('Create PGP key'), findsOneWidget);
    expect(find.text('Import PGP key'), findsOneWidget);
    await tester.tap(find.text('Use PGP key').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(completed, isTrue);
    expect(repository.actions.single, startsWith('recipients:'));
  });

  testWidgets('invalid external Git requires explicit disconnect', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository(
      storeOverride: const StoreStatus(
        name: 'Broken',
        root: '/tmp/broken',
        exists: true,
        hasGpgId: true,
        pgpRecipients: <String>['ABCD'],
        pgpKeyMissing: false,
        issues: <String>['git_invalid'],
        gitMode: StoreGitMode.invalid,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            onboardingComplete: true,
            biometricUnlockEnabled: true,
            lastUnlockedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect password store'));
    await tester.pumpAndSettle();
    expect(repository.actions, contains('disconnect:/tmp/broken'));
  });

  testWidgets('invalid managed Git requires typed deletion confirmation', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _ManagedOnboardingRepository(
      storeOverride: const StoreStatus(
        name: 'Broken',
        root: '/app/support/stores/broken',
        exists: true,
        hasGpgId: true,
        pgpRecipients: <String>['ABCD'],
        pgpKeyMissing: false,
        issues: <String>['git_invalid'],
        gitMode: StoreGitMode.invalid,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            onboardingComplete: true,
            biometricUnlockEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete app copy'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester.getSemantics(find.text('Delete app copy')).label,
      contains('Delete app copy'),
    );
    await tester.tap(find.text('Delete app copy'));
    await tester.pumpAndSettle();
    final confirmation = find.byKey(const Key('repair-delete-confirmation'));
    final deleteButton = find.widgetWithText(FilledButton, 'Delete');
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
    await tester.enterText(confirmation, 'wrong');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
    await tester.enterText(confirmation, 'broken');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);
    expectNoFlutterOverflow(tester);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(
      repository.actions,
      contains('delete:/app/support/stores/broken:broken'),
    );
  });

  testWidgets('ready lifecycle completes without a false repair step', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository(
      storeOverride: const StoreStatus(
        name: 'Ready',
        root: '/tmp/ready',
        exists: true,
        hasGpgId: true,
        pgpRecipients: <String>['ABCD'],
        pgpKeyMissing: false,
        issues: <String>[],
        gitMode: StoreGitMode.disabled,
      ),
    );
    var completed = false;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () => completed = true,
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            onboardingComplete: false,
            biometricUnlockEnabled: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(completed, isTrue);
  });

  testWidgets(
    'contextual import rejects unrelated protected material before mutation',
    (tester) async {
      await configureGuiTestViewport(tester);
      final repository = _OnboardingRepository(
        storeOverride: const StoreStatus(
          name: 'Imported',
          root: '/tmp/imported',
          exists: true,
          hasGpgId: true,
          pgpRecipients: <String>['MATCH-ABC'],
          pgpKeyMissing: true,
          issues: <String>['pgp_key_missing'],
          gitMode: StoreGitMode.disabled,
        ),
        inspectionOverride: const PgpKeyInspection(
          kind: PgpKeyKind.private,
          fingerprint: 'UNRELATED',
          identity: 'Other <other@example.com>',
          hasPrivateKey: true,
          requiresPassphrase: true,
          armored: true,
        ),
      );
      final security = InMemorySecurityRepository.withPattern(
        const <int>[0, 1, 2, 5],
        onboardingComplete: true,
        biometricUnlockEnabled: true,
        pgpPassphraseStorageEnabled: true,
        pgpPassphrase: const PgpPassphraseCache(
          fingerprint: 'MATCH-ABC',
          passphrase: 'existing',
        ),
        activePgpPassphrase: const PgpPassphraseCache(
          fingerprint: 'MATCH-ABC',
          passphrase: 'existing',
        ),
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: OnboardingScreen(
            onComplete: () {},
            settingsRepository: repository,
            keyRepository: repository,
            securityRepository: security,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import PGP key'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'protected material');
      await tester.pump();
      final importButton = find.widgetWithText(FilledButton, 'Import').last;
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('does not match'), findsOneWidget);
      expect(find.text('Remember in Keychain'), findsNothing);
      expect(repository.pgpImportCalls, 0);
      expect(
        (await security.readActivePgpPassphrase())?.fingerprint,
        'MATCH-ABC',
      );
      expect((await security.readPgpPassphrase())?.fingerprint, 'MATCH-ABC');
    },
  );

  testWidgets('contextual import rejects public material before mutation', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _OnboardingRepository(
      storeOverride: const StoreStatus(
        name: 'Imported',
        root: '/tmp/imported',
        exists: true,
        hasGpgId: true,
        pgpRecipients: <String>['MATCH-ABC'],
        pgpKeyMissing: true,
        issues: <String>['pgp_key_missing'],
        gitMode: StoreGitMode.disabled,
      ),
      inspectionOverride: const PgpKeyInspection(
        kind: PgpKeyKind.public,
        fingerprint: 'MATCH-ABC',
        identity: 'Matching',
        hasPrivateKey: false,
        requiresPassphrase: false,
        armored: true,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            onboardingComplete: true,
            biometricUnlockEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import PGP key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'public material');
    await tester.pump();
    final importButton = find.widgetWithText(FilledButton, 'Import').last;
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('matching private PGP key'), findsOneWidget);
    expect(repository.pgpImportCalls, 0);
  });

  for (final branch in <String>['create', 'import', 'clone']) {
    testWidgets('store-first onboarding completes $branch branch', (
      tester,
    ) async {
      await configureGuiTestViewport(tester);
      final repository = _OnboardingRepository();
      final picker = _FolderPicker(<String>['/tmp', '/tmp/imported', '/tmp']);
      var completed = false;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: OnboardingScreen(
            onComplete: () => completed = true,
            settingsRepository: repository,
            keyRepository: repository,
            pathPickerService: picker,
            securityRepository: InMemorySecurityRepository.withPattern(
              const <int>[0, 1, 2, 5],
              biometricUnlockEnabled: true,
              lastUnlockedAt: DateTime.now(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      switch (branch) {
        case 'create':
          await tester.tap(find.text('Create local store'));
          await tester.pumpAndSettle();
          expect(find.text('Choose PGP key'), findsOneWidget);
          await tester.tap(find.text('Use PGP key').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Create local store'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Choose'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Create').last);
          break;
        case 'import':
          await tester.tap(find.text('Import local store'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Choose'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Import').last);
          break;
        case 'clone':
          await tester.tap(find.text('Clone Git store'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).first,
            'https://example.com/pass.git',
          );
          await tester.tap(find.widgetWithText(TextButton, 'Choose'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Clone').last);
          break;
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(completed, isTrue);
      expect(repository.actions.single, startsWith(branch));
      expect(find.text('Review setup'), findsNothing);
    });
  }

  testWidgets(
    'store-source actions remain semantic at 200 percent text scale',
    (tester) async {
      await configureGuiTestViewport(tester);
      final repository = _OnboardingRepository();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          textScale: 2,
          child: OnboardingScreen(
            onComplete: () {},
            settingsRepository: repository,
            keyRepository: repository,
            securityRepository: InMemorySecurityRepository.withPattern(
              const <int>[0, 1, 2, 5],
              biometricUnlockEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final storeScrollable =
          find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first;
      for (final label in <String>[
        'Import local store',
        'Clone Git store',
        'Create local store',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          160,
          scrollable: storeScrollable,
        );
        expect(find.text(label), findsOneWidget);
        expect(tester.getSemantics(find.text(label)).label, contains(label));
      }
      final createButton = find.widgetWithText(
        OutlinedButton,
        'Create local store',
      );
      expect(createButton, findsOneWidget);
      await tester.tap(createButton);
      await tester.pumpAndSettle();
      final openedRecipientStep =
          find.text('Choose PGP key').evaluate().isNotEmpty;
      final openedCreateForm =
          find.widgetWithText(FilledButton, 'Create').evaluate().isNotEmpty;
      expect(openedRecipientStep || openedCreateForm, isTrue);
      expectNoFlutterOverflow(tester);
    },
  );

  testWidgets('missing Git decision remains usable at 200 percent text scale', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _ManagedOnboardingRepository(storeOverride: null);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          pathPickerService: _MissingGitPicker(),
          securityRepository: InMemorySecurityRepository.withPattern(
            const <int>[0, 1, 2, 5],
            biometricUnlockEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Import local store'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Import local store'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Choose folder and import'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Choose folder and import'));
    await tester.pumpAndSettle();
    expect(find.text('Git metadata not found'), findsOneWidget);
    expect(find.text('Initialize Git'), findsOneWidget);
    expect(find.text('Continue without Git'), findsOneWidget);
    expectNoFlutterOverflow(tester);
    await tester.tap(find.text('Continue without Git'));
    await tester.pumpAndSettle();
  });

  testWidgets('onboarding remains usable at 200 percent text scale', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set gesture lock'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });
}

class _OnboardingRepository extends FakeParsRepository {
  _OnboardingRepository({
    StoreStatus? storeOverride,
    this.keysOverride,
    this.inspectionOverride,
  }) : _store = storeOverride;

  StoreStatus? _store;
  final List<KeyRecord>? keysOverride;
  final PgpKeyInspection? inspectionOverride;
  final List<KeyRecord> _additionalKeys = <KeyRecord>[];
  final List<String> actions = <String>[];
  int pgpImportCalls = 0;

  @override
  Future<void> removeStore({required String root}) async {
    actions.add('disconnect:$root');
    _store = null;
  }

  @override
  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  }) async {
    actions.add('delete:$root:$confirmation');
    _store = null;
  }

  @override
  StoreStatus? get store => _store;

  @override
  StoreLifecycleSnapshot get lifecycle => StoreLifecycleSnapshot(
    configPath: '/tmp/config.toml',
    configExists: _store != null,
    onboardingState:
        _store == null
            ? StoreOnboardingState.noConfig
            : _store!.pgpKeyMissing
            ? StoreOnboardingState.pgpKeyMissing
            : StoreOnboardingState.ready,
    issues: _store?.issues ?? const <String>['no_config'],
    store: _store,
  );

  @override
  List<KeyRecord> get keys => <KeyRecord>[
    ...(keysOverride ?? super.keys),
    ..._additionalKeys,
  ];

  @override
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async =>
      inspectionOverride ?? super.inspectPgpKeyText(armoredText);

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async =>
      inspectionOverride ?? super.inspectPgpKeyFile(path);

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async {
    pgpImportCalls += 1;
    return super.importPgpKeyText(armoredText, passphrase: passphrase);
  }

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async {
    pgpImportCalls += 1;
    return super.importPgpKeyFile(path, passphrase: passphrase);
  }

  @override
  Future<KeyRecord> generateSshKey(String name) async {
    final key = KeyRecord(
      type: KeyRecordType.ssh,
      name: name,
      fingerprint: 'SHA256:test',
      source: 'Generated in test',
      hasPrivateKey: true,
    );
    _additionalKeys.add(key);
    return key;
  }

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) => generateSshKey(name);

  @override
  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool initializeGit,
  }) async {
    actions.add('create:$root:${pgpKeys.join(',')}');
    _setReady(
      root,
      gitMode: initializeGit ? StoreGitMode.local : StoreGitMode.disabled,
    );
  }

  @override
  Future<void> importLocalStore({required String root}) async {
    actions.add('import:$root');
    _setReady(root);
  }

  @override
  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
  }) async {
    actions.add('clone:$remoteUrl:$root');
    _setReady(root, gitMode: StoreGitMode.remote);
  }

  @override
  Future<void> initializeStoreRecipients(List<String> fingerprints) async {
    actions.add('recipients:${fingerprints.join(',')}');
    _setReady(_store!.root, gitMode: _store!.gitMode);
  }

  void _setReady(String root, {StoreGitMode gitMode = StoreGitMode.disabled}) {
    _store = StoreStatus(
      name: 'Ready',
      root: root,
      exists: true,
      hasGpgId: true,
      pgpRecipients: const <String>['ABCD'],
      pgpKeyMissing: false,
      issues: const <String>[],
      gitMode: gitMode,
    );
  }
}

class _ManagedOnboardingRepository extends _OnboardingRepository
    implements AppManagedPathRepository {
  _ManagedOnboardingRepository({required super.storeOverride});

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

class _MissingGitPicker implements PathPickerService {
  @override
  Future<ManagedStoreImportTransaction?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
    required ManagedStoreGitDecisionResolver resolveMissingGit,
  }) async {
    await resolveMissingGit(ManagedStoreGitState.absent);
    return null;
  }

  @override
  Future<String?> pickFile({required String initialDirectory}) async => null;

  @override
  Future<String?> pickFolder({required String initialDirectory}) async => null;
}

class _FolderPicker implements PathPickerService {
  _FolderPicker(this.paths);

  final List<String> paths;
  var _index = 0;

  @override
  Future<String?> pickFolder({required String initialDirectory}) async =>
      paths[_index++];

  @override
  Future<String?> pickFile({required String initialDirectory}) async => null;

  @override
  Future<ManagedStoreImportTransaction?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
    required ManagedStoreGitDecisionResolver resolveMissingGit,
  }) async => null;
}
