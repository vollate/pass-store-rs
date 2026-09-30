import '../models/git_sync.dart';
import '../models/key_record.dart';
import '../models/password_entry.dart';
import '../models/pgp_key_import.dart';
import 'git_repository.dart';
import 'key_repository.dart';
import 'pass_entry_parser.dart';
import 'runtime_diagnostics.dart';
import 'security_repository.dart';
import 'settings_repository.dart';
import 'store_lifecycle.dart';
import 'vault_repository.dart';

class FakeParsRepository
    implements
        ManageRepository,
        SettingsRepository,
        KeyRepository,
        RuntimeDiagnosticsRepository,
        GitOperationsRepository {
  const FakeParsRepository();

  static const StoreStatus _store = StoreStatus(
    name: '~/.password-store',
    root: '~/.password-store',
    exists: true,
    hasGpgId: true,
    pgpRecipients: <String>[
      '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF',
    ],
    pgpKeyMissing: false,
    issues: <String>[],
  );

  @override
  StoreLifecycleSnapshot get lifecycle => const StoreLifecycleSnapshot(
    configPath: '~/.config/pars/pars_config.toml',
    configExists: true,
    onboardingState: StoreOnboardingState.ready,
    issues: <String>[],
    store: _store,
  );

  @override
  StoreStatus? get store => _store;

  @override
  String get currentRepoName => '~/.password-store';

  @override
  RepoGitStatus get gitStatus => RepoGitStatus.clean;

  @override
  StoreGitMode get gitMode => StoreGitMode.remote;

  @override
  RuntimeDiagnostics runtimeDiagnostics(SecurityRepository securityRepository) {
    return RuntimeDiagnostics(
      bridgeLoaded: true,
      coreVersion: 'pars-core 0.2.5',
      pgpBackend: 'Mock system GPG',
      gitBackend: 'Mock git command',
      keyStorageBackend: keyStorageBackendLabel(securityRepository),
      nativeLibrary: 'mock pars_bridge',
    );
  }

  @override
  Future<GitOperationResult> initializeRepository() async {
    return const GitOperationResult(
      command: 'git init',
      stdout: 'Initialized an empty Git repository.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> refreshGitStatus() async {
    return const GitOperationResult(
      command: 'git status --short --branch',
      stdout: '## main\n',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> pull() async {
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
    return const GitOperationResult(
      command: 'git push',
      stdout: 'Pushed main.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> commit(String message) async {
    return GitOperationResult(
      command: 'git commit -m "$message"',
      stdout: 'Committed',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<GitOperationResult> runCommandLine(String commandLine) async {
    return GitOperationResult(
      command: 'git ${commandLine.trim()}',
      stdout:
          commandLine.trim() == 'remote -v'
              ? 'origin\tgit@example.com:org/pass.git (fetch)\norigin\tgit@example.com:org/pass.git (push)\n'
              : 'ok',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  static const GitStatusSummary _cleanSummary = GitStatusSummary(
    branch: 'main',
    upstream: 'origin/main',
    ahead: 0,
    behind: 0,
    changed: 0,
    conflicted: 0,
    operation: GitOperationState.none,
    lastFetchedAt: null,
  );

  @override
  GitStatusSummary? get statusSummary => _cleanSummary;

  @override
  GitSyncConflict? get lastConflict => null;

  @override
  bool get lastRemoteCheckFailed => false;

  @override
  GitPreferences get preferences => const GitPreferences();

  @override
  Future<void> updatePreferences(GitPreferences preferences) async {}

  @override
  Future<void> checkRemoteOnLaunch() async {}

  @override
  Future<GitSyncOutcome> sync({
    required bool commitPending,
    String message = 'Sync password store',
  }) async {
    return const GitSyncOutcome(
      committed: false,
      pulled: 0,
      pushed: false,
      blockedByChanges: false,
      conflict: null,
      summary: _cleanSummary,
    );
  }

  @override
  Future<GitResetOutcome> resetToUpstream() async {
    return const GitResetOutcome(
      committed: false,
      backupBranch: null,
      summary: _cleanSummary,
    );
  }

  @override
  Future<GitOperationResult> pushBackupBranch(String branch) async {
    return GitOperationResult(
      command: 'git push origin $branch',
      stdout: 'Pushed $branch.',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  Future<List<GitLogEntry>> history({int limit = 50}) async {
    return <GitLogEntry>[
      GitLogEntry(
        id: 'b3da0f4',
        summary: 'Edit password work/dev/github',
        author: 'Vollate',
        time: DateTime.utc(2026, 9, 28, 9, 30),
      ),
      GitLogEntry(
        id: '8c21e07',
        summary: 'Generate password personal/email',
        author: 'Vollate',
        time: DateTime.utc(2026, 9, 27, 18, 5),
      ),
    ];
  }

  @override
  Future<GitRemoteBranches> remoteBranches() async {
    return const GitRemoteBranches(
      remote: 'origin',
      current: 'main',
      branches: <String>['archive', 'main'],
    );
  }

  @override
  Future<void> switchBranch(String branch) async {}

  @override
  Future<GitIdentity?> identity() async {
    return const GitIdentity(name: 'Vollate', email: 'me@example.com');
  }

  @override
  GitIdentity? suggestedIdentity() {
    return const GitIdentity(name: 'Vollate', email: 'me@example.com');
  }

  @override
  Future<void> setIdentity({
    required String name,
    required String email,
  }) async {}

  @override
  Future<bool> hasHttpsCredentials() async => false;

  @override
  Future<void> rememberHttpsCredentials(HttpsCredentials credentials) async {}

  @override
  Future<void> forgetHttpsCredentials() async {}

  @override
  Future<void> rememberSshPassphrase(
    String passphrase, {
    required bool persist,
  }) async {}

  @override
  Future<List<GitRemote>> listRemotes() async {
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
    return GitOperationResult(
      command: 'git remote remove $name',
      stdout: '',
      stderr: '',
      exitCode: 0,
      success: true,
    );
  }

  @override
  List<PasswordEntry> get entries => const <PasswordEntry>[
    PasswordEntry(
      path: 'work/dev/github',
      displayName: 'GitHub',
      repoName: '~/.password-store',
      encryptedContent:
          's3cret-github\nusername: Vollate\nurl: https://github.com\ncreated on desktop',
    ),
    PasswordEntry(
      path: 'finance/stripe',
      displayName: 'Stripe',
      repoName: '~/.password-store',
      encryptedContent:
          'stripe-passphrase\nlogin: billing@example.com\nwebsite: https://dashboard.stripe.com',
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
  List<PasswordEntry> browseEntries(String? directoryPath) {
    final parent = directoryPath ?? currentRepoName;
    return entries
        .where((entry) => entry.parentPath == parent)
        .toList(growable: false);
  }

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    return PassEntryParser.parse(entry.encryptedContent);
  }

  @override
  Future<String> copyEntryPassword(PasswordEntry entry) async {
    return PassEntryParser.parse(entry.encryptedContent).password;
  }

  @override
  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  }) async {
    return EntryOperationResult(path: path, overwroteExisting: false);
  }

  @override
  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  }) async {
    return EntryOperationResult(path: path, overwroteExisting: false);
  }

  @override
  Future<EntryOperationResult> editEntry({
    required String path,
    required String content,
  }) async {
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
    return BatchOperationResult(
      action: 'Moved',
      affectedPaths: entries.map((entry) => entry.path).toList(growable: false),
    );
  }

  @override
  Future<BatchOperationResult> batchRenameEntries({
    required List<PasswordEntry> entries,
    required String prefix,
    required String suffix,
    required bool overwrite,
  }) async {
    return BatchOperationResult(
      action: 'Renamed',
      affectedPaths: entries.map((entry) => entry.path).toList(growable: false),
    );
  }

  @override
  Future<BatchOperationResult> batchDeleteEntries({
    required List<PasswordEntry> entries,
  }) async {
    return BatchOperationResult(
      action: 'Deleted',
      affectedPaths: entries.map((entry) => entry.path).toList(growable: false),
    );
  }

  @override
  Future<BatchOperationResult> batchRegenerateEntries({
    required List<PasswordEntry> entries,
    required int length,
    required bool noSymbols,
  }) async {
    return BatchOperationResult(
      action: 'Regenerated',
      affectedPaths: entries.map((entry) => entry.path).toList(growable: false),
    );
  }

  @override
  bool get commitsEveryChange => true;

  @override
  Future<GitOperationResult> commitChanges(String message) async {
    return GitOperationResult(
      command: 'git commit -m "$message"',
      stdout: 'Committed',
      stderr: '',
      success: true,
      exitCode: 0,
    );
  }

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
    bool overwrite = false,
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
  Future<PgpKeyInspection> inspectPgpKeyText(String armoredText) async =>
      _fakeInspection;

  @override
  Future<PgpKeyInspection> inspectPgpKeyFile(String path) async =>
      _fakeInspection;

  @override
  Future<PgpImportResult> importPgpKeyText(
    String armoredText, {
    String? passphrase,
  }) async => PgpImportResult(
    key: keys.firstWhere((key) => key.type == KeyRecordType.pgp),
    inspection: _fakeInspection,
  );

  @override
  Future<PgpImportResult> importPgpKeyFile(
    String path, {
    String? passphrase,
  }) async => PgpImportResult(
    key: keys.firstWhere((key) => key.type == KeyRecordType.pgp),
    inspection: _fakeInspection,
  );

  @override
  Future<PgpPrivateKeyPreparation> preparePgpPrivateKey({
    required String fingerprint,
    required String passphrase,
  }) async =>
      PgpPrivateKeyPreparation(fingerprint: fingerprint, migrated: false);

  @override
  Future<void> initializeStoreRecipients(List<String> fingerprints) async {}

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
  Future<void> deleteSshKey(String name) async {}

  @override
  Future<Uri> githubSshSettingsUri() async =>
      Uri.parse('https://github.com/settings/keys');
}

const PgpKeyInspection _fakeInspection = PgpKeyInspection(
  kind: PgpKeyKind.public,
  fingerprint: '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF',
  identity: 'Vollate <me@example.com>',
  hasPrivateKey: false,
  requiresPassphrase: false,
  armored: true,
);
