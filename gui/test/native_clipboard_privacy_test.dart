import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android clipboard channel marks secrets and clears compatibly', () {
    final source =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/MainActivity.kt',
        ).readAsStringSync();

    expect(source, contains('top.vollate.pars_gui/sensitive_clipboard'));
    expect(source, contains('android.content.extra.IS_SENSITIVE'));
    expect(source, contains('clipboard.clearPrimaryClip()'));
    expect(source, contains('Build.VERSION_CODES.P'));
    expect(source, contains('expiresAfterSeconds'));
    expect(source, contains('clipboardHandler.postDelayed'));
    expect(source, contains('clearClipboardIfMatches'));
    expect(source, contains('parsClipboardLabel(ownerToken)'));
    expect(source, contains('currentLabel == parsClipboardLabel(ownerToken)'));
  });

  test('Android release window protects authenticated content', () {
    final source =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/MainActivity.kt',
        ).readAsStringSync();

    expect(source, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    expect(source, contains('WindowManager.LayoutParams.FLAG_SECURE'));
  });

  test('iOS clipboard channel is local-only and expiration-aware', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('top.vollate.pars_gui/sensitive_clipboard'));
    expect(source, contains('UIPasteboard.OptionsKey'));
    expect(source, contains('.localOnly: true'));
    expect(source, contains('options[.expirationDate]'));
    expect(source, contains('case "clearIfMatches"'));
    expect(source, contains('UIPasteboard.general.string == expected'));
    expect(source, contains('top.vollate.pars.clipboard-owner'));
    expect(source, contains('currentOwner == ownerToken'));
  });

  test('iOS covers app-switcher and active screen capture content', () {
    final source = File('ios/Runner/SceneDelegate.swift').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(source, contains('sceneWillResignActive'));
    expect(source, contains('sceneDidBecomeActive'));
    expect(source, contains('UIScreen.capturedDidChangeNotification'));
    expect(source, contains('showPrivacyCover()'));
    expect(source, contains('hidePrivacyCover()'));
    expect(info, contains(r'$(PRODUCT_MODULE_NAME).SceneDelegate'));
  });

  test('only the centralized service writes Flutter Clipboard directly', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('/services/sensitive_clipboard_service.dart')) continue;
      if (entity.readAsStringSync().contains('Clipboard.setData(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });
}
