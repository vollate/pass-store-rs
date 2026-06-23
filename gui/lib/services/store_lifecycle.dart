import '../bridge/frb_generated/api.dart' as frb;

enum StoreOnboardingState {
  noConfig,
  storeMissing,
  missingGpgId,
  gitRemoteMissing,
  pgpKeyMissing,
  ready,
}

extension StoreOnboardingStateLabel on StoreOnboardingState {
  String get label {
    switch (this) {
      case StoreOnboardingState.noConfig:
        return 'No config';
      case StoreOnboardingState.storeMissing:
        return 'Store missing';
      case StoreOnboardingState.missingGpgId:
        return 'Missing .gpg-id';
      case StoreOnboardingState.gitRemoteMissing:
        return 'Git remote missing';
      case StoreOnboardingState.pgpKeyMissing:
        return 'PGP key missing';
      case StoreOnboardingState.ready:
        return 'Ready';
    }
  }

  bool get requiresSetup => this != StoreOnboardingState.ready;
}

class StoreStatus {
  const StoreStatus({
    required this.id,
    required this.name,
    required this.root,
    required this.isDefault,
    required this.exists,
    required this.hasGpgId,
    required this.hasGitRemote,
    required this.pgpKeyMissing,
    required this.issues,
  });

  factory StoreStatus.fromBridge(frb.StoreStatusDto dto) {
    return StoreStatus(
      id: dto.id,
      name: dto.name,
      root: dto.root,
      isDefault: dto.isDefault,
      exists: dto.exists,
      hasGpgId: dto.hasGpgId,
      hasGitRemote: dto.hasGitRemote,
      pgpKeyMissing: dto.pgpKeyMissing,
      issues: dto.issues,
    );
  }

  final String id;
  final String name;
  final String root;
  final bool isDefault;
  final bool exists;
  final bool hasGpgId;
  final bool hasGitRemote;
  final bool pgpKeyMissing;
  final List<String> issues;
}

class StoreLifecycleSnapshot {
  const StoreLifecycleSnapshot({
    required this.configPath,
    required this.configExists,
    required this.onboardingState,
    required this.issues,
    required this.stores,
    this.selectedStoreId,
    this.selectedStoreRoot,
  });

  factory StoreLifecycleSnapshot.empty(String configPath) {
    return StoreLifecycleSnapshot(
      configPath: configPath,
      configExists: false,
      onboardingState: StoreOnboardingState.noConfig,
      issues: const <String>['no_config'],
      stores: const <StoreStatus>[],
    );
  }

  factory StoreLifecycleSnapshot.fromBridge(frb.AppStateDto dto) {
    return StoreLifecycleSnapshot(
      configPath: dto.configPath,
      configExists: dto.configExists,
      selectedStoreId: dto.selectedStoreId,
      selectedStoreRoot: dto.selectedStoreRoot,
      onboardingState: _onboardingStateFromBridge(dto.onboardingState),
      issues: dto.issues,
      stores: dto.stores.map(StoreStatus.fromBridge).toList(growable: false),
    );
  }

  final String configPath;
  final bool configExists;
  final String? selectedStoreId;
  final String? selectedStoreRoot;
  final StoreOnboardingState onboardingState;
  final List<String> issues;
  final List<StoreStatus> stores;

  StoreStatus? get selectedStore {
    for (final store in stores) {
      if (store.id == selectedStoreId || store.root == selectedStoreRoot) {
        return store;
      }
    }
    return stores.isEmpty ? null : stores.first;
  }
}

StoreOnboardingState _onboardingStateFromBridge(String value) {
  switch (value) {
    case 'no_config':
      return StoreOnboardingState.noConfig;
    case 'store_missing':
      return StoreOnboardingState.storeMissing;
    case 'missing_gpg_id':
      return StoreOnboardingState.missingGpgId;
    case 'git_remote_missing':
      return StoreOnboardingState.gitRemoteMissing;
    case 'pgp_key_missing':
      return StoreOnboardingState.pgpKeyMissing;
    case 'ready':
      return StoreOnboardingState.ready;
    default:
      return StoreOnboardingState.storeMissing;
  }
}
