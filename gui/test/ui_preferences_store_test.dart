import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/ui_preferences_store.dart';

void main() {
  test('file UI preferences round-trip locale atomically', () async {
    final directory = await Directory.systemTemp.createTemp('pars-ui-prefs-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/ui.json');
    final store = FileUiPreferencesStore(file);

    expect(await store.loadLocale(), AppLocalePreference.system);
    await store.saveLocale(AppLocalePreference.chinese);
    expect(await store.loadLocale(), AppLocalePreference.chinese);
    expect(await File('${file.path}.tmp').exists(), isFalse);

    await store.saveLocale(AppLocalePreference.english);
    expect(await store.loadLocale(), AppLocalePreference.english);
  });

  test('invalid or unreadable UI preferences fall back to system', () async {
    final directory = await Directory.systemTemp.createTemp('pars-ui-prefs-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/ui.json');
    final store = FileUiPreferencesStore(file);

    await file.writeAsString('{broken');
    expect(await store.loadLocale(), AppLocalePreference.system);

    await file.writeAsString('{"version":999,"locale":"zh"}');
    expect(await store.loadLocale(), AppLocalePreference.system);

    await file.writeAsString('{"version":1,"locale":"unsupported"}');
    expect(await store.loadLocale(), AppLocalePreference.system);
  });

  testWidgets('Pars app restores a stored locale preference', (tester) async {
    final store = InMemoryUiPreferencesStore(AppLocalePreference.chinese);

    await tester.pumpWidget(ParsGuiApp.fake(uiPreferencesStore: store));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('zh'));
  });

  testWidgets('Settings switches and persists locale without restarting', (
    tester,
  ) async {
    const repository = FakeParsRepository();
    final store = InMemoryUiPreferencesStore();
    final security = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      onboardingComplete: true,
      lastUnlockedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: security,
        uiPreferencesStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinese'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('zh'),
    );
    expect(await store.loadLocale(), AppLocalePreference.chinese);
    expect(find.text('设置'), findsWidgets);
  });
}
