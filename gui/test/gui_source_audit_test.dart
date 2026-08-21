import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _initialHardCodedTextBaseline = 8;
const _initialRawErrorBaseline = 6;
const _initialDirectClipboardBaseline = 0;

void main() {
  test('mobile advanced Git args remain unavailable instead of emulated', () {
    final settings =
        File('lib/screens/settings/settings_screen.dart').readAsStringSync();
    final repository =
        File('lib/services/bridge_backed_repository.dart').readAsStringSync();

    expect(settings, contains('if (!Platform.isAndroid && !Platform.isIOS)'));
    expect(
      repository,
      contains('Advanced Git arguments are unavailable on mobile.'),
    );
    expect(repository, isNot(contains("args.first == 'remote'")));
  });

  test('store removal clears native Autofill identity and passphrase state', () {
    final autofill =
        File('lib/services/autofill_repository.dart').readAsStringSync();
    final androidActivity =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/MainActivity.kt',
        ).readAsStringSync();
    final androidState =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/autofill/ParsAutofillStateStore.kt',
        ).readAsStringSync();
    final ios =
        File('ios/Shared/ParsAutofillSharedState.swift').readAsStringSync();

    expect(autofill, contains("invokeMethod<void>('clearState')"));
    expect(autofill, contains('_serializePlatformState'));
    expect(autofill, contains('_isCapturedStoreReady(capturedRoot)'));
    expect(autofill, contains('This final tombstone wins'));
    expect(androidActivity, contains('ParsAutofillStateStore.clear(this)'));
    expect(androidState, contains('putBoolean(KEY_ENABLED, false)'));
    expect(androidState, contains('.commit()'));
    expect(ios, contains('enabled: false'));
    expect(ios, contains('removeAllCredentialIdentities'));
    expect(ios, contains('deletePassphrase()'));
  });

  test('device evidence harness stays out of production packaging', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final productionManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(pubspec, isNot(contains('integration_test:')));
    expect(
      productionManifest,
      isNot(contains('SyntheticStoreDocumentsProvider')),
    );
    expect(
      File('tool/run_single_store_device_evidence.sh').existsSync(),
      isTrue,
    );
  });

  test(
    'permanent PGP settings and onboarding recipient append stay removed',
    () {
      final settings =
          File('lib/screens/settings/settings_screen.dart').readAsStringSync();
      final onboarding =
          File(
            'lib/screens/onboarding/onboarding_screen.dart',
          ).readAsStringSync();

      expect(
        settings,
        isNot(contains('_showKeys(context, KeyRecordType.pgp)')),
      );
      expect(onboarding, isNot(contains('addPgpKeyToSelectedStore')));
      expect(onboarding, isNot(contains('_OnboardingStep.ssh')));
      expect(onboarding, isNot(contains('_OnboardingStep.review')));
    },
  );

  test('single-store and contextual-key contracts cannot regress', () {
    final lifecycle =
        File('lib/services/store_lifecycle.dart').readAsStringSync();
    final settings =
        File('lib/screens/settings/settings_screen.dart').readAsStringSync();
    final storeUi =
        File(
          'lib/screens/settings/widgets/settings_store_widgets.dart',
        ).readAsStringSync();
    final keys = File('lib/services/key_repository.dart').readAsStringSync();

    for (final forbidden in <String>[
      'selectedStore',
      'List<StoreStatus> get stores',
      'selectStore',
      'isDefault',
      'hasGitRemote',
      'StoreOnboardingStateLabel',
      "return 'No config'",
      "return 'Store missing'",
    ]) {
      expect(lifecycle, isNot(contains(forbidden)));
    }
    expect(settings, isNot(contains('passwordStoresTitle')));
    final entryDetail =
        File('lib/screens/vault/entry_detail_sheet.dart').readAsStringSync();
    expect(entryDetail, isNot(contains('openPgpKeysHint')));
    expect(entryDetail, isNot(contains('openKeyManagement')));
    expect(storeUi, isNot(contains('_PasswordStoresSheetBody')));
    expect(storeUi, isNot(contains('Set default')));
    for (final forbidden in <String>[
      'exportPgpPublicKey',
      'exportPgpPrivateKey',
      'deletePgpKey',
      'addPgpKeyToSelectedStore',
    ]) {
      expect(keys, isNot(contains(forbidden)));
    }
  });

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
