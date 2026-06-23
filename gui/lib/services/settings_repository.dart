import 'store_lifecycle.dart';

abstract interface class SettingsRepository {
  String get currentRepoName;

  StoreLifecycleSnapshot get lifecycle;

  List<StoreStatus> get stores;

  Future<void> refresh();

  Future<void> selectStore(String root);

  Future<void> createLocalStore({
    required String name,
    required String root,
    required List<String> pgpKeys,
    required bool setDefault,
    required bool initializeGit,
  });

  Future<void> importLocalStore({
    required String root,
    required bool setDefault,
  });

  Future<void> cloneStore({
    required String remoteUrl,
    required String root,
    required bool setDefault,
  });

  Future<void> removeStore({required String root});

  Future<void> deleteLocalStore({
    required String root,
    required String confirmation,
  });
}
