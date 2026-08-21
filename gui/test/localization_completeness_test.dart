import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English and Chinese ARB keys and placeholders stay in parity', () {
    final english = _readJson('lib/l10n/app_en.arb');
    final chinese = _readJson('lib/l10n/app_zh.arb');
    final englishKeys =
        english.keys.where((key) => !key.startsWith('@')).toSet();
    final chineseKeys =
        chinese.keys.where((key) => !key.startsWith('@')).toSet();

    expect(chineseKeys, englishKeys);
    for (final key in englishKeys) {
      expect(
        _placeholderNames(chinese['@$key']),
        _placeholderNames(english['@$key']),
        reason: 'Placeholder mismatch for $key',
      );
    }
  });

  test('production Text literals are classified machine data only', () {
    final allowed = <String, List<String>>{
      'lib/widgets/pgp_key_import_body.dart': <String>[
        r'${_kindLabel(context.l10n, inspection.kind)}\n',
      ],
      'lib/widgets/path_picker_row.dart': <String>[r'$pathPrefix: $path'],
      'lib/screens/settings/widgets/settings_git_widgets.dart': <String>[
        'git',
        r'git ${_argsText.trim()}',
        r'${remote.fetchUrl}\n${remote.pushUrl}',
      ],
    };
    final found = <String, List<String>>{};
    final pattern = RegExp(
      r'''(?:const\s+)?Text\(\s*(['"])(.*?)\1''',
      dotAll: true,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.contains('/bridge/frb_generated/') ||
          path.endsWith('/l10n/app_localizations.dart') ||
          path.contains('/l10n/app_localizations_')) {
        continue;
      }
      final values = pattern
          .allMatches(entity.readAsStringSync())
          .map((match) => match.group(2)!)
          .toList(growable: false);
      if (values.isNotEmpty) found[path] = values;
    }

    expect(found, allowed);
  });

  test('presentation properties contain no quoted English fallback', () {
    final findings = <String>[];
    final presentationLiteral = RegExp(
      r'''\b(labelText|helperText|tooltip|title|subtitle|buttonLabel|submitLabel)'''
      r'''\s*:\s*['"]([A-Za-z][^'"]*)['"]''',
    );
    final rawCaughtError = RegExp(
      r'''catch\s*\(\s*(\w+)\s*\)[\s\S]{0,400}?\1\.toString\(\)''',
    );
    for (final root in <Directory>[
      Directory('lib/screens'),
      Directory('lib/widgets'),
    ]) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in presentationLiteral.allMatches(source)) {
          findings.add('${entity.path}: ${match.group(0)}');
        }
        if (rawCaughtError.hasMatch(source)) {
          findings.add('${entity.path}: raw caught error.toString()');
        }
      }
    }
    expect(findings, isEmpty);
  });

  test('Android native English and Chinese strings stay in parity', () {
    final english = _androidStringKeys(
      'android/app/src/main/res/values/strings.xml',
    );
    final chinese = _androidStringKeys(
      'android/app/src/main/res/values-zh/strings.xml',
    );
    expect(chinese, english);
  });

  test('iOS English and zh-Hans resources stay in parity', () {
    for (final root in <String>['ios/Runner', 'ios/ParsCredentialProvider']) {
      for (final fileName in <String>[
        'InfoPlist.strings',
        'Localizable.strings',
      ]) {
        final english = File('$root/en.lproj/$fileName');
        final chinese = File('$root/zh-Hans.lproj/$fileName');
        if (!english.existsSync() && !chinese.existsSync()) continue;
        expect(english.existsSync(), isTrue, reason: english.path);
        expect(chinese.existsSync(), isTrue, reason: chinese.path);
        expect(
          _iosStringKeys(chinese),
          _iosStringKeys(english),
          reason: '$root/$fileName',
        );
      }
    }
  });
}

Map<String, Object?> _readJson(String path) {
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

Set<String> _placeholderNames(Object? metadata) {
  if (metadata is! Map) return const <String>{};
  final placeholders = metadata['placeholders'];
  if (placeholders is! Map) return const <String>{};
  return placeholders.keys.cast<String>().toSet();
}

Set<String> _androidStringKeys(String path) {
  final source = File(path).readAsStringSync();
  return RegExp(
    r'<string\s+name="([^"]+)"',
  ).allMatches(source).map((match) => match.group(1)!).toSet();
}

Set<String> _iosStringKeys(File file) {
  return RegExp(
    r'^\s*"([^"]+)"\s*=',
    multiLine: true,
  ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!).toSet();
}
