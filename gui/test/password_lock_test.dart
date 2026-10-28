import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/screens/onboarding/onboarding_screen.dart';
import 'package:pars_gui/screens/security/lock_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/widgets/gesture_lock_input.dart';

import 'support/gui_test_harness.dart';

const _testIterations = 1000;
const _password = 'correct horse';

final _desktop = TargetPlatformVariant.desktop();

void main() {
  testWidgets('desktop onboarding sets a password instead of a gesture', (
    tester,
  ) async {
    await configureGuiTestViewport(tester, viewport: GuiTestViewport.expanded);
    final security = InMemorySecurityRepository(
      passwordIterations: _testIterations,
    );
    await tester.pumpWidget(_app(security));
    await tester.pumpAndSettle();

    expect(find.text('Set app password'), findsOneWidget);
    expect(find.byType(GestureLockInput), findsNothing);

    await _enterNewPassword(tester, 'short', 'short');
    expect(find.text('At least 6 characters'), findsOneWidget);
    expect(security.hasUnlockVerifier, isFalse);

    await _enterNewPassword(tester, _password, 'correct horsf');
    expect(find.text('Passwords did not match.'), findsOneWidget);
    expect(security.hasUnlockVerifier, isFalse);

    await _enterNewPassword(tester, _password, _password);
    expect(find.text('Enable biometric unlock'), findsWidgets);
    expect(
      find.text('Biometrics are optional and keep the password as fallback.'),
      findsOneWidget,
    );
    expect(security.unlockMethod, LocalUnlockMethod.password);
    expect(await security.verifyPassword(_password), isTrue);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Set app password'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('phone onboarding keeps the gesture lock', (tester) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(_app(InMemorySecurityRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.byType(GestureLockInput), findsOneWidget);
    expect(find.text('Set app password'), findsNothing);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('password lock screen rejects a wrong password', (tester) async {
    await configureGuiTestViewport(tester, viewport: GuiTestViewport.expanded);
    final security = InMemorySecurityRepository(
      passwordVerifier: PasswordVerifier.fromPassword(
        _password,
        iterations: _testIterations,
      ),
      onboardingComplete: true,
    );
    await tester.pumpWidget(_app(security));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Pars'), findsOneWidget);
    expect(
      find.text('Enter your password to open the local app session.'),
      findsOneWidget,
    );
    expect(find.byType(GestureLockInput), findsNothing);

    await tester.enterText(
      find.byKey(const Key('unlock-password-field')),
      'wrong password',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Incorrect password'), findsOneWidget);
    expect(find.text('Unlock Pars'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('unlock-password-field')),
      _password,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock Pars'), findsNothing);
    expect(security.shouldLock(DateTime.now()), isFalse);
  }, variant: _desktop);

  testWidgets('settings switches a gesture lock to a password', (tester) async {
    await configureGuiTestViewport(tester);
    final security = InMemorySecurityRepository(
      gestureVerifier: GestureVerifier.fromPattern(const <int>[0, 1, 2, 5]),
      passwordIterations: _testIterations,
      onboardingComplete: true,
      lastUnlockedAt: DateTime.now(),
    );
    await tester.pumpWidget(_app(security));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesture lock and biometrics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use password'));
    await tester.pumpAndSettle();
    await _enterNewPassword(tester, _password, _password);

    expect(security.unlockMethod, LocalUnlockMethod.password);
    expect(security.hasGestureVerifier, isFalse);
    expect(find.text('Password lock and biometrics'), findsWidgets);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Use gesture'), findsOneWidget);
  });

  for (final textScale in <double>[1, 2]) {
    testWidgets('desktop flow fits the minimum window at ${textScale}x text', (
      tester,
    ) async {
      await configureGuiTestViewport(
        tester,
        viewport: GuiTestViewport.desktopMinimum,
      );
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final security = InMemorySecurityRepository(
        passwordIterations: _testIterations,
      );
      await tester.pumpWidget(_app(security));
      await tester.pumpAndSettle();
      expect(find.text('Set app password'), findsOneWidget);
      expectNoFlutterOverflow(tester);

      await _enterNewPassword(tester, _password, _password);
      expect(find.text('Skip biometrics'), findsOneWidget);
      expectNoFlutterOverflow(tester);

      await tester.ensureVisible(find.text('Skip biometrics'));
      await tester.tap(find.text('Skip biometrics'));
      await tester.pumpAndSettle();
      expectNoFlutterOverflow(tester);

        await security.markLocked();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(security));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlock-password-field')), findsOneWidget);
      expectNoFlutterOverflow(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('password setup and unlock fit a phone at ${textScale}x text', (
      tester,
    ) async {
      await configureGuiTestViewport(tester);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          textScale: textScale,
          child: OnboardingScreen(
            onComplete: () {},
            securityRepository: InMemorySecurityRepository(
              passwordIterations: _testIterations,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set app password'), findsOneWidget);
      expectNoFlutterOverflow(tester);

      await tester.pumpWidget(
        buildLocalizedTestApp(
          textScale: textScale,
          child: LockScreen(
            securityRepository: InMemorySecurityRepository(
              passwordVerifier: PasswordVerifier.fromPassword(
                _password,
                iterations: _testIterations,
              ),
            ),
            unlockWithBiometrics: () async => false,
            onUnlocked: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlock-password-field')), findsOneWidget);
      expectNoFlutterOverflow(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}

Widget _app(SecurityRepository security) {
  const repository = FakeParsRepository();
  return ParsGuiApp(
    vaultRepository: repository,
    settingsRepository: repository,
    keyRepository: repository,
    gitRepository: repository,
    securityRepository: security,
  );
}

Future<void> _enterNewPassword(
  WidgetTester tester,
  String password,
  String confirmation,
) async {
  await tester.enterText(find.byKey(const Key('app-password-field')), password);
  await tester.enterText(
    find.byKey(const Key('app-password-confirmation-field')),
    confirmation,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
  await tester.pumpAndSettle();
}
