import '../bridge/frb_generated/api.dart' as frb;

enum StoreOnboardingState {
  noConfig,
  storeMissing,
  missingGpgId,
  gitInvalid,
  pgpKeyMissing,
  ready,
}

enum StoreGitMode { disabled, local, remote, invalid }

class StoreStatus {
  const StoreStatus({
    required this.name,
    required this.root,
    required this.exists,
    required this.hasGpgId,
    this.pgpRecipients = const <String>[],
    required this.pgpKeyMissing,
    required this.issues,
    this.gitMode = StoreGitMode.remote,
  });

  factory StoreStatus.fromBridge(frb.StoreStatusDto dto) {
    final gitMode = _gitModeFromBridge(dto.gitMode);
    return StoreStatus(
      name: dto.name,
      root: dto.root,
      exists: dto.exists,
      hasGpgId: dto.hasGpgId,
      pgpRecipients: dto.pgpRecipients,
      pgpKeyMissing: dto.pgpKeyMissing,
      issues: dto.issues,
      gitMode: gitMode,
    );
  }

  final String name;
  final String root;
  final bool exists;
  final bool hasGpgId;
  final List<String> pgpRecipients;
  final bool pgpKeyMissing;
  final List<String> issues;
  final StoreGitMode gitMode;
}

class StoreLifecycleSnapshot {
  const StoreLifecycleSnapshot({
    required this.configPath,
    required this.configExists,
    required this.onboardingState,
    required this.issues,
    required this.store,
  });

  factory StoreLifecycleSnapshot.empty(String configPath) {
    return StoreLifecycleSnapshot(
      configPath: configPath,
      configExists: false,
      onboardingState: StoreOnboardingState.noConfig,
      issues: const <String>['no_config'],
      store: null,
    );
  }

  factory StoreLifecycleSnapshot.withoutStore({
    required String configPath,
    required bool configExists,
  }) {
    return StoreLifecycleSnapshot(
      configPath: configPath,
      configExists: configExists,
      onboardingState:
          configExists
              ? StoreOnboardingState.storeMissing
              : StoreOnboardingState.noConfig,
      issues: <String>[configExists ? 'store_missing' : 'no_config'],
      store: null,
    );
  }

  factory StoreLifecycleSnapshot.fromBridge(frb.AppStateDto dto) {
    final store = dto.store == null ? null : StoreStatus.fromBridge(dto.store!);
    return StoreLifecycleSnapshot(
      configPath: dto.configPath,
      configExists: dto.configExists,
      onboardingState: _onboardingStateFromBridge(dto.onboardingState),
      issues: dto.issues,
      store: store,
    );
  }

  final String configPath;
  final bool configExists;
  final StoreOnboardingState onboardingState;
  final List<String> issues;
  final StoreStatus? store;

  bool get requiresStoreSetup => store == null || !store!.exists;

  bool get requiresKeyRepair {
    final current = store;
    return current != null &&
        current.exists &&
        (current.pgpKeyMissing ||
            current.issues.contains('pgp_key_missing') ||
            onboardingState == StoreOnboardingState.pgpKeyMissing);
  }

  bool get requiresStoreRepair {
    final current = store;
    return current != null &&
        current.exists &&
        (!current.hasGpgId ||
            current.gitMode == StoreGitMode.invalid ||
            requiresKeyRepair);
  }
}

StoreGitMode _gitModeFromBridge(frb.StoreGitModeDto value) {
  switch (value) {
    case frb.StoreGitModeDto.disabled:
      return StoreGitMode.disabled;
    case frb.StoreGitModeDto.local:
      return StoreGitMode.local;
    case frb.StoreGitModeDto.remote:
      return StoreGitMode.remote;
    case frb.StoreGitModeDto.invalid:
      return StoreGitMode.invalid;
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
    case 'git_invalid':
      return StoreOnboardingState.gitInvalid;
    case 'pgp_key_missing':
      return StoreOnboardingState.pgpKeyMissing;
    case 'ready':
      return StoreOnboardingState.ready;
    default:
      return StoreOnboardingState.storeMissing;
  }
}
