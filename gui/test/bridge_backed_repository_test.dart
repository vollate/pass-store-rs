import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/bridge/pars_bridge_api.dart';
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
          'list_entries',
          'git_status',
        ]),
      );
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
}
