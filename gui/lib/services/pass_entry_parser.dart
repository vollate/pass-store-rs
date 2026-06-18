import '../models/password_entry.dart';

class PassEntryParser {
  static const Map<String, String> _knownLabels = <String, String>{
    'username': 'Username',
    'user': 'User',
    'login': 'Login',
    'email': 'Email',
    'url': 'URL',
    'website': 'Website',
    'totp': 'TOTP',
    'otp': 'OTP',
    'note': 'Note',
  };

  static SecretContent parse(String plainText) {
    final normalized = plainText.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final password = lines.isEmpty ? '' : lines.first;
    final fields = <ParsedSecretField>[];
    final rawNotes = <String>[];

    for (final line in lines.skip(1)) {
      final parsed = _parseField(line);
      if (parsed == null) {
        if (line.isNotEmpty) {
          rawNotes.add(line);
        }
      } else {
        fields.add(parsed);
      }
    }

    return SecretContent(
      password: password,
      fields: fields,
      rawNotes: rawNotes.join('\n'),
    );
  }

  static ParsedSecretField? _parseField(String line) {
    final separatorIndex = line.indexOf(':');
    if (separatorIndex <= 0) {
      return null;
    }

    final rawKey = line.substring(0, separatorIndex).trim();
    final key = rawKey.toLowerCase();
    final label = _knownLabels[key];
    if (label == null) {
      return null;
    }

    final value = line.substring(separatorIndex + 1).trim();
    if (value.isEmpty) {
      return null;
    }

    return ParsedSecretField(key: key, label: label, value: value);
  }
}
