import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

abstract interface class PathPickerService {
  Future<String?> pickFolder({required String initialDirectory});

  Future<String?> pickFile({required String initialDirectory});
}

class PathPickerException implements Exception {
  const PathPickerException(this.message);

  final String message;

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
