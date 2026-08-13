import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/path_picker_service.dart';

void main() {
  test(
    'imports every selected file without requiring password files',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-import-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/empty-store');
      final destinationBase = Directory('${sandbox.path}/managed');
      await source.create();
      await File('${source.path}/.gpg-id').writeAsString('KEY-FINGERPRINT\n');
      await File('${source.path}/README.md').writeAsString('Empty for now.\n');
      await Directory('${source.path}/.git').create();
      await File('${source.path}/.git/config').writeAsString('[core]\n');

      final importedPath = await copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: destinationBase.path,
      );

      expect(File('$importedPath/.gpg-id').readAsStringSync(), contains('KEY'));
      expect(
        File('$importedPath/README.md').readAsStringSync(),
        'Empty for now.\n',
      );
      expect(File('$importedPath/.git/config').readAsStringSync(), '[core]\n');
      expect(
        Directory(importedPath)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.gpg')),
        isEmpty,
      );
    },
  );

  test('imports a selected folder without .gpg-id or .gpg files', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'pars-managed-store-import-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = Directory('${sandbox.path}/arbitrary-folder');
    final destinationBase = Directory('${sandbox.path}/managed');
    await source.create();
    await File('${source.path}/README.md').writeAsString('Copy me.\n');

    final importedPath = await copyFolderToManagedStorageForTesting(
      sourcePath: source.path,
      destinationBaseDirectory: destinationBase.path,
    );

    expect(File('$importedPath/README.md').readAsStringSync(), 'Copy me.\n');
    expect(File('$importedPath/.gpg-id').existsSync(), isFalse);
  });
}
