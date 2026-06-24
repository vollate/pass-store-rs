import 'security_repository.dart';

class RuntimeDiagnostics {
  const RuntimeDiagnostics({
    required this.bridgeLoaded,
    required this.coreVersion,
    required this.pgpBackend,
    required this.gitBackend,
    required this.keyStorageBackend,
    required this.nativeLibrary,
  });

  final bool bridgeLoaded;
  final String coreVersion;
  final String pgpBackend;
  final String gitBackend;
  final String keyStorageBackend;
  final String nativeLibrary;
}

abstract interface class RuntimeDiagnosticsRepository {
  RuntimeDiagnostics runtimeDiagnostics(SecurityRepository securityRepository);
}

String keyStorageBackendLabel(SecurityRepository securityRepository) {
  if (securityRepository is SecureStorageSecurityRepository) {
    return 'Flutter secure storage';
  }
  if (securityRepository is InMemorySecurityRepository) {
    return 'In-memory test storage';
  }
  return 'Custom security repository';
}
