import 'package:flutter/widgets.dart';

enum RepoGitStatus {
  clean,
  needPull,
  uncommitted,
  syncFailed,
}

extension RepoGitStatusLabel on RepoGitStatus {
  String get label {
    switch (this) {
      case RepoGitStatus.clean:
        return 'Clean';
      case RepoGitStatus.needPull:
        return 'Need pull';
      case RepoGitStatus.uncommitted:
        return 'Uncommitted';
      case RepoGitStatus.syncFailed:
        return 'Sync failed';
    }
  }
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
