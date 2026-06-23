import 'frb_generated/api.dart' as frb;

abstract interface class ParsBridgeApi {
  Future<frb.ConfigResponse> loadConfig({
    required frb.LoadConfigRequest request,
  });

  Future<frb.UnitResponse> saveConfig({required frb.SaveConfigRequest request});

  Future<frb.ListStoresResponse> listStores({
    required frb.ListStoresRequest request,
  });

  Future<frb.ListEntriesResponse> listEntries({
    required frb.ListEntriesRequest request,
  });

  Future<frb.EntrySecretResponse> readEntry({
    required frb.EntryRequest request,
  });

  Future<frb.CopyEntryPasswordResponse> copyEntryPassword({
    required frb.EntryRequest request,
  });

  Future<frb.InsertEntryResponse> insertEntry({
    required frb.InsertEntryRequest request,
  });

  Future<frb.GenerateEntryResponse> generateEntry({
    required frb.GenerateEntryRequest request,
  });

  Future<frb.MutationResponse> editEntry({
    required frb.EditEntryRequest request,
  });

  Future<frb.MutationResponse> moveEntry({
    required frb.MoveEntryRequest request,
  });

  Future<frb.DeleteEntryResponse> deleteEntry({
    required frb.DeleteEntryRequest request,
  });

  Future<frb.GitCommandResponse> gitStatus({required frb.GitRequest request});

  Future<frb.GitCommandResponse> gitPull({required frb.GitRequest request});

  Future<frb.GitCommandResponse> gitPush({required frb.GitRequest request});

  Future<frb.GitCommandResponse> gitCommit({
    required frb.GitCommitRequest request,
  });

  Future<frb.GitCommandResponse> runGitArgs({
    required frb.GitArgsRequest request,
  });
}

final class FrbParsBridgeApi implements ParsBridgeApi {
  const FrbParsBridgeApi();

  @override
  Future<frb.ConfigResponse> loadConfig({
    required frb.LoadConfigRequest request,
  }) => frb.loadConfig(request: request);

  @override
  Future<frb.UnitResponse> saveConfig({
    required frb.SaveConfigRequest request,
  }) => frb.saveConfig(request: request);

  @override
  Future<frb.ListStoresResponse> listStores({
    required frb.ListStoresRequest request,
  }) => frb.listStores(request: request);

  @override
  Future<frb.ListEntriesResponse> listEntries({
    required frb.ListEntriesRequest request,
  }) => frb.listEntries(request: request);

  @override
  Future<frb.EntrySecretResponse> readEntry({
    required frb.EntryRequest request,
  }) => frb.readEntry(request: request);

  @override
  Future<frb.CopyEntryPasswordResponse> copyEntryPassword({
    required frb.EntryRequest request,
  }) => frb.copyEntryPassword(request: request);

  @override
  Future<frb.InsertEntryResponse> insertEntry({
    required frb.InsertEntryRequest request,
  }) => frb.insertEntry(request: request);

  @override
  Future<frb.GenerateEntryResponse> generateEntry({
    required frb.GenerateEntryRequest request,
  }) => frb.generateEntry(request: request);

  @override
  Future<frb.MutationResponse> editEntry({
    required frb.EditEntryRequest request,
  }) => frb.editEntry(request: request);

  @override
  Future<frb.MutationResponse> moveEntry({
    required frb.MoveEntryRequest request,
  }) => frb.moveEntry(request: request);

  @override
  Future<frb.DeleteEntryResponse> deleteEntry({
    required frb.DeleteEntryRequest request,
  }) => frb.deleteEntry(request: request);

  @override
  Future<frb.GitCommandResponse> gitStatus({required frb.GitRequest request}) =>
      frb.gitStatus(request: request);

  @override
  Future<frb.GitCommandResponse> gitPull({required frb.GitRequest request}) =>
      frb.gitPull(request: request);

  @override
  Future<frb.GitCommandResponse> gitPush({required frb.GitRequest request}) =>
      frb.gitPush(request: request);

  @override
  Future<frb.GitCommandResponse> gitCommit({
    required frb.GitCommitRequest request,
  }) => frb.gitCommit(request: request);

  @override
  Future<frb.GitCommandResponse> runGitArgs({
    required frb.GitArgsRequest request,
  }) => frb.runGitArgs(request: request);
}
