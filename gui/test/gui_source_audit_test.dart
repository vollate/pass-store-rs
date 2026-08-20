import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _initialHardCodedTextBaseline = 8;
const _initialRawErrorBaseline = 6;
const _initialDirectClipboardBaseline = 0;

void main() {
  test('GUI source debt does not exceed the recorded redesign baseline', () {
    final audit = _auditProductionGui();

    expect(
      audit.hardCodedTextLiterals,
      lessThanOrEqualTo(_initialHardCodedTextBaseline),
      reason: audit.describe('hard-coded Text literals'),
    );
    expect(
      audit.rawErrorInterpolations,
      lessThanOrEqualTo(_initialRawErrorBaseline),
      reason: audit.describe('raw error interpolations'),
    );
    expect(
      audit.directClipboardWrites,
      lessThanOrEqualTo(_initialDirectClipboardBaseline),
      reason: audit.describe('direct clipboard writes'),
    );
    expect(
      audit.emptyActionCallbacks,
      0,
      reason: audit.describe('literal empty action callbacks'),
    );
    expect(
      audit.findings.where(
        (finding) =>
            finding.endsWith('raw error') &&
            (finding.startsWith('lib/screens/') ||
                finding.startsWith('lib/widgets/')),
      ),
      isEmpty,
      reason: 'Raw backend errors must not be rendered by UI surfaces.',
    );
  });
}

_GuiSourceAudit _auditProductionGui() {
  final lib = Directory('lib');
  expect(
    lib.existsSync(),
    isTrue,
    reason: 'Run from the Flutter package root.',
  );

  final textLiteral = RegExp(r'''(?<![A-Za-z])(?:const\s+)?Text\(\s*['"]''');
  final rawError = RegExp(
    r'''(?:error|exception)\.toString\(\)|\$error\b|_error\s*=\s*error\.toString''',
    caseSensitive: false,
  );
  final clipboardWrite = RegExp(r'''Clipboard\.setData\s*\(''');
  final emptyAction = RegExp(
    r'''\b(onPressed|onTap|onLongPress|onDoubleTap|onSecondaryTap|onSubmitted)'''
    r'''\s*:\s*(?:\([^)]*\)|[A-Za-z_]\w*)\s*(?:async\s*)?\{\s*\}''',
    multiLine: true,
  );

  var hardCodedTextLiterals = 0;
  var rawErrorInterpolations = 0;
  var directClipboardWrites = 0;
  var emptyActionCallbacks = 0;
  final findings = <String>[];

  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll('\\', '/');
    if (normalized.contains('/bridge/frb_generated/') ||
        normalized.endsWith('/l10n/app_localizations.dart') ||
        normalized.contains('/l10n/app_localizations_')) {
      continue;
    }
    final source = entity.readAsStringSync();
    final clipboardPattern =
        normalized.endsWith('/services/sensitive_clipboard_service.dart')
            ? RegExp(r'(?!)')
            : clipboardWrite;
    for (final item in <(String, RegExp, void Function())>[
      ('hard-coded Text', textLiteral, () => hardCodedTextLiterals++),
      ('raw error', rawError, () => rawErrorInterpolations++),
      ('direct clipboard', clipboardPattern, () => directClipboardWrites++),
      ('empty action', emptyAction, () => emptyActionCallbacks++),
    ]) {
      for (final match in item.$2.allMatches(source)) {
        item.$3();
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        findings.add('$normalized:$line ${item.$1}');
      }
    }
  }

  return _GuiSourceAudit(
    hardCodedTextLiterals: hardCodedTextLiterals,
    rawErrorInterpolations: rawErrorInterpolations,
    directClipboardWrites: directClipboardWrites,
    emptyActionCallbacks: emptyActionCallbacks,
    findings: findings,
  );
}

class _GuiSourceAudit {
  const _GuiSourceAudit({
    required this.hardCodedTextLiterals,
    required this.rawErrorInterpolations,
    required this.directClipboardWrites,
    required this.emptyActionCallbacks,
    required this.findings,
  });

  final int hardCodedTextLiterals;
  final int rawErrorInterpolations;
  final int directClipboardWrites;
  final int emptyActionCallbacks;
  final List<String> findings;

  String describe(String category) {
    final relevant = findings.where(
      (line) => line.endsWith(category) || line.contains(category),
    );
    return '$category exceeded its recorded baseline.\n${relevant.join('\n')}';
  }
}
