import 'package:flutter/material.dart';

import 'app/pars_gui_app.dart';
import 'bridge/frb_generated/frb_generated.dart';
import 'services/bridge_backed_repository.dart';
import 'services/security_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final repository = BridgeBackedRepository.defaultInstance();
  try {
    await repository.refresh();
  } catch (_) {
    // Keep the empty lifecycle so onboarding can present recovery actions.
  }
  final securityRepository = await SecureStorageSecurityRepository.load();
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
