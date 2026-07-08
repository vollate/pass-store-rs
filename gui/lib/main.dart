import 'package:flutter/material.dart';

import 'app/pars_gui_app.dart';
import 'bridge/pars_bridge_api.dart';
import 'bridge/frb_generated/frb_generated.dart';
import 'services/bridge_backed_repository.dart';
import 'services/mobile_pgp_backend.dart';
import 'services/security_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  const bridge = FrbParsBridgeApi();
  final pgpRuntime = await configureDefaultPgpRuntime(
    bridge: bridge,
    desktopConfigPath: BridgeBackedRepository.defaultConfigPath(),
  );
  final securityRepository = await SecureStorageSecurityRepository.load();
  final repository = BridgeBackedRepository(
    bridge: bridge,
    configPath: pgpRuntime.configPath,
    pgpExecutable: pgpRuntime.pgpExecutable,
    pgpBackendLabel: pgpRuntime.diagnosticsLabel,
    sshDir: pgpRuntime.sshDir,
    managedStoreBaseDir: pgpRuntime.storeBaseDir,
    securityRepository: securityRepository,
  );
  try {
    await repository.refresh();
    await repository.autoPullOnOpen();
  } catch (_) {
    // Keep the empty lifecycle so onboarding can present recovery actions.
  }
  runApp(
    ParsGuiApp(
      vaultRepository: repository,
      settingsRepository: repository,
      keyRepository: repository,
      gitRepository: repository,
      securityRepository: securityRepository,
    ),
  );
}
