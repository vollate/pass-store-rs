import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/screens/onboarding/onboarding_screen.dart';
import 'package:pars_gui/screens/security/lock_screen.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/widgets/biometric_icon.dart';
import 'package:pars_gui/widgets/pin_lock_input.dart';
import 'package:pars_gui/widgets/pin_setup_panel.dart';

import 'support/gui_test_harness.dart';

void main() {
  group('PinLockInput', () {
    testWidgets('auto-submits on the 6th digit and supports backspace', (
      tester,
    ) async {
      final completed = <String>[];
      await configureGuiTestViewport(tester);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: Center(child: PinLockInput(onCompleted: completed.add)),
        ),
      );

      await _tapDigits(tester, '12345');
      expect(completed, isEmpty);

      await tester.tap(find.byKey(const Key('pin-backspace-button')));
      await tester.pump();

      await _tapDigits(tester, '9');
      expect(completed, isEmpty);

      await _tapDigits(tester, '0');
      expect(completed, const <String>['123490']);
    });

    testWidgets('accepts hardware keyboard digits and backspace', (
      tester,
    ) async {
      final completed = <String>[];
      await configureGuiTestViewport(tester);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: Center(child: PinLockInput(onCompleted: completed.add)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();

      expect(completed, const <String>['198765']);
    });

    testWidgets('places biometric button in the bottom-left keypad row', (
      tester,
    ) async {
      var biometricTaps = 0;
      await configureGuiTestViewport(tester);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: Center(
            child: PinLockInput(
              onCompleted: (_) {},
              biometricKind: BiometricKind.face,
              onBiometricPressed: () => biometricTaps += 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bioRect = tester.getRect(
        find.byKey(const Key('pin-biometric-button')),
      );
      final zeroRect = tester.getRect(find.byKey(const Key('pin-key-0')));
      final sevenRect = tester.getRect(find.byKey(const Key('pin-key-7')));
      final eightRect = tester.getRect(find.byKey(const Key('pin-key-8')));
      final nineRect = tester.getRect(find.byKey(const Key('pin-key-9')));

      expect(bioRect.center.dy, closeTo(zeroRect.center.dy, 1));
      expect(bioRect.top, greaterThan(sevenRect.bottom));
      expect(bioRect.top, greaterThan(eightRect.bottom));
      expect(bioRect.top, greaterThan(nineRect.bottom));
      expect(bioRect.right, lessThan(zeroRect.left));

      await tester.tap(find.byKey(const Key('pin-biometric-button')));
      await tester.pump();
      expect(biometricTaps, 1);
    });
  });

  group('PinSetupPanel', () {
    testWidgets('captures, detects mismatch, resets, and saves 6-digit PIN', (
      tester,
    ) async {
      await configureGuiTestViewport(tester);
      final security = InMemorySecurityRepository();
      var savedCount = 0;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: PinSetupPanel(
            securityRepository: security,
            onSaved: () => savedCount += 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter a 6-digit PIN.'), findsOneWidget);

      await _tapDigits(tester, '123456');
      await tester.pumpAndSettle();
      expect(find.text('PIN entered. Confirm it once more.'), findsOneWidget);

      await _tapDigits(tester, '654321');
      await tester.pumpAndSettle();
      expect(find.text('PINs did not match. Start again.'), findsOneWidget);
      expect(security.hasPinVerifier, isFalse);

      await _tapDigits(tester, '246810');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Start again with a new PIN.'), findsOneWidget);

      await _tapDigits(tester, '135790');
      await tester.pumpAndSettle();
      await _tapDigits(tester, '135790');
      await tester.pumpAndSettle();

      expect(savedCount, 1);
      expect(security.hasPinVerifier, isTrue);
      expect(await security.verifyPin('135790'), isTrue);
      expect(await security.verifyPin('123456'), isFalse);
    });
  });

  group('LockScreen PIN and biometrics', () {
    testWidgets('rejects wrong PIN, clears digits, and unlocks on right PIN', (
      tester,
    ) async {
      await configureGuiTestViewport(tester);
      final security = InMemorySecurityRepository.withPin('123456');
      var unlocked = false;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: LockScreen(
            securityRepository: security,
            unlockWithBiometrics: () async => false,
            onUnlocked: () => unlocked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapDigits(tester, '000000');
      await tester.pumpAndSettle();
      expect(find.text('Incorrect PIN'), findsOneWidget);
      expect(unlocked, isFalse);

      await _tapDigits(tester, '123456');
      await tester.pumpAndSettle();
      expect(unlocked, isTrue);
    });

    for (final kind in <BiometricKind>[
      BiometricKind.face,
      BiometricKind.fingerprint,
    ]) {
      testWidgets(
        'PIN lock screen places ${kind.name} biometric button in bottom keypad row',
        (tester) async {
          await configureGuiTestViewport(tester);
          final security = InMemorySecurityRepository.withPin(
            '123456',
            biometricUnlockEnabled: true,
            biometricAvailable: true,
            biometricKind: kind,
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              child: LockScreen(
                securityRepository: security,
                unlockWithBiometrics: () async => false,
                onUnlocked: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final buttonFinder = find.byKey(const Key('pin-biometric-button'));
          expect(buttonFinder, findsOneWidget);

          final iconFinder = find.descendant(
            of: buttonFinder,
            matching: find.byType(BiometricIcon),
          );
          final icon = tester.widget<BiometricIcon>(iconFinder);
          expect(icon.kind, kind);
          if (kind == BiometricKind.face) {
            expect(
              find.descendant(
                of: iconFinder,
                matching: find.byType(CustomPaint),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: iconFinder,
                matching: find.byIcon(Icons.fingerprint),
              ),
              findsNothing,
            );
          } else {
            expect(
              find.descendant(
                of: iconFinder,
                matching: find.byIcon(Icons.fingerprint),
              ),
              findsOneWidget,
            );
          }

          final bioRect = tester.getRect(buttonFinder);
          final zeroRect = tester.getRect(find.byKey(const Key('pin-key-0')));
          final sevenRect = tester.getRect(find.byKey(const Key('pin-key-7')));
          expect(bioRect.center.dy, closeTo(zeroRect.center.dy, 1));
          expect(bioRect.top, greaterThan(sevenRect.bottom));
        },
      );

      testWidgets(
        'password lock screen places ${kind.name} biometric button near the bottom',
        (tester) async {
          await configureGuiTestViewport(tester);
          final security = InMemorySecurityRepository(
            passwordVerifier: PasswordVerifier.fromPassword(
              'correct horse',
              iterations: 1000,
            ),
            biometricUnlockEnabled: true,
            biometricAvailable: true,
            biometricKind: kind,
            onboardingComplete: true,
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              child: LockScreen(
                securityRepository: security,
                unlockWithBiometrics: () async => false,
                onUnlocked: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final buttonFinder = find.byKey(
            const Key('password-biometric-button'),
          );
          expect(buttonFinder, findsOneWidget);
          final icon = tester.widget<BiometricIcon>(
            find.descendant(
              of: buttonFinder,
              matching: find.byType(BiometricIcon),
            ),
          );
          expect(icon.kind, kind);

          final unlockRect = tester.getRect(
            find.widgetWithText(FilledButton, 'Unlock'),
          );
          final bioRect = tester.getRect(buttonFinder);
          expect(bioRect.top, greaterThan(unlockRect.bottom));
        },
      );
    }

    testWidgets(
      'onboarding and settings show matching Face ID and Fingerprint icons',
      (tester) async {
        const repository = FakeParsRepository();
        for (final kind in <BiometricKind>[
          BiometricKind.face,
          BiometricKind.fingerprint,
        ]) {
          await configureGuiTestViewport(tester);
          final onboardingSecurity = InMemorySecurityRepository.withPin(
            '123456',
            onboardingComplete: false,
            biometricAvailable: true,
            biometricKind: kind,
            lastUnlockedAt: DateTime.now(),
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              child: OnboardingScreen(
                onComplete: () {},
                securityRepository: onboardingSecurity,
              ),
            ),
          );
          await tester.pumpAndSettle();

          final onboardingIcons = tester.widgetList<BiometricIcon>(
            find.byType(BiometricIcon),
          );
          expect(onboardingIcons, isNotEmpty);
          expect(
            onboardingIcons.every((icon) => icon.kind == kind),
            isTrue,
          );

          final settingsSecurity = InMemorySecurityRepository.withPin(
            '123456',
            biometricAvailable: true,
            biometricKind: kind,
            lastUnlockedAt: DateTime.now(),
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              child: SettingsScreen(
                settingsRepository: repository,
                keyRepository: repository,
                gitRepository: repository,
                securityRepository: settingsSecurity,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('PIN lock and biometrics'));
          await tester.pumpAndSettle();

          final settingsIcons = tester.widgetList<BiometricIcon>(
            find.byType(BiometricIcon),
          );
          expect(settingsIcons, isNotEmpty);
          expect(
            settingsIcons.every((icon) => icon.kind == kind),
            isTrue,
          );

          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final viewport in <GuiTestViewport>[
      GuiTestViewport.compactPhone,
      GuiTestViewport.compactLandscape,
    ]) {
      testWidgets(
        'PIN lock and setup have zero overflow on ${viewport.name} at 200% text',
        (tester) async {
          await configureGuiTestViewport(tester, viewport: viewport);
          await tester.pumpWidget(
            buildLocalizedTestApp(
              textScale: 2,
              child: LockScreen(
                securityRepository: InMemorySecurityRepository.withPin(
                  '123456',
                  biometricUnlockEnabled: true,
                  biometricAvailable: true,
                  biometricKind: BiometricKind.face,
                ),
                unlockWithBiometrics: () async => false,
                onUnlocked: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expectNoFlutterOverflow(tester);

          await tester.pumpWidget(
            buildLocalizedTestApp(
              textScale: 2,
              child: OnboardingScreen(
                onComplete: () {},
                securityRepository: InMemorySecurityRepository(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expectNoFlutterOverflow(tester);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  });
}

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('pin-key-$digit')));
    await tester.pump();
  }
}
