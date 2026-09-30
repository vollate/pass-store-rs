import 'dart:convert';

import '../models/git_sync.dart';
import 'security_repository.dart';

/// Keeps HTTPS tokens and SSH key passphrases in platform secure storage.
///
/// Remembered values survive restarts; values the user did not ask to
/// remember live only for this app process.
class GitCredentialStore {
  GitCredentialStore(this._storage);

  final SecureStorageAdapter? _storage;
  final Map<String, String> _sessionPassphrases = <String, String>{};

  static String httpsKey(String remoteUrl) =>
      'pars.git.https.${normalizedRemoteKey(remoteUrl)}';

  static String passphraseKey(String sshKeyName) =>
      'pars.git.ssh-passphrase.$sshKeyName';

  /// Drops userinfo, query, and fragment so the same remote maps to one key.
  static String normalizedRemoteKey(String remoteUrl) {
    var value = remoteUrl.trim().split(RegExp(r'[?#]')).first;
    final scheme = value.indexOf('://');
    if (scheme >= 0) {
      final authorityStart = scheme + 3;
      final slash = value.indexOf('/', authorityStart);
      final authorityEnd = slash < 0 ? value.length : slash;
      final at = value.lastIndexOf('@', authorityEnd);
      if (at >= authorityStart) {
        value =
            '${value.substring(0, authorityStart)}${value.substring(at + 1)}';
      }
    }
    return value.replaceAll(RegExp(r'/+$'), '').toLowerCase();
  }

  Future<HttpsCredentials?> readHttps(String remoteUrl) async {
    final storage = _storage;
    if (storage == null) return null;
    try {
      final raw = await storage.read(httpsKey(remoteUrl));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final username = decoded['username'];
      final token = decoded['token'];
      if (username is! String || token is! String || token.isEmpty) {
        return null;
      }
      return HttpsCredentials(username: username, token: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeHttps(String remoteUrl, HttpsCredentials credentials) {
    final storage = _storage;
    if (storage == null) return Future<void>.value();
    return storage.write(
      key: httpsKey(remoteUrl),
      value: jsonEncode(<String, String>{
        'username': credentials.username,
        'token': credentials.token,
      }),
    );
  }

  Future<void> deleteHttps(String remoteUrl) async {
    try {
      await _storage?.delete(httpsKey(remoteUrl));
    } catch (_) {
      // A stale entry is rejected again and deleted on the next attempt.
    }
  }

  Future<String?> readPassphrase(String sshKeyName) async {
    final session = _sessionPassphrases[sshKeyName];
    if (session != null) return session;
    try {
      return await _storage?.read(passphraseKey(sshKeyName));
    } catch (_) {
      return null;
    }
  }

  Future<void> writePassphrase(
    String sshKeyName,
    String passphrase, {
    required bool remember,
  }) async {
    _sessionPassphrases[sshKeyName] = passphrase;
    if (remember) {
      await _storage?.write(key: passphraseKey(sshKeyName), value: passphrase);
    }
  }

  Future<void> deletePassphrase(String sshKeyName) async {
    _sessionPassphrases.remove(sshKeyName);
    try {
      await _storage?.delete(passphraseKey(sshKeyName));
    } catch (_) {
      // Nothing to clean up when storage is unavailable.
    }
  }
}
