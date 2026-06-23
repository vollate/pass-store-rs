import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/bridge/pars_bridge_api.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/bridge_backed_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';

void main() {
  test(
    'bridge-backed repository loads config stores entries and git status',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.refresh();

      expect(repository.currentRepoName, 'Personal');
      expect(repository.lifecycle.onboardingState, StoreOnboardingState.ready);
      expect(repository.gitStatus.label, 'Uncommitted');
      expect(
        repository.entries.map((entry) => entry.path),
        contains('work/github'),
      );
      expect(repository.search('git').single.displayName, 'github');
      expect(
        bridge.calledMethods,
        containsAll(<String>[
          'inspect_app_state',
          'list_keys',
          'list_entries',
          'git_status',
        ]),
      );
      expect(repository.keys.single.name, 'github-mobile');
    },
  );

  test('bridge-backed repository exposes store lifecycle operations', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.createLocalStore(
      name: 'Work',
      root: '/tmp/work-store',
      pgpKeys: const <String>['alice@example.com'],
      setDefault: true,
      initializeGit: true,
    );
    await repository.selectStore('/tmp/work-store');
    await repository.importLocalStore(
      root: '/tmp/existing-store',
      setDefault: false,
    );
    await repository.cloneStore(
      remoteUrl: 'git@example.com:org/pass.git',
      root: '/tmp/cloned-store',
      setDefault: true,
    );
    await repository.removeStore(root: '/tmp/old-store');
    await repository.deleteLocalStore(
      root: '/tmp/old-store',
      confirmation: '/tmp/old-store',
    );

    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'create_local_store',
        'select_store',
        'import_local_store',
        'clone_store',
        'remove_store',
        'delete_local_store',
      ]),
    );
  });

  test('bridge-backed repository exposes key management operations', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      sshDir: '/tmp/pars-ssh',
    );

    final key = await repository.generateSshKey('github-mobile');
    final publicKey = await repository.exportSshPublicKey('github-mobile');
    final github = await repository.githubSshSettingsUri();

    expect(key.type, KeyRecordType.ssh);
    expect(publicKey, startsWith('ssh-ed25519 '));
    expect(github.toString(), 'https://github.com/settings/keys');
    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'generate_ssh_key',
        'export_ssh_public_key',
        'open_github_ssh_settings',
      ]),
    );
  });
}

class _LifecycleBridge implements ParsBridgeApi {
  final List<String> calledMethods = <String>[];

  @override
  Future<frb.AppStateResponse> inspectAppState({
    required frb.InspectAppStateRequest request,
  }) async {
    calledMethods.add('inspect_app_state');
    return const frb.AppStateResponse(
      state: frb.AppStateDto(
        configPath: '/tmp/pars_config.toml',
        configExists: true,
        selectedStoreId: 'store-0',
        selectedStoreRoot: '/tmp/personal-store',
        onboardingState: 'ready',
        issues: <String>[],
        stores: <frb.StoreStatusDto>[
          frb.StoreStatusDto(
            id: 'store-0',
            name: 'Personal',
            root: '/tmp/personal-store',
            isDefault: true,
            exists: true,
            hasGpgId: true,
            hasGitRemote: true,
            pgpKeyMissing: false,
            issues: <String>[],
          ),
        ],
      ),
    );
  }

  @override
  Future<frb.ListEntriesResponse> listEntries({
    required frb.ListEntriesRequest request,
  }) async {
    calledMethods.add('list_entries');
    return const frb.ListEntriesResponse(
      entries: <frb.EntrySummaryDto>[
        frb.EntrySummaryDto(
          path: 'work/github',
          name: 'github',
          entryType: 'Password',
          childCount: 0,
        ),
        frb.EntrySummaryDto(
          path: 'work',
          name: 'work',
          entryType: 'Directory',
          childCount: 1,
        ),
      ],
    );
  }

