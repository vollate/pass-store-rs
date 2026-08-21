import 'package:flutter/foundation.dart';

import 'store_lifecycle.dart';

abstract interface class SettingsRepository {
  StoreLifecycleSnapshot get lifecycle;

  StoreStatus? get store;

  Future<void> refresh();

  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool initializeGit,
  });

  Future<void> importLocalStore({required String root});

  Future<void> cloneStore({required String remoteUrl, required String root});

  Future<void> removeStore({required String root});

  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  });
}

abstract interface class StoreLifecycleChangeSource {
  ValueListenable<int> get lifecycleRevision;

  bool get storeRemovalInProgress;
}

abstract interface class AppManagedPathRepository {
  bool get usesAppManagedPaths;

  bool isAppManagedStoreRoot(String root);

  String storeRootForName(String name);

  String storeRootForRemote(String remoteUrl);
}
