import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/l10n/app_localizations_en.dart';
import 'package:pars_gui/l10n/app_localizations_zh.dart';
import 'package:pars_gui/services/path_picker_service.dart';

void main() {
  test(
    'Android key selection keeps the user location and reads it later',
    () async {
      const location = '/storage/emulated/0/Download/gh_vollate';
      final selected = selectedKeyFileFromOpenableResult(<Object?, Object?>{
        'location': location,
        'fileName': 'gh_vollate',
        'uri': 'content://documents/document/primary:Download/gh_vollate',
      }, (uri) async => 'material-for:$uri');

      expect(selected.location, location);
      expect(selected.fileName, 'gh_vollate');
      expect(
        await selected.readText(),
        'material-for:content://documents/document/primary:Download/gh_vollate',
      );
      expect(keyFileNameFromLocation(location), 'gh_vollate');
    },
  );

  test('provider fault and recovery prompt are localized', () {
    final english = AppLocalizationsEn();
    final chinese = AppLocalizationsZh();

    expect(english.storeImportProviderUnlistable, contains('Android'));
    expect(english.storeImportDirectAccessMessage, contains('folder provider'));
    expect(chinese.storeImportProviderUnlistable, contains('Android'));
    expect(chinese.storeImportDirectAccessMessage, contains('目录提供程序'));
  });

  test('working Android provider never invokes direct recovery', () async {
    var prompted = false;
    var requestedAccess = false;
    var direct = false;

    final result = await stageAndroidDirectoryWithRecoveryForTesting(
      providerStage: () async => <String, Object?>{'handle': 'provider'},
      resolveProviderFault: () async {
        prompted = true;
        return true;
      },
      requestDirectReadAccess: () async {
        requestedAccess = true;
        return true;
      },
      directStage: () async {
        direct = true;
        return <String, Object?>{'handle': 'direct'};
      },
    );

    expect(result?['handle'], 'provider');
    expect(prompted, isFalse);
    expect(requestedAccess, isFalse);
    expect(direct, isFalse);
  });

  test('declined provider recovery leaves direct access untouched', () async {
    var requestedAccess = false;
    var direct = false;

    await expectLater(
      stageAndroidDirectoryWithRecoveryForTesting(
        providerStage:
            () async =>
                throw PlatformException(
                  code: 'store_import_provider_unlistable',
                ),
        resolveProviderFault: () async => false,
        requestDirectReadAccess: () async {
          requestedAccess = true;
          return true;
        },
        directStage: () async {
          direct = true;
          return <String, Object?>{};
        },
      ),
      throwsA(
        isA<PathPickerException>().having(
          (error) => error.code,
          'code',
          'store_import_provider_unlistable',
        ),
      ),
    );
    expect(requestedAccess, isFalse);
    expect(direct, isFalse);
  });

  test('provider fault recovers only after access is granted', () async {
    var direct = false;

    final result = await stageAndroidDirectoryWithRecoveryForTesting(
      providerStage:
          () async =>
              throw PlatformException(code: 'store_import_provider_unlistable'),
      resolveProviderFault: () async => true,
      requestDirectReadAccess: () async => true,
      directStage: () async {
        direct = true;
        return <String, Object?>{'handle': 'direct'};
      },
    );

    expect(direct, isTrue);
    expect(result?['handle'], 'direct');
  });

  test('dismissed all-files settings preserves provider fault', () async {
    var direct = false;

    await expectLater(
      stageAndroidDirectoryWithRecoveryForTesting(
        providerStage:
            () async =>
                throw PlatformException(
                  code: 'store_import_provider_unlistable',
                ),
        resolveProviderFault: () async => true,
        requestDirectReadAccess: () async => false,
        directStage: () async {
          direct = true;
          return <String, Object?>{};
        },
      ),
      throwsA(
        isA<PathPickerException>().having(
          (error) => error.code,
          'code',
          'store_import_provider_unlistable',
        ),
      ),
    );
    expect(direct, isFalse);
  });

  test('remote transport detection only requires SSH keys for SSH URLs', () {
    expect(remoteUrlUsesSsh('git@example.com:org/pass.git'), isTrue);
    expect(remoteUrlUsesSsh('ssh://git@example.com/org/pass.git'), isTrue);
    expect(remoteUrlUsesSsh('https://example.com/org/pass.git'), isFalse);
    expect(remoteUrlUsesSsh('file:///tmp/pass.git'), isFalse);
  });

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
      final initialized = await Process.run('git', const <String>[
        'init',
      ], workingDirectory: source.path);
      expect(initialized.exitCode, 0);

      final importedPath = await copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: destinationBase.path,
      );
      expect(importedPath, isNotNull);
      final imported = importedPath!;

      expect(File('$imported/.gpg-id').readAsStringSync(), contains('KEY'));
      expect(
        File('$imported/README.md').readAsStringSync(),
        'Empty for now.\n',
      );
      expect(File('$imported/.git/config').existsSync(), isTrue);
      expect(
        Directory(imported)
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
    expect(importedPath, isNotNull);
    final imported = importedPath!;

    expect(File('$imported/README.md').readAsStringSync(), 'Copy me.\n');
    expect(File('$imported/.gpg-id').existsSync(), isFalse);
  });

  test('explicitly initializes missing Git in staging only', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'pars-managed-store-init-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = Directory('${sandbox.path}/local-only');
    await source.create();
    await File('${source.path}/.gpg-id').writeAsString('KEY\n');

    final importedPath = await copyFolderToManagedStorageForTesting(
      sourcePath: source.path,
      destinationBaseDirectory: '${sandbox.path}/managed',
      resolveMissingGit: (_) async => ManagedStoreGitDecision.initialize,
    );
    expect(importedPath, isNotNull);

    expect(Directory('${importedPath!}/.git').existsSync(), isTrue);
    expect(Directory('${source.path}/.git').existsSync(), isFalse);
  });

  test('invalid Git aborts without replacing the destination', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'pars-managed-store-invalid-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = Directory('${sandbox.path}/broken');
    final destination = Directory('${sandbox.path}/managed/broken');
    await source.create(recursive: true);
    await Directory('${source.path}/.git').create();
    await File('${source.path}/.git/HEAD').writeAsString('not-a-valid-head');
    await destination.create(recursive: true);
    await File('${destination.path}/sentinel').writeAsString('keep');

    await expectLater(
      copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: '${sandbox.path}/managed',
      ),
      throwsA(
        isA<PathPickerException>().having(
          (error) => error.code,
          'code',
          'store_import_git_invalid',
        ),
      ),
    );
    expect(File('${destination.path}/sentinel').readAsStringSync(), 'keep');
  });

  test(
    'valid Git import preserves history branch remote and dotfiles',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-git-history-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/history-store');
      await source.create();
      Future<void> git(List<String> args) async {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: source.path,
        );
        expect(
          result.exitCode,
          0,
          reason: '${args.join(' ')}: ${result.stderr}',
        );
      }

      await git(const <String>['init']);
      await git(const <String>['config', 'user.name', 'Pars Test']);
      await git(const <String>['config', 'user.email', 'pars@example.invalid']);
      await File('${source.path}/.gpg-id').writeAsString('KEY\n');
      await File('${source.path}/entry.gpg').writeAsString('ciphertext-one');
      await File('${source.path}/.pars-meta').writeAsString('dotfile');
      await git(const <String>['add', '-A']);
      await git(const <String>['commit', '-m', 'first']);
      await git(const <String>['checkout', '-b', 'mobile']);
      await File('${source.path}/entry.gpg').writeAsString('ciphertext-two');
      await git(const <String>['commit', '-am', 'second']);
      await git(const <String>[
        'remote',
        'add',
        'origin',
        'https://example.invalid/passwords.git',
      ]);

      final sourceHead =
          (await Process.run('git', const <String>[
            'rev-parse',
            'HEAD',
          ], workingDirectory: source.path)).stdout.toString().trim();
      final importedPath = await copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: '${sandbox.path}/managed',
      );
      expect(importedPath, isNotNull);
      final imported = importedPath!;
      final importedHead =
          (await Process.run('git', const <String>[
            'rev-parse',
            'HEAD',
          ], workingDirectory: imported)).stdout.toString().trim();
      final branch =
          (await Process.run('git', const <String>[
            'branch',
            '--show-current',
          ], workingDirectory: imported)).stdout.toString().trim();
      final remote =
          (await Process.run('git', const <String>[
            'remote',
            'get-url',
            'origin',
          ], workingDirectory: imported)).stdout.toString().trim();

      expect(importedHead, sourceHead);
      expect(branch, 'mobile');
      expect(remote, 'https://example.invalid/passwords.git');
      expect(File('$imported/.pars-meta').readAsStringSync(), 'dotfile');
      expect(
        (await Process.run('git', const <String>[
          'rev-list',
          '--count',
          'HEAD',
        ], workingDirectory: imported)).stdout.toString().trim(),
        '2',
      );
    },
  );

  test(
    'missing Git can continue locally without changing the source',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-local-only-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/local-only');
      await source.create();
      await File('${source.path}/.gpg-id').writeAsString('KEY\n');
      await File('${source.path}/entry.gpg').writeAsString('ciphertext');

      final imported = await copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: '${sandbox.path}/managed',
        resolveMissingGit:
            (_) async => ManagedStoreGitDecision.continueWithoutGit,
      );

      expect(imported, isNotNull);
      final importedPath = imported!;
      expect(File('$importedPath/entry.gpg').existsSync(), isTrue);
      expect(File('$importedPath/.git').existsSync(), isFalse);
      expect(File('${source.path}/.git').existsSync(), isFalse);
    },
  );

  test(
    'cancelling missing Git removes staging and preserves destination',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-cancel-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/cancel-store');
      final managed = Directory('${sandbox.path}/managed');
      final destination = Directory('${managed.path}/cancel-store');
      await source.create(recursive: true);
      await File('${source.path}/.gpg-id').writeAsString('KEY\n');
      await destination.create(recursive: true);
      await File('${destination.path}/sentinel').writeAsString('keep');

      final imported = await copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: managed.path,
        resolveMissingGit: (_) async => ManagedStoreGitDecision.cancel,
      );

      expect(imported, isNull);
      expect(File('${destination.path}/sentinel').readAsStringSync(), 'keep');
      expect(
        managed.listSync().where((entry) => entry.path.contains('.import-')),
        isEmpty,
      );
    },
  );

  test(
    'registration failure rollback restores the prior destination',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-rollback-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/rollback-store');
      final managed = Directory('${sandbox.path}/managed');
      final destination = Directory('${managed.path}/rollback-store');
      await source.create(recursive: true);
      await File('${source.path}/.gpg-id').writeAsString('NEW\n');
      await destination.create(recursive: true);
      await File('${destination.path}/sentinel').writeAsString('old');

      final transaction = await stageFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: managed.path,
      );
      expect(transaction, isNotNull);
      expect(File('${destination.path}/.gpg-id').readAsStringSync(), 'NEW\n');

      await transaction!.rollback();

      expect(File('${destination.path}/sentinel').readAsStringSync(), 'old');
      expect(File('${destination.path}/.gpg-id').existsSync(), isFalse);
      expect(
        managed.listSync().where((entry) => entry.path.contains('.import-')),
        isEmpty,
      );
    },
  );

  test(
    'source overlapping managed storage is rejected before staging',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-overlap-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/source');
      final managed = Directory('${source.path}/managed');
      await source.create(recursive: true);
      await File('${source.path}/.gpg-id').writeAsString('KEY\n');

      final before =
          source.listSync(recursive: true).map((entry) => entry.path).toList();
      final beforeGpgId = File('${source.path}/.gpg-id').readAsBytesSync();
      await expectLater(
        stageFolderToManagedStorageForTesting(
          sourcePath: source.path,
          destinationBaseDirectory: managed.path,
        ),
        throwsA(
          isA<PathPickerException>().having(
            (error) => error.code,
            'code',
            'store_import_path_overlap',
          ),
        ),
      );
      expect(managed.existsSync(), isFalse);
      expect(
        source.listSync(recursive: true).map((entry) => entry.path),
        before,
      );
      expect(File('${source.path}/.gpg-id').readAsBytesSync(), beforeGpgId);
    },
  );

  test(
    'replacement is atomic and removes the prior destination only on success',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'pars-managed-store-replace-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = Directory('${sandbox.path}/replace-store');
      final destination = Directory('${sandbox.path}/managed/replace-store');
      await source.create(recursive: true);
      await File('${source.path}/.gpg-id').writeAsString('NEW\n');
      await destination.create(recursive: true);
      await File('${destination.path}/sentinel').writeAsString('old');

      final imported = await copyFolderToManagedStorageForTesting(
        sourcePath: source.path,
        destinationBaseDirectory: '${sandbox.path}/managed',
        resolveMissingGit:
            (_) async => ManagedStoreGitDecision.continueWithoutGit,
      );

      expect(imported, destination.path);
      expect(File('${destination.path}/sentinel').existsSync(), isFalse);
      expect(File('${destination.path}/.gpg-id').readAsStringSync(), 'NEW\n');
      expect(
        Directory(
          '${sandbox.path}/managed',
        ).listSync().where((entry) => entry.path.contains('.import-backup-')),
        isEmpty,
      );
    },
  );

  test(
    'registration failure rolls back before config becomes canonical',
    () async {
      var rolledBack = false;
      var committed = false;
      var refreshed = false;
      final transaction = ManagedStoreImportTransaction(
        root: '/managed/store',
        commit: () async => committed = true,
        rollback: () async => rolledBack = true,
      );

      await expectLater(
        completeManagedStoreImport(
          transaction: transaction,
          register: (_) async => throw StateError('registration failed'),
          refresh: () async => refreshed = true,
        ),
        throwsStateError,
      );

      expect(rolledBack, isTrue);
      expect(committed, isFalse);
      expect(refreshed, isFalse);
    },
  );

  test('refresh failure after registration never rolls back', () async {
    var registered = false;
    var rolledBack = false;
    var committed = false;
    final transaction = ManagedStoreImportTransaction(
      root: '/managed/store',
      commit: () async => committed = true,
      rollback: () async => rolledBack = true,
    );

    await expectLater(
      completeManagedStoreImport(
        transaction: transaction,
        register: (_) async => registered = true,
        refresh: () async => throw StateError('refresh failed'),
      ),
      throwsStateError,
    );

    expect(registered, isTrue);
    expect(committed, isTrue);
    expect(rolledBack, isFalse);
  });

  test(
    'backup cleanup failure is post-registration and never rolls back',
    () async {
      var rolledBack = false;
      var refreshed = false;
      final transaction = ManagedStoreImportTransaction(
        root: '/managed/store',
        commit: () async => throw StateError('cleanup failed'),
        rollback: () async => rolledBack = true,
      );

      await expectLater(
        completeManagedStoreImport(
          transaction: transaction,
          register: (_) async {},
          refresh: () async => refreshed = true,
        ),
        throwsA(
          isA<PathPickerException>().having(
            (error) => error.code,
            'code',
            'store_import_cleanup_failed',
          ),
        ),
      );

      expect(rolledBack, isFalse);
      expect(refreshed, isTrue);
    },
  );

  test('ambiguous Android finalization failure invokes rollback', () async {
    var installed = false;
    var rolledBack = false;

    await expectLater(
      finalizeAndroidStagedImportForTesting<String>(
        finalize: () async {
          installed = true;
          throw StateError('channel response lost');
        },
        rollback: () async {
          expect(installed, isTrue);
          rolledBack = true;
        },
      ),
      throwsStateError,
    );

    expect(rolledBack, isTrue);
  });

  test('ambiguous Android rollback failure is not swallowed', () async {
    await expectLater(
      finalizeAndroidStagedImportForTesting<String>(
        finalize: () async => throw StateError('channel response lost'),
        rollback: () async => throw StateError('rollback failed'),
      ),
      throwsA(
        isA<PathPickerException>().having(
          (error) => error.code,
          'code',
          'store_import_rollback_failed',
        ),
      ),
    );
  });
}
