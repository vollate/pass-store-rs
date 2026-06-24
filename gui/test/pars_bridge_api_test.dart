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
  Future<frb.UnitResponse> configurePgpBackend({
    required frb.ConfigurePgpBackendRequest request,
  }) async {
    calledMethods.add('configure_pgp_backend');
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

  @override
  Future<frb.AppStateResponse> inspectAppState({
    required frb.InspectAppStateRequest request,
  }) async {
    calledMethods.add('inspect_app_state');
    return const frb.AppStateResponse();
  }

  @override
  Future<frb.UnitResponse> selectStore({
    required frb.SelectStoreRequest request,
  }) async {
    calledMethods.add('select_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> createLocalStore({
    required frb.CreateLocalStoreRequest request,
  }) async {
    calledMethods.add('create_local_store');
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
  Future<frb.ListKeysResponse> listKeys({
    required frb.ListKeysRequest request,
  }) async {
    calledMethods.add('list_keys');
    return const frb.ListKeysResponse(keys: <frb.KeyRecordDto>[]);
  }

  @override
  Future<frb.KeyDetectionResponse> detectImportedKey({
    required frb.ImportKeyTextRequest request,
  }) async {
    calledMethods.add('detect_imported_key');
    return const frb.KeyDetectionResponse(kind: 'pgp_public');
  }

  @override
  Future<frb.KeyMutationResponse> generatePgpKey({
    required frb.GeneratePgpKeyRequest request,
  }) async {
    calledMethods.add('generate_pgp_key');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPublicKey({
    required frb.ImportKeyTextRequest request,
  }) async {
    calledMethods.add('import_pgp_public_key');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) async {
    calledMethods.add('import_pgp_private_key_file');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) async {
    calledMethods.add('import_pgp_private_key_text');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyExportResponse> exportPgpPublicKey({
    required frb.ExportPgpKeyRequest request,
  }) async {
    calledMethods.add('export_pgp_public_key');
    return const frb.KeyExportResponse();
  }

  @override
  Future<frb.KeyExportResponse> exportPgpPrivateKey({
    required frb.ExportPgpKeyRequest request,
  }) async {
    calledMethods.add('export_pgp_private_key');
    return const frb.KeyExportResponse();
  }

  @override
  Future<frb.UnitResponse> addPgpKeyToGpgId({
    required frb.AddPgpKeyToGpgIdRequest request,
  }) async {
    calledMethods.add('add_pgp_key_to_gpg_id');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.KeyMutationResponse> generateSshKey({
    required frb.GenerateSshKeyRequest request,
  }) async {
    calledMethods.add('generate_ssh_key');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) async {
    calledMethods.add('import_ssh_private_key_file');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) async {
    calledMethods.add('import_ssh_private_key_text');
    return const frb.KeyMutationResponse();
  }

  @override
  Future<frb.KeyExportResponse> exportSshPublicKey({
    required frb.ExportSshKeyRequest request,
  }) async {
    calledMethods.add('export_ssh_public_key');
    return const frb.KeyExportResponse();
  }

  @override
  Future<frb.KeyExportResponse> exportSshPrivateKey({
    required frb.ExportSshKeyRequest request,
  }) async {
    calledMethods.add('export_ssh_private_key');
    return const frb.KeyExportResponse();
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
}
