import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/screens/shell/shell_view_state.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/sensitive_clipboard_service.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets('compact shell exposes Vault and Settings and preserves query', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _CountingRepository();
    await tester.pumpWidget(_readyApp(repository));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
    expect(repository.refreshCount, 1);

    await tester.enterText(find.byType(TextField).first, 'github');
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Move'), findsNothing);
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vault').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'github',
    );
    expect(find.text('1 selected'), findsOneWidget);
    expect(repository.refreshCount, 1);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('wide shell uses NavigationRail', (tester) async {
    await configureGuiTestViewport(tester, viewport: GuiTestViewport.expanded);
    final repository = _CountingRepository();
    await tester.pumpWidget(_readyApp(repository));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Manage'), findsNothing);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('system back returns Settings to Vault before app exit', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _CountingRepository();
    await tester.pumpWidget(_readyApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('APPEARANCE'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Search by name or path'), findsOneWidget);
  });

  testWidgets('Lock now clears session and opens the lock screen', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _CountingRepository();
    final security = _readySecurity();
    final clipboardPlatform = _ShellClipboardPlatform();
    final autofill = _PublishingAutofillRepository();
    final clipboardService = SensitiveClipboardService(
      platform: clipboardPlatform,
      clearDelay: Duration.zero,
    );
    addTearDown(clipboardService.dispose);
    await clipboardService.copySecret('copied-before-lock');
    await security.startPgpSession(
      fingerprint: 'ABC',
      passphrase: 'session-only',
    );
    await tester.pumpWidget(
      _readyApp(
        repository,
        security: security,
        clipboardService: clipboardService,
        autofillRepository: autofill,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Lock now'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
    expect(security.hasActivePgpSession, isFalse);
    expect(clipboardPlatform.writes.last, isEmpty);
    expect(autofill.publishCount, greaterThan(0));
  });

  test('destination state owns query, directory, selection, and cleanup', () {
    final state = VaultDestinationState();
    addTearDown(state.dispose);

    state.setDirectory('work');
    state.setQuery('github');
    expect(state.directoryPath, isNull);
    state.enterSelection('github/alice');
    state.setSelected('github/bob', selected: true);
    expect(state.selectionMode, isTrue);
    expect(state.selectedPaths, <String>{'github/alice', 'github/bob'});

    state.clearSelection();
    expect(state.selectionMode, isFalse);
    expect(state.selectedPaths, isEmpty);
  });
}

Widget _readyApp(
  _CountingRepository repository, {
  InMemorySecurityRepository? security,
  SensitiveClipboardService? clipboardService,
  AutofillRepository? autofillRepository,
}) {
  return ParsGuiApp(
    vaultRepository: repository,
    settingsRepository: repository,
    keyRepository: repository,
    gitRepository: repository,
    securityRepository: security ?? _readySecurity(),
    clipboardService: clipboardService,
    autofillRepository: autofillRepository,
  );
}

InMemorySecurityRepository _readySecurity() {
  return InMemorySecurityRepository.withPattern(
    const <int>[0, 1, 2, 5],
    onboardingComplete: true,
    lastUnlockedAt: DateTime.now(),
  );
}

class _PublishingAutofillRepository extends FakeAutofillRepository {
  int publishCount = 0;

  @override
  Future<void> publishPlatformState() async {
    publishCount += 1;
  }
}

class _ShellClipboardPlatform implements SensitiveClipboardPlatform {
  final List<String> writes = <String>[];

  @override
  Future<void> clearIfMatches(
    String expectedText, {
    required String ownerToken,
  }) async {
    writes.add('');
  }

  @override
  Future<void> write(
    String text, {
    required bool sensitive,
    required String ownerToken,
    Duration? expiresAfter,
  }) async {
    writes.add(text);
  }
}

class _CountingRepository extends FakeParsRepository {
  int refreshCount = 0;

  @override
  Future<void> refresh() async {
    refreshCount += 1;
  }
}
