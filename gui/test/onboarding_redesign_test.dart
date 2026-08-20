import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/screens/onboarding/onboarding_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets(
    'onboarding uses required progress instead of disabled chip rail',
    (tester) async {
      await configureGuiTestViewport(tester);
      await tester.pumpWidget(ParsGuiApp.fake());
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Step '), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expectNoFlutterOverflow(tester);
    },
  );

  testWidgets('biometrics is visibly optional and deferrable', (tester) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    final security = InMemorySecurityRepository.withPattern(
      const <int>[0, 1, 2, 5],
      onboardingComplete: false,
      lastUnlockedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: security,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable biometric unlock'), findsWidgets);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.text('Skip biometrics'), findsOneWidget);
  });

  testWidgets('public-only PGP keys cannot satisfy onboarding repair', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _PublicOnlyKeyRepository();
    await tester.pumpWidget(
      ParsGuiApp(
        vaultRepository: repository,
        settingsRepository: repository,
        keyRepository: repository,
        gitRepository: repository,
        securityRepository: InMemorySecurityRepository.withPattern(
          const <int>[0, 1, 2, 5],
          biometricUnlockEnabled: true,
          onboardingComplete: false,
          lastUnlockedAt: DateTime.now(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No PGP keys found'), findsOneWidget);
    expect(find.text('Use PGP key'), findsNothing);
  });

  testWidgets('onboarding remains usable at 200 percent text scale', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        textScale: 2,
        child: OnboardingScreen(
          onComplete: () {},
          settingsRepository: repository,
          keyRepository: repository,
          securityRepository: InMemorySecurityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set gesture lock'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });
}

class _PublicOnlyKeyRepository extends FakeParsRepository {
  @override
  List<KeyRecord> get keys => const <KeyRecord>[
    KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Public only',
      fingerprint: 'PUBLIC-ONLY',
      source: 'Imported public key',
      hasPrivateKey: false,
    ),
  ];
}
