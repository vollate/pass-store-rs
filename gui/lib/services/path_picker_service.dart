import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/frb_generated/api.dart' as frb;

const MethodChannel _androidStoreImportChannel = MethodChannel(
  'top.vollate.pars_gui/store_import',
);

enum ManagedStoreConflictPolicy { replace }

enum ManagedStoreGitDecision { initialize, continueWithoutGit, cancel }

enum ManagedStoreGitState { valid, absent, invalid }

class ManagedStoreConflict {
  const ManagedStoreConflict({required this.destinationPath});

  final String destinationPath;
}

typedef ManagedStoreConflictResolver =
    Future<ManagedStoreConflictPolicy?> Function(ManagedStoreConflict conflict);

typedef ManagedStoreGitDecisionResolver =
    Future<ManagedStoreGitDecision> Function(ManagedStoreGitState state);

class ManagedStoreImportTransaction {
  ManagedStoreImportTransaction({
    required this.root,
    required Future<void> Function() commit,
    required Future<void> Function() rollback,
  }) : _commit = commit,
       _rollback = rollback;

  final String root;
  final Future<void> Function() _commit;
  final Future<void> Function() _rollback;
  bool _finished = false;

  Future<void> commit() async {
    if (_finished) return;
    await _commit();
    _finished = true;
  }

  Future<void> rollback() async {
    if (_finished) return;
    await _rollback();
    _finished = true;
  }
}

/// Registers an installed store, commits its backup cleanup, then refreshes.
///
/// Only registration failure can roll back the filesystem. Once registration
/// persists canonical config, cleanup and refresh failures are post-registration
/// outcomes and must never restore or remove the registered destination.
Future<void> completeManagedStoreImport({
  required ManagedStoreImportTransaction transaction,
  required Future<void> Function(String root) register,
  required Future<void> Function() refresh,
}) async {
  try {
    await register(transaction.root);
  } catch (registrationError, registrationStack) {
    try {
      await transaction.rollback();
    } catch (_) {
      throw const PathPickerException(
        'Store registration failed and the previous store could not be restored.',
        code: 'store_import_rollback_failed',
      );
    }
    Error.throwWithStackTrace(registrationError, registrationStack);
  }

  Object? cleanupError;
  try {
    await transaction.commit();
  } catch (error) {
    cleanupError = error;
  }

  Object? refreshError;
  StackTrace? refreshStack;
  try {
    await refresh();
  } catch (error, stack) {
    refreshError = error;
    refreshStack = stack;
  }

  if (cleanupError != null) {
    throw const PathPickerException(
      'The imported store is active, but its backup could not be cleaned up.',
      code: 'store_import_cleanup_failed',
    );
  }
  if (refreshError != null) {
    Error.throwWithStackTrace(refreshError, refreshStack!);
  }
}

@visibleForTesting
Future<T> finalizeAndroidStagedImportForTesting<T>({
  required Future<T> Function() finalize,
  required Future<void> Function() rollback,
}) async {
  try {
    return await finalize();
  } catch (finalizeError, finalizeStack) {
    try {
      await rollback();
    } catch (_) {
      throw const PathPickerException(
        'Android import finalization failed and rollback could not be verified.',
        code: 'store_import_rollback_failed',
      );
    }
    Error.throwWithStackTrace(finalizeError, finalizeStack);
  }
}

abstract interface class PathPickerService {
  Future<String?> pickFolder({required String initialDirectory});

  Future<String?> pickFile({required String initialDirectory});

  /// Lets the user choose a store and copies it into app-managed storage.
  ///
  /// Android must use the Storage Access Framework instead of converting the
  /// selected tree URI to a filesystem path. The returned path is always the
  /// copied, app-readable destination.
  Future<ManagedStoreImportTransaction?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
    required ManagedStoreGitDecisionResolver resolveMissingGit,
  });
}

