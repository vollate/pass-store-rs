import 'dart:io';

import 'path_picker_service.dart';

String selectedSshKeyPath(String configPath) =>
    joinFilesystemPath(parentDirectory(configPath), 'selected_ssh_key');

Future<String?> loadSelectedSshKey(String configPath) async {
  try {
    final file = File(selectedSshKeyPath(configPath));
    if (!file.existsSync()) return null;
    final name = (await file.readAsString()).trim();
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) return null;
    return name;
  } catch (_) {
    return null;
  }
}

Future<void> saveSelectedSshKey(String configPath, String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.contains('/') || trimmed.contains(r'\')) {
    return;
  }
  final file = File(selectedSshKeyPath(configPath));
  await file.parent.create(recursive: true);
  await file.writeAsString('$trimmed\n');
}
