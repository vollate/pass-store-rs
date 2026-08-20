import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

enum AppLocalePreference {
  system('system'),
  english('en'),
  chinese('zh');

  const AppLocalePreference(this.storageValue);

  final String storageValue;

  Locale? get locale => switch (this) {
    AppLocalePreference.system => null,
    AppLocalePreference.english => const Locale('en'),
    AppLocalePreference.chinese => const Locale('zh'),
  };

  static AppLocalePreference parse(Object? value) {
    return values.firstWhere(
      (preference) => preference.storageValue == value,
      orElse: () => AppLocalePreference.system,
    );
  }
}

abstract interface class UiPreferencesStore {
  Future<AppLocalePreference> loadLocale();

  Future<void> saveLocale(AppLocalePreference preference);
}

class InMemoryUiPreferencesStore implements UiPreferencesStore {
  InMemoryUiPreferencesStore([this._preference = AppLocalePreference.system]);

  AppLocalePreference _preference;

  @override
  Future<AppLocalePreference> loadLocale() async => _preference;

  @override
  Future<void> saveLocale(AppLocalePreference preference) async {
    _preference = preference;
  }
}

class FileUiPreferencesStore implements UiPreferencesStore {
  const FileUiPreferencesStore(this.file);

  static const int schemaVersion = 1;

  final File file;

  @override
  Future<AppLocalePreference> loadLocale() async {
    try {
      if (!await file.exists()) return AppLocalePreference.system;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?> ||
          decoded['version'] != schemaVersion) {
        return AppLocalePreference.system;
      }
      return AppLocalePreference.parse(decoded['locale']);
    } catch (_) {
      return AppLocalePreference.system;
    }
  }

  @override
  Future<void> saveLocale(AppLocalePreference preference) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(
      '${jsonEncode(<String, Object>{'version': schemaVersion, 'locale': preference.storageValue})}\n',
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