class PathPickerException implements Exception {
  const PathPickerException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class SystemPathPickerService implements PathPickerService {
  const SystemPathPickerService();

  @override
  Future<String?> pickFolder({required String initialDirectory}) async {
    try {
      return await getDirectoryPath(initialDirectory: initialDirectory);
    } on UnimplementedError catch (error) {
      throw PathPickerException(error.message ?? 'Folder picker unavailable.');
    } on MissingPluginException {
      throw const PathPickerException('Folder picker unavailable.');
    } on PlatformException catch (error) {
      throw PathPickerException(error.message ?? 'Folder picker failed.');
    }
  }

  @override
  Future<String?> pickFile({required String initialDirectory}) async {
    try {
      final file = await openFile(initialDirectory: initialDirectory);
      return file?.path;
    } on UnimplementedError catch (error) {
      throw PathPickerException(error.message ?? 'File picker unavailable.');
    } on MissingPluginException {
      throw const PathPickerException('File picker unavailable.');
    } on PlatformException catch (error) {
      throw PathPickerException(error.message ?? 'File picker failed.');
    }
  }

  @override
  Future<ManagedStoreImportTransaction?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
    required ManagedStoreGitDecisionResolver resolveMissingGit,
  }) async {
    if (Platform.isAndroid) {
      try {
        final selection = await _androidStoreImportChannel
            .invokeMapMethod<String, Object?>('pickDirectory', <String, Object>{
              'destinationBaseDirectory': destinationBaseDirectory,
            });
        if (selection == null) return null;
        final treeUri = selection['treeUri'];
        final destinationPath = selection['destinationPath'];
        final destinationExists = selection['destinationExists'];
        if (treeUri is! String ||
            destinationPath is! String ||
            destinationExists is! bool) {
          throw const PathPickerException(
            'Android returned an invalid managed store selection.',
          );
        }
        if (destinationExists) {
          final policy = await resolveConflict(
            ManagedStoreConflict(destinationPath: destinationPath),
          );
          if (policy == null) return null;
        }
        final stage = await _androidStoreImportChannel
            .invokeMapMethod<String, Object?>(
              'stageDirectory',
              <String, Object>{
                'destinationBaseDirectory': destinationBaseDirectory,
                'treeUri': treeUri,
              },
            );
        if (stage == null ||
            stage['handle'] is! String ||
            stage['stagingPath'] is! String) {
          throw const PathPickerException(
            'Android returned an invalid staged store.',
          );
        }
        final handle = stage['handle']! as String;
        final stagingPath = stage['stagingPath']! as String;
        bool proceed;
        try {
          proceed = await _prepareStagedGit(stagingPath, resolveMissingGit);
        } catch (error, stack) {
          try {
            await _androidStoreImportChannel.invokeMethod<void>(
              'cancelStagedDirectory',
              <String, Object>{'handle': handle},
            );
          } catch (_) {
            throw const PathPickerException(
              'Android import staging could not be cleaned up.',
              code: 'store_import_cleanup_failed',
            );
          }
          Error.throwWithStackTrace(error, stack);
        }
        if (!proceed) {
          await _androidStoreImportChannel.invokeMethod<void>(
            'cancelStagedDirectory',
            <String, Object>{'handle': handle},
          );
          return null;
        }

        final root = await finalizeAndroidStagedImportForTesting<String>(
          finalize: () async {
            final value = await _androidStoreImportChannel.invokeMethod<String>(
              'finalizeStagedDirectory',
              <String, Object>{'handle': handle},
            );
            if (value == null) {
              throw const PathPickerException(
                'Android failed to finalize import.',
                code: 'store_import_finalize_failed',
              );
            }
            return value;
          },
          rollback:
              () => _androidStoreImportChannel.invokeMethod<void>(
                'rollbackStagedDirectory',
                <String, Object>{'handle': handle},
              ),
        );
        return ManagedStoreImportTransaction(
          root: root,
          commit:
              () => _androidStoreImportChannel.invokeMethod<void>(
                'commitStagedDirectory',
                <String, Object>{'handle': handle},
              ),
          rollback:
              () => _androidStoreImportChannel.invokeMethod<void>(
                'rollbackStagedDirectory',
                <String, Object>{'handle': handle},
              ),
        );
      } on MissingPluginException {
        throw const PathPickerException(
          'Managed store import is unavailable on this Android build.',
        );
      } on PlatformException catch (error) {
        throw PathPickerException(
          error.message ?? 'Failed to import the selected store folder.',
          code: error.code,
        );
      }
    }

    final sourcePath = await pickFolder(
      initialDirectory: defaultUserDirectory(),
    );
    if (sourcePath == null) return null;
    final destinationPath = _managedDestinationPath(
      sourcePath: sourcePath,
      destinationBaseDirectory: destinationBaseDirectory,
    );
    if (await Directory(destinationPath).exists()) {
      final policy = await resolveConflict(
        ManagedStoreConflict(destinationPath: destinationPath),
      );
      if (policy == null) return null;
    }
    return _copyFolderToManagedStorage(
      sourcePath: sourcePath,
      destinationBaseDirectory: destinationBaseDirectory,
      existingStorePolicy: ManagedStoreConflictPolicy.replace,
      resolveMissingGit: resolveMissingGit,
    );
  }
}

