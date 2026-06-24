import 'frb_generated/api.dart' as frb;

abstract interface class ParsBridgeApi {
  Future<frb.ConfigResponse> loadConfig({
    required frb.LoadConfigRequest request,
  });

  Future<frb.UnitResponse> saveConfig({required frb.SaveConfigRequest request});

  Future<frb.UnitResponse> configurePgpBackend({
    required frb.ConfigurePgpBackendRequest request,
  });

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

  Future<frb.AppStateResponse> inspectAppState({
    required frb.InspectAppStateRequest request,
  });

  Future<frb.UnitResponse> selectStore({
    required frb.SelectStoreRequest request,
  });

  Future<frb.UnitResponse> createLocalStore({
    required frb.CreateLocalStoreRequest request,
  });

  Future<frb.UnitResponse> importLocalStore({
    required frb.ImportLocalStoreRequest request,
  });

  Future<frb.UnitResponse> cloneStore({required frb.CloneStoreRequest request});

  Future<frb.UnitResponse> removeStore({
    required frb.RemoveStoreRequest request,
  });

  Future<frb.UnitResponse> deleteLocalStore({
    required frb.DeleteLocalStoreRequest request,
  });

  Future<frb.ListKeysResponse> listKeys({required frb.ListKeysRequest request});

  Future<frb.KeyDetectionResponse> detectImportedKey({
    required frb.ImportKeyTextRequest request,
  });

  Future<frb.KeyMutationResponse> generatePgpKey({
    required frb.GeneratePgpKeyRequest request,
  });

  Future<frb.KeyMutationResponse> importPgpPublicKey({
    required frb.ImportKeyTextRequest request,
  });

  Future<frb.KeyMutationResponse> importPgpPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  });

  Future<frb.KeyMutationResponse> importPgpPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  });

  Future<frb.KeyExportResponse> exportPgpPublicKey({
    required frb.ExportPgpKeyRequest request,
  });

  Future<frb.KeyExportResponse> exportPgpPrivateKey({
    required frb.ExportPgpKeyRequest request,
  });

  Future<frb.UnitResponse> addPgpKeyToGpgId({
    required frb.AddPgpKeyToGpgIdRequest request,
  });

  Future<frb.KeyMutationResponse> generateSshKey({
    required frb.GenerateSshKeyRequest request,
  });

  Future<frb.KeyMutationResponse> importSshPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  });

  Future<frb.KeyMutationResponse> importSshPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  });

  Future<frb.KeyExportResponse> exportSshPublicKey({
    required frb.ExportSshKeyRequest request,
  });

  Future<frb.KeyExportResponse> exportSshPrivateKey({
    required frb.ExportSshKeyRequest request,
  });

  Future<frb.OpenExternalUrlResponse> openGithubSshSettings({
    required frb.OpenGithubSshSettingsRequest request,
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
  Future<frb.UnitResponse> configurePgpBackend({
    required frb.ConfigurePgpBackendRequest request,
  }) => frb.configurePgpBackend(request: request);

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

  @override
  Future<frb.AppStateResponse> inspectAppState({
    required frb.InspectAppStateRequest request,
  }) => frb.inspectAppState(request: request);

  @override
  Future<frb.UnitResponse> selectStore({
    required frb.SelectStoreRequest request,
  }) => frb.selectStore(request: request);

  @override
  Future<frb.UnitResponse> createLocalStore({
    required frb.CreateLocalStoreRequest request,
  }) => frb.createLocalStore(request: request);

  @override
  Future<frb.UnitResponse> importLocalStore({
    required frb.ImportLocalStoreRequest request,
  }) => frb.importLocalStore(request: request);

  @override
  Future<frb.UnitResponse> cloneStore({
    required frb.CloneStoreRequest request,
  }) => frb.cloneStore(request: request);

  @override
  Future<frb.UnitResponse> removeStore({
    required frb.RemoveStoreRequest request,
  }) => frb.removeStore(request: request);

  @override
  Future<frb.UnitResponse> deleteLocalStore({
    required frb.DeleteLocalStoreRequest request,
  }) => frb.deleteLocalStore(request: request);

  @override
  Future<frb.ListKeysResponse> listKeys({
    required frb.ListKeysRequest request,
  }) => frb.listKeys(request: request);

  @override
  Future<frb.KeyDetectionResponse> detectImportedKey({
    required frb.ImportKeyTextRequest request,
  }) => frb.detectImportedKey(request: request);

  @override
  Future<frb.KeyMutationResponse> generatePgpKey({
    required frb.GeneratePgpKeyRequest request,
  }) => frb.generatePgpKey(request: request);

  @override
  Future<frb.KeyMutationResponse> importPgpPublicKey({
    required frb.ImportKeyTextRequest request,
  }) => frb.importPgpPublicKey(request: request);

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) => frb.importPgpPrivateKeyFile(request: request);

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) => frb.importPgpPrivateKeyText(request: request);

  @override
  Future<frb.KeyExportResponse> exportPgpPublicKey({
    required frb.ExportPgpKeyRequest request,
  }) => frb.exportPgpPublicKey(request: request);

  @override
  Future<frb.KeyExportResponse> exportPgpPrivateKey({
    required frb.ExportPgpKeyRequest request,
  }) => frb.exportPgpPrivateKey(request: request);

  @override
  Future<frb.UnitResponse> addPgpKeyToGpgId({
    required frb.AddPgpKeyToGpgIdRequest request,
  }) => frb.addPgpKeyToGpgId(request: request);

  @override
  Future<frb.KeyMutationResponse> generateSshKey({
    required frb.GenerateSshKeyRequest request,
  }) => frb.generateSshKey(request: request);

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) => frb.importSshPrivateKeyFile(request: request);

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) => frb.importSshPrivateKeyText(request: request);

  @override
  Future<frb.KeyExportResponse> exportSshPublicKey({
    required frb.ExportSshKeyRequest request,
  }) => frb.exportSshPublicKey(request: request);

  @override
  Future<frb.KeyExportResponse> exportSshPrivateKey({
    required frb.ExportSshKeyRequest request,
  }) => frb.exportSshPrivateKey(request: request);

  @override
  Future<frb.OpenExternalUrlResponse> openGithubSshSettings({
    required frb.OpenGithubSshSettingsRequest request,
  }) => frb.openGithubSshSettings(request: request);
}
