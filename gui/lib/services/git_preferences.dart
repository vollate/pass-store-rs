import 'dart:convert';
import 'dart:io';

import '../models/git_sync.dart';
import 'path_picker_service.dart';

String gitPreferencesPath(String configPath) =>
    joinFilesystemPath(parentDirectory(configPath), 'git_preferences.json');

Future<GitPreferences> loadGitPreferences(String configPath) async {
  try {
    final file = File(gitPreferencesPath(configPath));
    if (!file.existsSync()) return const GitPreferences();
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return const GitPreferences();
    return GitPreferences(
      commitEveryChange: decoded['commitEveryChange'] != false,
      checkRemoteOnLaunch: decoded['checkRemoteOnLaunch'] != false,
      strategy:
          decoded['strategy'] == 'merge'
              ? GitIntegrationStrategy.merge
              : GitIntegrationStrategy.rebase,
    );
  } catch (_) {
    return const GitPreferences();
  }
}

Future<void> saveGitPreferences(
  String configPath,
  GitPreferences preferences,
) async {
  final file = File(gitPreferencesPath(configPath));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode(<String, Object>{
      'commitEveryChange': preferences.commitEveryChange,
      'checkRemoteOnLaunch': preferences.checkRemoteOnLaunch,
      'strategy': preferences.strategy.name,
    }),
  );
}