String _managedDestinationPath({
  required String sourcePath,
  required String destinationBaseDirectory,
}) {
  final source = Directory(sourcePath).absolute;
  final sourceName =
      source.path
          .replaceAll(RegExp(r'[\\/]+$'), '')
          .split(RegExp(r'[\\/]'))
          .last;
  return joinFilesystemPath(
    Directory(destinationBaseDirectory).absolute.path,
    slugPathSegment(sourceName),
  );
}

Future<String> _resolvePathThroughExistingAncestor(Directory directory) async {
  var cursor = directory.absolute;
  final missingSegments = <String>[];
  while (!await cursor.exists()) {
    final normalized = cursor.path.replaceAll(RegExp(r'[\\/]+$'), '');
    final segment = normalized.split(RegExp(r'[\\/]')).last;
    if (segment.isEmpty || cursor.parent.path == cursor.path) {
      throw const PathPickerException(
        'The managed store base is unavailable.',
        code: 'store_import_destination_invalid',
      );
    }
    missingSegments.insert(0, segment);
    cursor = cursor.parent;
  }
  var resolved = await cursor.resolveSymbolicLinks();
  for (final segment in missingSegments) {
    resolved = joinFilesystemPath(resolved, segment);
  }
  return Directory(resolved).absolute.path;
}

