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
import 'services/key_repository.dart';
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
    storeId: 'canonical-store',
    storeName: 'Pars',
    storeRoot: '',
    pgpExecutable: pgpRuntime.pgpExecutable,
    securityRepository: securityRepository,
    currentStoreId: () => 'canonical-store',
    currentStoreName: () => repository.lifecycle.store?.name ?? 'Pars',
    currentStoreRoot: () => repository.lifecycle.store?.root ?? '',
    currentStoreReady:
        () =>
            !repository.storeRemovalInProgress &&
            !repository.lifecycle.requiresStoreSetup &&
            !repository.lifecycle.requiresStoreRepair,
    validatePgpPassphraseForCurrentStore: (fingerprint, passphrase) async {
      final store = repository.lifecycle.store;
      if (store == null || repository.storeRemovalInProgress) return false;
      final expected = fingerprint.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final matching = repository.keys.where(
        (key) =>
            key.hasPrivateKey &&
            key.hasLocalKeyMaterial &&
            key.fingerprint.replaceAll(RegExp(r'\s+'), '').toUpperCase() ==
                expected &&
            pgpIdentityMatchesAnyRecipient(
              fingerprint: key.fingerprint,
              identity: key.name,
              recipients: store.pgpRecipients,
            ),
      );
      if (matching.isEmpty) return false;
      try {
        final prepared = await repository.preparePgpPrivateKey(
          fingerprint: matching.first.fingerprint,
          passphrase: passphrase,
        );
        return prepared.fingerprint
                .replaceAll(RegExp(r'\s+'), '')
                .toUpperCase() ==
            expected;
      } catch (_) {
        return false;
      }
    },
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
