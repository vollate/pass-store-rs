import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/bridge/pars_bridge_api.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/services/bridge_backed_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/services/vault_metadata_store.dart';

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
      final secret = await repository.readEntry(repository.entries.first);
      final copiedPassword = await repository.copyEntryPassword(
        repository.entries.first,
      );

      expect(secret.password, 'bridge-secret');
      expect(secret.fieldValue('username'), 'alice');
      expect(secret.fieldValue('url'), 'https://example.com');
      expect(copiedPassword, 'bridge-secret');
      expect(bridge.lastEntryRequest?.root, '/tmp/personal-store');
      expect(bridge.lastEntryRequest?.path, 'work/github');
      expect(
        bridge.calledMethods,
        containsAll(<String>[
          'inspect_app_state',
          'list_keys',
          'list_entries',
          'git_status',
          'read_entry',
          'copy_entry_password',
        ]),
      );
      expect(repository.keys.single.name, 'github-mobile');
    },
  );

  test('bridge-backed repository persists vault metadata', () async {
    final metadataStore = InMemoryVaultMetadataStore();
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      metadataStore: metadataStore,
    );

    await repository.refresh();

    expect(repository.browseEntries(null).map((entry) => entry.path), <String>[
      'work',
    ]);
    expect(
      repository.browseEntries('work').map((entry) => entry.path),
      <String>['work/github'],
    );

    await repository.readEntry(repository.entries.first);
    await repository.toggleFavorite(repository.entries.first);

    expect(repository.recentEntries().single.path, 'work/github');
    expect(repository.entries.first.isFavorite, isTrue);

    final nextRepository = BridgeBackedRepository(
      bridge: _LifecycleBridge(),
      configPath: '/tmp/pars_config.toml',
      metadataStore: metadataStore,
    );
    await nextRepository.refresh();

    expect(nextRepository.recentEntries().single.path, 'work/github');
    expect(nextRepository.entries.first.isFavorite, isTrue);
  });

  test('bridge-backed repository exposes manage operations', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.refresh();

    final saved = await repository.saveEntry(
      path: 'work/new',
      content: 'new-secret',
      overwrite: false,
    );
    final generated = await repository.generateEntry(
      path: 'work/generated',
      length: 32,
      noSymbols: true,
      overwrite: true,
    );
    final edited = await repository.editEntry(
      path: 'work/new',
      content: 'edited-secret\nnote',
    );
    final replaced = await repository.replaceEntryPassword(
      entry: repository.entries.first,
      password: 'rotated-secret',
    );
    final moved = await repository.moveEntry(
      fromPath: 'work/new',
      toPath: 'archive/new',
      overwrite: false,
    );
    final deleted = await repository.deleteEntry(
      path: 'archive/new',
      recursive: false,
    );
    final commit = await repository.commitChanges('Update archive/new');

    expect(saved.path, 'work/new');
    expect(generated.path, 'work/generated');
    expect(edited.path, 'work/new');
    expect(replaced.action, 'Replaced password for');
    expect(moved.path, 'archive/new');
    expect(deleted.action, 'Deleted');
    expect(commit.success, isTrue);
    expect(bridge.lastInsertRequest?.content, 'new-secret');
    expect(bridge.lastGenerateRequest?.length, 32);
    expect(bridge.lastGenerateRequest?.noSymbols, isTrue);
    expect(bridge.lastEditRequest?.content, contains('rotated-secret'));
    expect(bridge.lastEditRequest?.content, contains('username: alice'));
    expect(bridge.lastMoveRequest?.fromPath, 'work/new');
    expect(bridge.lastMoveRequest?.toPath, 'archive/new');
    expect(bridge.lastDeleteRequest?.path, 'archive/new');
    expect(bridge.lastGitCommitRequest?.message, 'Update archive/new');
    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'insert_entry',
        'generate_entry',
        'edit_entry',
        'move_entry',
        'delete_entry',
        'git_commit',
      ]),
    );
  });

  test('bridge-backed repository exposes git operations and remotes', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.refresh();

    final status = await repository.refreshGitStatus();
    final pull = await repository.pull();
    final push = await repository.push();
    final commit = await repository.commit('Sync passwords');
    final remotes = await repository.listRemotes();
    final added = await repository.addRemote(
      name: 'backup',
      url: 'git@example.com:backup/pass.git',
    );
    final edited = await repository.editRemote(
      name: 'origin',
      url: 'git@example.com:new/pass.git',
    );
    final removed = await repository.removeRemote('backup');

    expect(status.command, 'git status --short --branch');
    expect(pull.command, 'git pull');
    expect(push.command, 'git push');
    expect(commit.command, 'git commit -m "Sync passwords"');
    expect(remotes.single.name, 'origin');
    expect(remotes.single.fetchUrl, 'git@example.com:org/pass.git');
    expect(
      added.command,
      'git remote add backup git@example.com:backup/pass.git',
    );
    expect(
      edited.command,
      'git remote set-url origin git@example.com:new/pass.git',
    );
    expect(removed.command, 'git remote remove backup');
    expect(bridge.lastGitCommitRequest?.message, 'Sync passwords');
    expect(bridge.lastGitArgsRequest?.args, <String>[
      'remote',
      'remove',
      'backup',
    ]);
  });

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
  frb.EntryRequest? lastEntryRequest;
  frb.InsertEntryRequest? lastInsertRequest;
  frb.GenerateEntryRequest? lastGenerateRequest;
  frb.EditEntryRequest? lastEditRequest;
  frb.MoveEntryRequest? lastMoveRequest;
  frb.DeleteEntryRequest? lastDeleteRequest;
  frb.GitCommitRequest? lastGitCommitRequest;
  frb.GitArgsRequest? lastGitArgsRequest;

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
  }) async {
    calledMethods.add('read_entry');
    lastEntryRequest = request;
    return const frb.EntrySecretResponse(
      secret: frb.EntrySecretDto(
        password: 'bridge-secret',
        fields: <frb.ParsedEntryFieldDto>[
          frb.ParsedEntryFieldDto(
            key: 'username',
            label: 'Username',
            value: 'alice',
          ),
          frb.ParsedEntryFieldDto(
            key: 'url',
            label: 'URL',
            value: 'https://example.com',
          ),
        ],
        rawNotes: 'raw note',
      ),
    );
  }

  @override
  Future<frb.CopyEntryPasswordResponse> copyEntryPassword({
    required frb.EntryRequest request,
  }) async {
    calledMethods.add('copy_entry_password');
    lastEntryRequest = request;
    return const frb.CopyEntryPasswordResponse(
      result: frb.CopyEntryPasswordResult(
        path: 'work/github',
        password: 'bridge-secret',
      ),
    );
  }

  @override
  Future<frb.InsertEntryResponse> insertEntry({
    required frb.InsertEntryRequest request,
  }) async {
    calledMethods.add('insert_entry');
    lastInsertRequest = request;
    return frb.InsertEntryResponse(
      result: frb.InsertEntryResultDto(
        entryPath: request.path,
        overwroteExisting: request.overwrite,
      ),
    );
  }

  @override
  Future<frb.GenerateEntryResponse> generateEntry({
    required frb.GenerateEntryRequest request,
  }) async {
    calledMethods.add('generate_entry');
    lastGenerateRequest = request;
    return frb.GenerateEntryResponse(
      result: frb.GenerateEntryResultDto(
        entryPath: request.path,
        password: 'generated-secret',
        overwroteExisting: request.overwrite,
      ),
    );
  }

  @override
  Future<frb.MutationResponse> editEntry({
    required frb.EditEntryRequest request,
  }) async {
    calledMethods.add('edit_entry');
    lastEditRequest = request;
    return frb.MutationResponse(
      result: frb.MutationResultDto(path: request.path),
    );
  }

  @override
  Future<frb.MutationResponse> moveEntry({
    required frb.MoveEntryRequest request,
  }) async {
    calledMethods.add('move_entry');
    lastMoveRequest = request;
    return frb.MutationResponse(
      result: frb.MutationResultDto(path: request.toPath),
    );
  }

  @override
  Future<frb.DeleteEntryResponse> deleteEntry({
    required frb.DeleteEntryRequest request,
  }) async {
    calledMethods.add('delete_entry');
    lastDeleteRequest = request;
    return frb.DeleteEntryResponse(
      result: frb.DeleteEntryResultDto(
        deletedPath: request.path,
        deletedType: 'Password',
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitPull({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_pull');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git pull',
        stdout: 'Already up to date.',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitPush({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_push');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git push',
        stdout: 'Pushed.',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitCommit({
    required frb.GitCommitRequest request,
  }) async {
    calledMethods.add('git_commit');
    lastGitCommitRequest = request;
    return frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git commit -m "${request.message}"',
        stdout: 'Committed',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> runGitArgs({
    required frb.GitArgsRequest request,
  }) async {
    calledMethods.add('run_git_args');
    lastGitArgsRequest = request;
    final args = request.args.join(' ');
    final stdout =
        args == 'remote -v'
            ? 'origin\tgit@example.com:org/pass.git (fetch)\norigin\tgit@example.com:org/pass.git (push)\n'
            : '';
    return frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git $args',
        stdout: stdout,
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
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