Future<ManagedStoreImportTransaction?> _copyFolderToManagedStorage({
  required String sourcePath,
  required String destinationBaseDirectory,
  required ManagedStoreConflictPolicy existingStorePolicy,
  required ManagedStoreGitDecisionResolver resolveMissingGit,
}) async {
  final source = Directory(sourcePath).absolute;
  if (!await source.exists()) {
    throw const PathPickerException(
      'The selected store folder is unavailable.',
      code: 'store_import_source_missing',
    );
  }

  final destinationBase = Directory(destinationBaseDirectory).absolute;
  final sourceCanonical = await source.resolveSymbolicLinks();
  final separator = Platform.pathSeparator;
  bool containsPath(String parent, String child) =>
      child == parent || child.startsWith('$parent$separator');

  // Resolve through the nearest existing ancestor before creating anything so
  // rejecting an overlapping destination cannot mutate the selected source.
  final prospectiveBase = await _resolvePathThroughExistingAncestor(
    destinationBase,
  );
  if (containsPath(sourceCanonical, prospectiveBase) ||
      containsPath(prospectiveBase, sourceCanonical)) {
    throw const PathPickerException(
      'The selected folder overlaps app-managed storage.',
      code: 'store_import_path_overlap',
    );
  }

  await destinationBase.create(recursive: true);
  final baseCanonical = await destinationBase.resolveSymbolicLinks();
  if (containsPath(sourceCanonical, baseCanonical) ||
      containsPath(baseCanonical, sourceCanonical)) {
    throw const PathPickerException(
      'The selected folder overlaps app-managed storage.',
      code: 'store_import_path_overlap',
    );
  }

  final destinationPath = _managedDestinationPath(
    sourcePath: sourcePath,
    destinationBaseDirectory: destinationBaseDirectory,
  );
  final destinationType = await FileSystemEntity.type(
    destinationPath,
    followLinks: false,
  );
  if (destinationType != FileSystemEntityType.notFound &&
      destinationType != FileSystemEntityType.directory) {
    throw const PathPickerException(
      'The managed store destination is unavailable.',
      code: 'store_import_destination_invalid',
    );
  }

  final staging = Directory(
    joinFilesystemPath(
      destinationBase.path,
      '.import-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  final backup = Directory(
    joinFilesystemPath(
      destinationBase.path,
      '.import-backup-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await staging.create();
  try {
    final sourcePrefix = '$sourceCanonical$separator';
    await for (final entity in Directory(
      sourceCanonical,
    ).list(recursive: true, followLinks: false)) {
      final entityPath = entity.absolute.path;
      if (!entityPath.startsWith(sourcePrefix)) {
        throw const PathPickerException(
          'The selected store contains an invalid path.',
          code: 'store_import_invalid_path',
        );
      }
      final relativePath = entityPath.substring(sourcePrefix.length);
      final destination = joinFilesystemPath(staging.path, relativePath);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        final destinationFile = File(destination);
        await destinationFile.parent.create(recursive: true);
        await entity.copy(destinationFile.path);
      } else {
        throw const PathPickerException(
          'The selected store contains an unsupported link.',
          code: 'store_import_link_unsupported',
        );
      }
    }
    final proceed = await _prepareStagedGit(staging.path, resolveMissingGit);
    if (!proceed) {
      await staging.delete(recursive: true);
      return null;
    }
    if (destinationType == FileSystemEntityType.directory) {
      await Directory(destinationPath).rename(backup.path);
    }
    await staging.rename(destinationPath);

    Future<void> restore() async {
      final destination = Directory(destinationPath);
      if (await destination.exists()) await destination.delete(recursive: true);
      if (await backup.exists()) {
        await backup.rename(destinationPath);
        if (!await destination.exists()) {
          throw const PathPickerException(
            'Failed to restore the previous password store.',
            code: 'store_import_rollback_failed',
          );
        }
      }
    }

    return ManagedStoreImportTransaction(
      root: destinationPath,
      commit: () async {
        if (await backup.exists()) {
          await backup.delete(recursive: true);
          if (await backup.exists()) {
            throw const PathPickerException(
              'Imported store is active but backup cleanup failed.',
              code: 'store_import_cleanup_failed',
            );
          }
        }
      },
      rollback: restore,
    );
  } catch (error) {
    if (await staging.exists()) await staging.delete(recursive: true);
    if (await backup.exists() && !await Directory(destinationPath).exists()) {
      await backup.rename(destinationPath);
    }
    if (error is PathPickerException) rethrow;
    throw const PathPickerException(
      'Failed to import the selected password store.',
      code: 'store_import_failed',
    );
  }
}

Future<bool> _prepareStagedGit(
  String stagingPath,
  ManagedStoreGitDecisionResolver resolveMissingGit,
) async {
  final state = await _inspectStagedGit(stagingPath);
  switch (state) {
    case ManagedStoreGitState.valid:
      return true;
    case ManagedStoreGitState.invalid:
      throw const PathPickerException(
        'The selected store contains invalid Git metadata.',
        code: 'store_import_git_invalid',
      );
    case ManagedStoreGitState.absent:
      final decision = await resolveMissingGit(state);
      switch (decision) {
        case ManagedStoreGitDecision.cancel:
          return false;
        case ManagedStoreGitDecision.continueWithoutGit:
          return true;
        case ManagedStoreGitDecision.initialize:
          await _initializeStagedGit(stagingPath);
          return true;
      }
  }
}

Future<ManagedStoreGitState> _inspectStagedGit(String stagingPath) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final response = await frb.inspectStoreGit(
      request: frb.InspectStoreGitRequest(root: stagingPath),
    );
    if (response.error != null) {
      throw PathPickerException(
        'Unable to inspect imported Git metadata.',
        code: 'store_import_git_inspection_failed',
      );
    }
    return switch (response.mode) {
      frb.StoreGitModeDto.disabled => ManagedStoreGitState.absent,
      frb.StoreGitModeDto.local ||
      frb.StoreGitModeDto.remote => ManagedStoreGitState.valid,
      frb.StoreGitModeDto.invalid => ManagedStoreGitState.invalid,
      null => ManagedStoreGitState.invalid,
    };
  }
  if (!await FileSystemEntity.isDirectory(
        joinFilesystemPath(stagingPath, '.git'),
      ) &&
      !await FileSystemEntity.isFile(joinFilesystemPath(stagingPath, '.git'))) {
    return ManagedStoreGitState.absent;
  }
  final result = await Process.run('git', const <String>[
    'rev-parse',
    '--is-inside-work-tree',
  ], workingDirectory: stagingPath);
  return result.exitCode == 0 && result.stdout.toString().trim() == 'true'
      ? ManagedStoreGitState.valid
      : ManagedStoreGitState.invalid;
}

