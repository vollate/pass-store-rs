import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../bridge/frb_generated/api.dart' as frb;
import '../bridge/pars_bridge_api.dart';

class PgpRuntimeConfigurationException implements Exception {
  const PgpRuntimeConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PgpRuntimeConfig {
  const PgpRuntimeConfig({
    required this.configPath,
    required this.diagnosticsLabel,
    this.pgpExecutable,
  });

  final String configPath;
  final String diagnosticsLabel;
  final String? pgpExecutable;
}

class PgpRuntimeEnvironment {
  const PgpRuntimeEnvironment({
    required this.isMobile,
    required this.supportDirectory,
  });

  factory PgpRuntimeEnvironment.current() {
    return PgpRuntimeEnvironment(
      isMobile: Platform.isAndroid || Platform.isIOS,
      supportDirectory: getApplicationSupportDirectory,
    );
  }

  final bool isMobile;
  final Future<Directory> Function() supportDirectory;
}

Future<PgpRuntimeConfig> configureDefaultPgpRuntime({
  required ParsBridgeApi bridge,
  required String desktopConfigPath,
  PgpRuntimeEnvironment? environment,
}) async {
  final runtime = environment ?? PgpRuntimeEnvironment.current();
  if (!runtime.isMobile) {
    return PgpRuntimeConfig(
      configPath: desktopConfigPath,
      diagnosticsLabel: 'System GPG from PATH',
    );
  }

  final supportDir = await runtime.supportDirectory();
  final configPath = _joinPath(supportDir.path, 'pars_config.toml');
  final keyringHome = _joinPath(supportDir.path, 'pgp');
  await Directory(keyringHome).create(recursive: true);
  final response = await bridge.configurePgpBackend(
    request: frb.ConfigurePgpBackendRequest(
      configPath: configPath,
      backend: 'pure_rust',
      keyringHome: keyringHome,
    ),
  );
  final error = response.error;
  if (error != null) {
    throw PgpRuntimeConfigurationException(error.message);
  }

  return PgpRuntimeConfig(
    configPath: configPath,
    diagnosticsLabel: 'Pure Rust OpenPGP (rPGP)',
  );
}

String _joinPath(String parent, String child) {
  final separator = Platform.pathSeparator;
  if (parent.endsWith(separator)) {
    return '$parent$child';
  }
  return '$parent$separator$child';
}
