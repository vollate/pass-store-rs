import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../bridge/frb_generated/api.dart' as frb;
import '../bridge/pars_bridge_api.dart';

const MethodChannel _iosRuntimeChannel = MethodChannel(
  'top.vollate.pars_gui/ios_runtime',
);

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
    this.sshDir,
    this.storeBaseDir,
  });

  final String configPath;
  final String diagnosticsLabel;
  final String? pgpExecutable;
  final String? sshDir;
  final String? storeBaseDir;
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

  final supportDir = await _mobileSupportDirectory(runtime);
  final configPath = _joinPath(supportDir.path, 'pars_config.toml');
  final keyringHome = _joinPath(supportDir.path, 'pgp');
  final sshDir = _joinPath(supportDir.path, 'ssh');
  final storeBaseDir = _joinPath(supportDir.path, 'stores');
  await Directory(keyringHome).create(recursive: true);
  await Directory(sshDir).create(recursive: true);
  await Directory(storeBaseDir).create(recursive: true);
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
    sshDir: sshDir,
    storeBaseDir: storeBaseDir,
  );
}

String _joinPath(String parent, String child) {
  final separator = Platform.pathSeparator;
  if (parent.endsWith(separator)) {
    return '$parent$child';
  }
  return '$parent$separator$child';
}

Future<Directory> _mobileSupportDirectory(PgpRuntimeEnvironment runtime) async {
  final defaultDir = await runtime.supportDirectory();
  if (!Platform.isIOS) {
    return defaultDir;
  }
  try {
    final sharedPath = await _iosRuntimeChannel.invokeMethod<String>(
      'appGroupSupportPath',
    );
    if (sharedPath == null || sharedPath.trim().isEmpty) {
      return defaultDir;
    }
    final sharedDir = Directory(sharedPath);
    await sharedDir.create(recursive: true);
    await _copyDirectoryIfNeeded(defaultDir, sharedDir);
    return sharedDir;
  } on MissingPluginException {
    return defaultDir;
  }
}

Future<void> _copyDirectoryIfNeeded(Directory source, Directory target) async {
  if (!await source.exists()) {
    return;
  }
  if (source.absolute.path == target.absolute.path) {
    return;
  }
  await for (final entity in source.list(recursive: true)) {
    final relativePath = entity.path.substring(source.path.length);
    if (relativePath.isEmpty) {
      continue;
    }
    final destinationPath = '${target.path}$relativePath';
    if (entity is Directory) {
      await Directory(destinationPath).create(recursive: true);
    } else if (entity is File) {
      final destination = File(destinationPath);
      if (!await destination.exists()) {
        await destination.parent.create(recursive: true);
        await entity.copy(destination.path);
      }
    }
  }
}
