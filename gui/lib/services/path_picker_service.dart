import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _androidStoreImportChannel = MethodChannel(
  'top.vollate.pars_gui/store_import',
);

enum ManagedStoreConflictPolicy { replace, merge }

class ManagedStoreConflict {
  const ManagedStoreConflict({required this.destinationPath});

  final String destinationPath;
}

typedef ManagedStoreConflictResolver =
    Future<ManagedStoreConflictPolicy?> Function(ManagedStoreConflict conflict);

abstract interface class PathPickerService {
  Future<String?> pickFolder({required String initialDirectory});

  Future<String?> pickFile({required String initialDirectory});

  /// Lets the user choose a store and copies it into app-managed storage.
  ///
  /// Android must use the Storage Access Framework instead of converting the
  /// selected tree URI to a filesystem path. The returned path is always the
  /// copied, app-readable destination.
  Future<String?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
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
  Future<String?> importFolderToManagedStorage({
    required String destinationBaseDirectory,
    required ManagedStoreConflictResolver resolveConflict,
  }) async {
    if (Platform.isAndroid) {
      try {
        final selection = await _androidStoreImportChannel
            .invokeMapMethod<String, Object?>('pickDirectory', <String, Object>{
              'destinationBaseDirectory': destinationBaseDirectory,
            });
        if (selection == null) {
          return null;
        }
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
        var policy = ManagedStoreConflictPolicy.replace;
        if (destinationExists) {
          final selectedPolicy = await resolveConflict(
            ManagedStoreConflict(destinationPath: destinationPath),
          );
          if (selectedPolicy == null) {
            return null;
          }
          policy = selectedPolicy;
        }
        return await _androidStoreImportChannel
            .invokeMethod<String>('copyDirectory', <String, Object>{
              'destinationBaseDirectory': destinationBaseDirectory,
              'treeUri': treeUri,
              'existingStorePolicy': policy.name,
            });
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
    if (sourcePath == null) {
      return null;
    }
    final destinationPath = _managedDestinationPath(
      sourcePath: sourcePath,
      destinationBaseDirectory: destinationBaseDirectory,
    );
    var policy = ManagedStoreConflictPolicy.replace;
    if (await Directory(destinationPath).exists()) {
      final selectedPolicy = await resolveConflict(
        ManagedStoreConflict(destinationPath: destinationPath),
      );
      if (selectedPolicy == null) {
        return null;
      }
      policy = selectedPolicy;
    }
    return _copyFolderToManagedStorage(
      sourcePath: sourcePath,
      destinationBaseDirectory: destinationBaseDirectory,
      existingStorePolicy: policy,
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

Future<String> _copyFolderToManagedStorage({
  required String sourcePath,
  required String destinationBaseDirectory,
  required ManagedStoreConflictPolicy existingStorePolicy,
}) async {
  final source = Directory(sourcePath).absolute;
  if (!await source.exists()) {
    throw PathPickerException(
      "Selected store folder does not exist: '$sourcePath'.",
    );
  }

  final destinationBase = Directory(destinationBaseDirectory).absolute;
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
    throw PathPickerException(
      "The managed store destination is not a directory: '$destinationPath'.",
    );
  }

  await destinationBase.create(recursive: true);
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
    if (existingStorePolicy == ManagedStoreConflictPolicy.merge &&
        destinationType == FileSystemEntityType.directory) {
      await _copyDirectoryContents(
        source: Directory(destinationPath),
        destination: staging,
      );
    }
    final sourcePrefix = '${source.path}${Platform.pathSeparator}';
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final entityPath = entity.absolute.path;
      if (!entityPath.startsWith(sourcePrefix)) {
        throw PathPickerException(
          "Selected store contains an invalid path: '$entityPath'.",
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
        throw PathPickerException(
          "Selected store contains an unsupported symbolic link: '$entityPath'.",
        );
      }
    }
    if (destinationType == FileSystemEntityType.directory) {
      await Directory(destinationPath).rename(backup.path);
    }
    await staging.rename(destinationPath);
    if (await backup.exists()) {
      await backup.delete(recursive: true);
    }
    return destinationPath;
  } catch (error) {
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    if (await backup.exists() && !await Directory(destinationPath).exists()) {
      await backup.rename(destinationPath);
    }
    if (error is PathPickerException) {
      rethrow;
    }
    throw PathPickerException(
      "Failed to copy '$sourcePath' into app storage '$destinationPath': $error",
    );
  }
}

@visibleForTesting
Future<String> copyFolderToManagedStorageForTesting({
  required String sourcePath,
  required String destinationBaseDirectory,
  ManagedStoreConflictPolicy existingStorePolicy =
      ManagedStoreConflictPolicy.replace,
}) {
  return _copyFolderToManagedStorage(
    sourcePath: sourcePath,
    destinationBaseDirectory: destinationBaseDirectory,
    existingStorePolicy: existingStorePolicy,
  );
}

Future<void> _copyDirectoryContents({
  required Directory source,
  required Directory destination,
}) async {
  final sourcePrefix = '${source.absolute.path}${Platform.pathSeparator}';
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final entityPath = entity.absolute.path;
    if (!entityPath.startsWith(sourcePrefix)) {
      throw PathPickerException(
        "Managed store contains an invalid path: '$entityPath'.",
      );
    }
    final relativePath = entityPath.substring(sourcePrefix.length);
    final destinationPath = joinFilesystemPath(destination.path, relativePath);
    if (entity is Directory) {
      await Directory(destinationPath).create(recursive: true);
    } else if (entity is File) {
      final destinationFile = File(destinationPath);
      await destinationFile.parent.create(recursive: true);
      await entity.copy(destinationFile.path);
    } else {
      throw PathPickerException(
        "Managed store contains an unsupported symbolic link: '$entityPath'.",
      );
    }
  }
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

String slugFromRemoteUrl(String remoteUrl) {
  final withoutQuery = remoteUrl.trim().split('?').first.split('#').first;
  final normalized = withoutQuery.replaceAll(RegExp(r'/+$'), '');
  final lastSegment = normalized.split(RegExp(r'[:/\\]')).last;
  return slugPathSegment(
    lastSegment.replaceFirst(RegExp(r'\.git$', caseSensitive: false), ''),
  );
}
