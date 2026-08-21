import 'package:flutter/widgets.dart';

enum RepoGitStatus {
  disabled,
  clean,
  needPull,
  uncommitted,
  invalid,
  syncFailed,
}

class PasswordEntry {
  const PasswordEntry({
    required this.path,
    required this.displayName,
    required this.repoName,
    required this.encryptedContent,
    this.isDirectory = false,
    this.childCount = 0,
    this.isFavorite = false,
    this.lastUsedLabel,
  });

  final String path;
  final String displayName;
  final String repoName;
  final String encryptedContent;
  final bool isDirectory;
  final int childCount;
  final bool isFavorite;
  final String? lastUsedLabel;

  PasswordEntry copyWith({bool? isFavorite, String? lastUsedLabel}) {
    return PasswordEntry(
      path: path,
      displayName: displayName,
      repoName: repoName,
      encryptedContent: encryptedContent,
      isDirectory: isDirectory,
      childCount: childCount,
      isFavorite: isFavorite ?? this.isFavorite,
      lastUsedLabel: lastUsedLabel ?? this.lastUsedLabel,
    );
  }

  String get parentPath {
    final index = path.lastIndexOf('/');
    if (index == -1) {
      return repoName;
    }
    return path.substring(0, index);
  }

  String get initials {
    if (displayName.isEmpty) {
      return '?';
    }
    return displayName.characters.first.toUpperCase();
  }
}

class ParsedSecretField {
  const ParsedSecretField({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

class SecretContent {
  const SecretContent({
    required this.password,
    required this.fields,
    required this.rawNotes,
  });

  final String password;
  final List<ParsedSecretField> fields;
  final String rawNotes;

  String? fieldValue(String key) {
    for (final field in fields) {
      if (field.key == key) {
        return field.value;
      }
    }
    return null;
  }
}

class EntryOperationResult {
  const EntryOperationResult({
    required this.path,
    required this.overwroteExisting,
    this.action = 'Saved',
    this.committed = false,
  });

  final String path;
  final bool overwroteExisting;
  final String action;
  final bool committed;

  EntryOperationResult copyWith({
    String? path,
    bool? overwroteExisting,
    String? action,
    bool? committed,
  }) {
    return EntryOperationResult(
      path: path ?? this.path,
      overwroteExisting: overwroteExisting ?? this.overwroteExisting,
      action: action ?? this.action,
      committed: committed ?? this.committed,
    );
  }

  String get summary {
    final overwrite = overwroteExisting ? ' (overwrote existing)' : '';
    final commit = committed ? ' and committed' : '';
    return '$action $path$overwrite$commit';
  }
}

class BatchOperationFailure {
  const BatchOperationFailure({required this.path, required this.message});

  final String path;
  final String message;
}

class BatchOperationResult {
  const BatchOperationResult({
    required this.action,
    required this.affectedPaths,
    this.failures = const <BatchOperationFailure>[],
    this.committed = false,
  });

  final String action;
  final List<String> affectedPaths;
  final List<BatchOperationFailure> failures;
  final bool committed;

  BatchOperationResult copyWith({bool? committed}) {
    return BatchOperationResult(
      action: action,
      affectedPaths: affectedPaths,
      failures: failures,
      committed: committed ?? this.committed,
    );
  }

  String get summary {
    final commit = committed ? ' and committed' : '';
    if (failures.isEmpty) {
      return '$action ${affectedPaths.length} entries$commit';
    }
    return '$action ${affectedPaths.length} entries$commit; ${failures.length} failed';
  }
}

class GitOperationResult {
  const GitOperationResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.success,
    this.exitCode,
  });

  final String command;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final bool success;
}
