import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production GUI action properties never use literal empty callbacks', () {
    final libDirectory = Directory('lib');
    expect(
      libDirectory.existsSync(),
      isTrue,
      reason: 'Run this test from the Flutter package root.',
    );

    final emptyAction = RegExp(
      r'\b(onPressed|onTap|onLongPress|onDoubleTap|onSecondaryTap|onSubmitted)'
      r'\s*:\s*(?:\([^)]*\)|[A-Za-z_]\w*)\s*(?:async\s*)?\{\s*\}',
      multiLine: true,
    );
    final findings = <String>[];

    for (final entity in libDirectory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (normalizedPath.contains('/bridge/frb_generated/')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final match in emptyAction.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        findings.add('$normalizedPath:$line: ${match.group(0)}');
      }
    }

    expect(
      findings,
      isEmpty,
      reason:
          'Actionable production controls must invoke a concrete callback, '
          'be disabled with null, or expose an unavailable state.\n'
          '${findings.join('\n')}',
    );
  });
}