Future<void> _initializeStagedGit(String stagingPath) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final response = await frb.initializeGitRepository(
      request: frb.InitializeGitRepositoryRequest(root: stagingPath),
    );
    if (response.error != null) {
      throw const PathPickerException(
        'Failed to initialize Git for the imported store.',
        code: 'store_import_git_init_failed',
      );
    }
    return;
  }
  final result = await Process.run('git', const <String>[
    'init',
  ], workingDirectory: stagingPath);
  if (result.exitCode != 0) {
    throw const PathPickerException(
      'Failed to initialize Git for the imported store.',
      code: 'store_import_git_init_failed',
    );
  }
}

@visibleForTesting
Future<ManagedStoreImportTransaction?> stageFolderToManagedStorageForTesting({
  required String sourcePath,
  required String destinationBaseDirectory,
  ManagedStoreGitDecisionResolver? resolveMissingGit,
}) => _copyFolderToManagedStorage(
  sourcePath: sourcePath,
  destinationBaseDirectory: destinationBaseDirectory,
  existingStorePolicy: ManagedStoreConflictPolicy.replace,
  resolveMissingGit:
      resolveMissingGit ??
      (_) async => ManagedStoreGitDecision.continueWithoutGit,
);

@visibleForTesting
Future<String?> copyFolderToManagedStorageForTesting({
  required String sourcePath,
  required String destinationBaseDirectory,
  ManagedStoreConflictPolicy existingStorePolicy =
      ManagedStoreConflictPolicy.replace,
  ManagedStoreGitDecisionResolver? resolveMissingGit,
}) async {
  final transaction = await _copyFolderToManagedStorage(
    sourcePath: sourcePath,
    destinationBaseDirectory: destinationBaseDirectory,
    existingStorePolicy: existingStorePolicy,
    resolveMissingGit:
        resolveMissingGit ??
        (_) async => ManagedStoreGitDecision.continueWithoutGit,
  );
  if (transaction == null) return null;
  await transaction.commit();
  return transaction.root;
}

String defaultUserDirectory() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.trim().isNotEmpty) {
    return home;
  }
  return Directory.current.path;
}

String parentDirectory(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) {
    return defaultUserDirectory();
  }
  final trimmed =
      normalized.length > 1 && normalized.endsWith('/')
          ? normalized.replaceFirst(RegExp(r'/+$'), '')
          : normalized;
  final index = trimmed.lastIndexOf('/');
  if (index <= 0) {
    return index == 0 ? '/' : defaultUserDirectory();
  }
  return trimmed.substring(0, index);
}

String joinFilesystemPath(String base, String child) {
  final cleanBase = base.trim().replaceAll(RegExp(r'[\\/]+$'), '');
  final cleanChild = child.trim().replaceAll(RegExp(r'^[\\/]+'), '');
  if (cleanBase.isEmpty) {
    return cleanChild;
  }
  if (cleanChild.isEmpty) {
    return cleanBase;
  }
  return '$cleanBase/$cleanChild';
}

String slugPathSegment(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'store' : slug;
}

bool remoteUrlUsesSsh(String remoteUrl) {
  final value = remoteUrl.trim().toLowerCase();
  return value.startsWith('ssh://') ||
      (!value.contains('://') && value.contains('@') && value.contains(':'));
}

String slugFromRemoteUrl(String remoteUrl) {
  final withoutQuery = remoteUrl.trim().split('?').first.split('#').first;
  final normalized = withoutQuery.replaceAll(RegExp(r'/+$'), '');
  final lastSegment = normalized.split(RegExp(r'[:/\\]')).last;
  return slugPathSegment(
    lastSegment.replaceFirst(RegExp(r'\.git$', caseSensitive: false), ''),
  );
}