  @override
  Future<frb.GitCommandResponse> gitStatus({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_status');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git status --short --branch',
        stdout: '## main\n M example.gpg\n',
        stderr: '',
        success: true,
      ),
    );
  }

  @override
  Future<frb.ListKeysResponse> listKeys({
    required frb.ListKeysRequest request,
  }) async {
    calledMethods.add('list_keys');
    return const frb.ListKeysResponse(
      keys: <frb.KeyRecordDto>[
        frb.KeyRecordDto(
          keyType: 'ssh',
          name: 'github-mobile',
          fingerprint: 'SHA256:test',
          source: 'SSH key directory',
          hasPrivateKey: true,
        ),
      ],
    );
  }

  @override
  Future<frb.UnitResponse> createLocalStore({
    required frb.CreateLocalStoreRequest request,
  }) async {
    calledMethods.add('create_local_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> selectStore({
    required frb.SelectStoreRequest request,
  }) async {
    calledMethods.add('select_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> importLocalStore({
    required frb.ImportLocalStoreRequest request,
  }) async {
    calledMethods.add('import_local_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> cloneStore({
    required frb.CloneStoreRequest request,
  }) async {
    calledMethods.add('clone_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> removeStore({
    required frb.RemoveStoreRequest request,
  }) async {
    calledMethods.add('remove_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> deleteLocalStore({
    required frb.DeleteLocalStoreRequest request,
  }) async {
    calledMethods.add('delete_local_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.KeyMutationResponse> generateSshKey({
    required frb.GenerateSshKeyRequest request,
  }) async {
    calledMethods.add('generate_ssh_key');
    return const frb.KeyMutationResponse(
      key: frb.KeyRecordDto(
        keyType: 'ssh',
        name: 'github-mobile',
        fingerprint: 'SHA256:test',
        source: 'SSH key directory',
        hasPrivateKey: true,
      ),
    );
  }

  @override
  Future<frb.KeyExportResponse> exportSshPublicKey({
    required frb.ExportSshKeyRequest request,
  }) async {
    calledMethods.add('export_ssh_public_key');
    return const frb.KeyExportResponse(
      export_: frb.KeyExportDto(armoredText: 'ssh-ed25519 AAAAtest'),
    );
  }

  @override
  Future<frb.OpenExternalUrlResponse> openGithubSshSettings({
    required frb.OpenGithubSshSettingsRequest request,
  }) async {
    calledMethods.add('open_github_ssh_settings');
    return const frb.OpenExternalUrlResponse(
      url: 'https://github.com/settings/keys',
    );
  }

  @override
  Future<frb.ConfigResponse> loadConfig({
    required frb.LoadConfigRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.UnitResponse> saveConfig({
    required frb.SaveConfigRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.ListStoresResponse> listStores({
    required frb.ListStoresRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.EntrySecretResponse> readEntry({
    required frb.EntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.CopyEntryPasswordResponse> copyEntryPassword({
    required frb.EntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.InsertEntryResponse> insertEntry({
    required frb.InsertEntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.GenerateEntryResponse> generateEntry({
    required frb.GenerateEntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.MutationResponse> editEntry({
    required frb.EditEntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.MutationResponse> moveEntry({
    required frb.MoveEntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.DeleteEntryResponse> deleteEntry({
    required frb.DeleteEntryRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.GitCommandResponse> gitPull({required frb.GitRequest request}) {
    throw UnimplementedError();
  }

  @override
  Future<frb.GitCommandResponse> gitPush({required frb.GitRequest request}) {
    throw UnimplementedError();
  }

  @override
  Future<frb.GitCommandResponse> gitCommit({
    required frb.GitCommitRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.GitCommandResponse> runGitArgs({
    required frb.GitArgsRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyDetectionResponse> detectImportedKey({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> generatePgpKey({
    required frb.GeneratePgpKeyRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPublicKey({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyExportResponse> exportPgpPublicKey({
    required frb.ExportPgpKeyRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyExportResponse> exportPgpPrivateKey({
    required frb.ExportPgpKeyRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.UnitResponse> addPgpKeyToGpgId({
    required frb.AddPgpKeyToGpgIdRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyExportResponse> exportSshPrivateKey({
    required frb.ExportSshKeyRequest request,
  }) {
    throw UnimplementedError();
  }
}
