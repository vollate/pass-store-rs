import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/bridge/pars_bridge_api.dart';

void main() {
  test('mock bridge exposes async FRB entry list calls', () async {
    final bridge = _MockParsBridgeApi();

    final response = await bridge.listEntries(
      request: const frb.ListEntriesRequest(
        root: '/tmp/password-store',
        recursive: true,
      ),
    );

    expect(response.entries, hasLength(2));
    expect(response.entries.first.path, 'github');
    expect(bridge.calledMethods, contains('list_entries'));
  });

  test('FRB generated failures preserve typed Rust error fields', () {
    const failure = frb.BridgeFailure(
      category: frb.BridgeFailureCategory.conflict,
      message: 'entry already exists: github',
      conflictKind: 'EntryAlreadyExists',
      path: 'github',
    );

    expect(failure.category, frb.BridgeFailureCategory.conflict);
    expect(failure.conflictKind, 'EntryAlreadyExists');
    expect(failure.path, 'github');
    expect(failure.message, contains('entry already exists'));
  });
}

class _MockParsBridgeApi implements ParsBridgeApi {
  final List<String> calledMethods = <String>[];

  @override
  Future<frb.ConfigResponse> loadConfig({
    required frb.LoadConfigRequest request,
  }) async {
    calledMethods.add('load_config');
    return const frb.ConfigResponse(configToml: '');
  }

  @override
  Future<frb.UnitResponse> saveConfig({
    required frb.SaveConfigRequest request,
  }) async {
    calledMethods.add('save_config');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.ListStoresResponse> listStores({
    required frb.ListStoresRequest request,
  }) async {
    calledMethods.add('list_stores');
    return const frb.ListStoresResponse(stores: <frb.StoreInfoDto>[]);
  }

  @override
  Future<frb.ListEntriesResponse> listEntries({
    required frb.ListEntriesRequest request,
  }) async {
    calledMethods.add('list_entries');
    return frb.ListEntriesResponse(
      entries: <frb.EntrySummaryDto>[
        frb.EntrySummaryDto(
          path: 'github',
          name: 'github',
          entryType: 'File',
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
  Future<frb.EntrySecretResponse> readEntry({
    required frb.EntryRequest request,
  }) async {
    calledMethods.add('read_entry');
    return const frb.EntrySecretResponse();
  }

  @override
  Future<frb.CopyEntryPasswordResponse> copyEntryPassword({
    required frb.EntryRequest request,
  }) async {
    calledMethods.add('copy_entry_password');
    return const frb.CopyEntryPasswordResponse();
  }

  @override
  Future<frb.InsertEntryResponse> insertEntry({
    required frb.InsertEntryRequest request,
  }) async {
    calledMethods.add('insert_entry');
    return const frb.InsertEntryResponse();
  }

  @override
  Future<frb.GenerateEntryResponse> generateEntry({
    required frb.GenerateEntryRequest request,
  }) async {
    calledMethods.add('generate_entry');
    return const frb.GenerateEntryResponse();
  }

  @override
  Future<frb.MutationResponse> editEntry({
    required frb.EditEntryRequest request,
  }) async {
    calledMethods.add('edit_entry');
    return const frb.MutationResponse();
  }

  @override
  Future<frb.MutationResponse> moveEntry({
    required frb.MoveEntryRequest request,
  }) async {
    calledMethods.add('move_entry');
    return const frb.MutationResponse();
  }

  @override
  Future<frb.DeleteEntryResponse> deleteEntry({
    required frb.DeleteEntryRequest request,
  }) async {
    calledMethods.add('delete_entry');
    return const frb.DeleteEntryResponse();
  }

  @override
  Future<frb.GitCommandResponse> gitStatus({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_status');
    return const frb.GitCommandResponse();
  }

  @override
  Future<frb.GitCommandResponse> gitPull({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_pull');
    return const frb.GitCommandResponse();
  }

  @override
  Future<frb.GitCommandResponse> gitPush({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_push');
    return const frb.GitCommandResponse();
  }

  @override
  Future<frb.GitCommandResponse> gitCommit({
    required frb.GitCommitRequest request,
  }) async {
    calledMethods.add('git_commit');
    return const frb.GitCommandResponse();
  }

  @override
  Future<frb.GitCommandResponse> runGitArgs({
    required frb.GitArgsRequest request,
  }) async {
    calledMethods.add('run_git_args');
    return const frb.GitCommandResponse();
  }
}
