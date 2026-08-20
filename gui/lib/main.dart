import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'app/pars_gui_app.dart';
import 'bridge/pars_bridge_api.dart';
import 'bridge/frb_generated/frb_generated.dart';
import 'services/autofill_repository.dart';
import 'services/bridge_backed_repository.dart';
import 'services/mobile_pgp_backend.dart';
import 'services/security_repository.dart';
import 'services/ui_preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init(
    externalLibrary:
        Platform.isIOS ? ExternalLibrary.process(iKnowHowToUseIt: true) : null,
  );
  const bridge = FrbParsBridgeApi();
  final pgpRuntime = await configureDefaultPgpRuntime(
    bridge: bridge,
    desktopConfigPath: BridgeBackedRepository.defaultConfigPath(),
  );
  final securityRepository = await SecureStorageSecurityRepository.load();
  final appSupportDirectory = await getApplicationSupportDirectory();
  final uiPreferencesStore = FileUiPreferencesStore(
    File('${appSupportDirectory.path}/pars_ui_preferences.json'),
  );
  late final BridgeBackedRepository repository;
  final autofillRepository = BridgeAutofillRepository(
    bridge: const FrbAutofillBridgeApi(),
    configPath: pgpRuntime.configPath,
    indexPath: '${pgpRuntime.configPath}.autofill.json',
    storeId: 'selected',
    storeName: 'Selected store',
    storeRoot: '',
    pgpExecutable: pgpRuntime.pgpExecutable,
    securityRepository: securityRepository,
    currentStoreId: () => repository.lifecycle.selectedStoreId ?? 'selected',
    currentStoreName:
        () => repository.lifecycle.selectedStore?.name ?? 'Selected store',
    currentStoreRoot: () => repository.lifecycle.selectedStoreRoot ?? '',
  );
  repository = BridgeBackedRepository(
    bridge: bridge,
    configPath: pgpRuntime.configPath,
    pgpExecutable: pgpRuntime.pgpExecutable,
    pgpBackendLabel: pgpRuntime.diagnosticsLabel,
    sshDir: pgpRuntime.sshDir,
    managedStoreBaseDir: pgpRuntime.storeBaseDir,
    securityRepository: securityRepository,
    autofillRepository: autofillRepository,
  );
  try {
    await repository.refresh();
    await repository.autoPullOnOpen();
  } catch (_) {
    // Keep the empty lifecycle so onboarding can present recovery actions.
  }
  try {
    await autofillRepository.publishPlatformState();
  } catch (_) {
    // Native Autofill remains unavailable until Settings rebuilds or retries it.
  }
  runApp(
    ParsGuiApp(
      vaultRepository: repository,
      settingsRepository: repository,
      keyRepository: repository,
      gitRepository: repository,
      securityRepository: securityRepository,
      autofillRepository: autofillRepository,
      uiPreferencesStore: uiPreferencesStore,
    ),
  );
}
