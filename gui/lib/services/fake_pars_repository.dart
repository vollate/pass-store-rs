import '../models/key_record.dart';
import '../models/password_entry.dart';
import 'git_repository.dart';
import 'key_repository.dart';
import 'settings_repository.dart';
import 'store_lifecycle.dart';
import 'vault_repository.dart';

class FakeParsRepository
    implements
        VaultRepository,
        SettingsRepository,
        KeyRepository,
        GitRepository {
  const FakeParsRepository();

  static const StoreStatus _store = StoreStatus(
    id: 'fake-store',
    name: '~/.password-store',
    root: '~/.password-store',
    isDefault: true,
    exists: true,
    hasGpgId: true,
    hasGitRemote: true,
    pgpKeyMissing: false,
    issues: <String>[],
  );

  @override
  StoreLifecycleSnapshot get lifecycle => const StoreLifecycleSnapshot(
    configPath: '~/.config/pars/pars_config.toml',
    configExists: true,
    selectedStoreId: 'fake-store',
    selectedStoreRoot: '~/.password-store',
    onboardingState: StoreOnboardingState.ready,
    issues: <String>[],
    stores: <StoreStatus>[_store],
  );

  @override
  List<StoreStatus> get stores => const <StoreStatus>[_store];

  @override
  String get currentRepoName => '~/.password-store';

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.clean;

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[
    PasswordEntry(
      path: 'work/dev/github',
      displayName: 'GitHub',
      repoName: '~/.password-store',
      encryptedContent:
          's3cret-github\nusername: Vollate\nurl: https://github.com\ncreated on desktop',
      isFavorite: true,
      lastUsedLabel: 'Today',
    ),
    PasswordEntry(
      path: 'finance/stripe',
      displayName: 'Stripe',
      repoName: '~/.password-store',
      encryptedContent:
          'stripe-passphrase\nlogin: billing@example.com\nwebsite: https://dashboard.stripe.com',
      lastUsedLabel: 'Yesterday',
    ),
    PasswordEntry(
      path: 'infra/prod/root',
      displayName: 'Root server',
      repoName: '~/.password-store',
      encryptedContent: 'root-server-password\nssh jump host\nrotate manually',
    ),
    PasswordEntry(
      path: 'work',
      displayName: 'work',
      repoName: '~/.password-store',
      encryptedContent: '',
      isDirectory: true,
      childCount: 8,
    ),
    PasswordEntry(
      path: 'finance',
      displayName: 'finance',
      repoName: '~/.password-store',
      encryptedContent: '',
      isDirectory: true,
      childCount: 5,
    ),
  ];

  @override
  List<KeyRecord> get keys => const <KeyRecord>[
    KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Vollate <me@example.com>',
      fingerprint: '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF',
      source: 'Generated on device',
      hasPrivateKey: true,
    ),
    KeyRecord(
      type: KeyRecordType.ssh,
      name: 'github-mobile-ed25519',
      fingerprint: 'SHA256:4m0ckedGitHubSshKeyFingerprint',
      source: 'Imported from text',
      hasPrivateKey: true,
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
        .where(
          (entry) =>
              entry.displayName.toLowerCase().contains(normalized) ||
              entry.path.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

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
  }) async => keys.firstWhere((key) => key.type == KeyRecordType.pgp);

  @override
  Future<KeyRecord> importPgpPublicKeyText(String armoredText) async =>
      keys.firstWhere((key) => key.type == KeyRecordType.pgp);

  @override
  Future<KeyRecord> importPgpPrivateKeyText(String armoredText) async =>
      keys.firstWhere((key) => key.type == KeyRecordType.pgp);

  @override
  Future<KeyRecord> importPgpPrivateKeyFile(String path) async =>
      keys.firstWhere((key) => key.type == KeyRecordType.pgp);

  @override
  Future<String> exportPgpPublicKey(String fingerprint) async =>
      '-----BEGIN PGP PUBLIC KEY BLOCK-----\n...\n-----END PGP PUBLIC KEY BLOCK-----';

  @override
  Future<String> exportPgpPrivateKey({
    required String fingerprint,
    required String confirmation,
  }) async =>
      '-----BEGIN PGP PRIVATE KEY BLOCK-----\n...\n-----END PGP PRIVATE KEY BLOCK-----';

  @override
  Future<void> addPgpKeyToSelectedStore(String fingerprint) async {}

  @override
  Future<KeyRecord> generateSshKey(String name) async =>
      keys.firstWhere((key) => key.type == KeyRecordType.ssh);

  @override
  Future<KeyRecord> importSshPrivateKeyText({
    required String name,
    required String privateKey,
  }) async => keys.firstWhere((key) => key.type == KeyRecordType.ssh);

  @override
  Future<KeyRecord> importSshPrivateKeyFile({
    required String name,
    required String path,
  }) async => keys.firstWhere((key) => key.type == KeyRecordType.ssh);

  @override
  Future<String> exportSshPublicKey(String name) async =>
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKey';

  @override
  Future<String> exportSshPrivateKey({
    required String name,
    required String confirmation,
  }) async =>
      '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----';

  @override
  Future<Uri> githubSshSettingsUri() async =>
      Uri.parse('https://github.com/settings/keys');
}
