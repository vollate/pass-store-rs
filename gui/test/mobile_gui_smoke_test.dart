import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/git_repository.dart';
import 'package:pars_gui/services/key_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/settings_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/services/vault_repository.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';

void main() {
  testWidgets('shows onboarding before entering the vault', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.text('Draw at least 4 dots.'), findsOneWidget);
  });

  testWidgets('enters the mobile shell after onboarding', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    await _completeGestureSetup(tester);

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('vault searches entries and opens detail sheet', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeGestureSetup(tester);

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
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeGestureSetup(tester);

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
    await tester.pumpWidget(ParsGuiApp.fake());
    await _completeGestureSetup(tester);

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
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository(),
      ),
    );
    await _completeGestureSetup(tester);

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
}

Future<void> _completeGestureSetup(WidgetTester tester) async {
  await _drawGesture(tester);
  await tester.pumpAndSettle();
  expect(find.text('Gesture captured. Confirm it once more.'), findsOneWidget);
  await _drawGesture(tester);
  await tester.pumpAndSettle();
}

Future<void> _drawGesture(WidgetTester tester) async {
  final box = tester.renderObject<RenderBox>(find.byType(GestureLockInput));
  final topLeft = box.localToGlobal(Offset.zero);
  final cell = box.size.width / 3;
  Offset dot(int index) =>
      topLeft +
      Offset(cell * (index % 3) + cell / 2, cell * (index ~/ 3) + cell / 2);

  final gesture = await tester.createGesture();
  await gesture.down(dot(0));
  await tester.pump();
  await gesture.moveTo(dot(0) + Offset(cell / 4, 0));
  await tester.pump();
  await gesture.moveTo(dot(1));
  await tester.pump();
  await gesture.moveTo(dot(2));
  await tester.pump();
  await gesture.moveTo(dot(5));
  await tester.pump();
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
}
