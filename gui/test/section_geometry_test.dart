import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_design_tokens.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/widgets/app_section.dart';

import 'support/gui_test_harness.dart';

// Vault and Settings drifted apart once before, each carrying its own card
// outline, row height and gaps. These measure the rendered geometry of both
// routes rather than trusting that they still call the same widget.
void main() {
  testWidgets('Vault and Settings render identical section geometry', (
    tester,
  ) async {
    final vault = await _sectionMetrics(tester, _vaultScreen());
    final settings = await _sectionMetrics(tester, _settingsScreen());

    expect(settings.rowHeight, vault.rowHeight);
    expect(settings.sectionLeft, vault.sectionLeft);
    expect(settings.sectionWidth, vault.sectionWidth);
    expect(settings.headerToContainerGap, vault.headerToContainerGap);
  });

  testWidgets('section geometry comes from the theme, not the widgets', (
    tester,
  ) async {
    const style = ParsSectionStyle.standard;
    final metrics = await _sectionMetrics(tester, _settingsScreen());

    expect(metrics.rowHeight, style.rowMinHeight);
    expect(metrics.sectionLeft, style.horizontalPadding);
    expect(metrics.headerToContainerGap, style.headerSpacing);
  });

  testWidgets('an overridden section style moves both routes together', (
    tester,
  ) async {
    final style = ParsSectionStyle.standard.copyWith(
      horizontalPadding: ParsSpacing.xxl,
      rowMinHeight: ParsSizes.minimumTouchTarget * 2,
    );
    final vault = await _sectionMetrics(tester, _vaultScreen(), style: style);
    final settings = await _sectionMetrics(
      tester,
      _settingsScreen(),
      style: style,
    );

    for (final metrics in <_SectionMetrics>[vault, settings]) {
      expect(metrics.rowHeight, style.rowMinHeight);
      expect(metrics.sectionLeft, style.horizontalPadding);
    }
  });
}

Widget _vaultScreen() {
  const repository = FakeParsRepository();
  return const VaultScreen(
    vaultRepository: repository,
    gitRepository: repository,
    keyRepository: repository,
  );
}

Widget _settingsScreen() {
  const repository = FakeParsRepository();
  return SettingsScreen(
    settingsRepository: repository,
    keyRepository: repository,
    gitRepository: repository,
    securityRepository: InMemorySecurityRepository(),
    autofillRepository: FakeAutofillRepository(),
    vaultRepository: repository,
  );
}

class _SectionMetrics {
  const _SectionMetrics({
    required this.rowHeight,
    required this.sectionLeft,
    required this.sectionWidth,
    required this.headerToContainerGap,
  });

  final double rowHeight;
  final double sectionLeft;
  final double sectionWidth;
  final double headerToContainerGap;
}

Future<_SectionMetrics> _sectionMetrics(
  WidgetTester tester,
  Widget screen, {
  ParsSectionStyle? style,
}) async {
  await configureGuiTestViewport(tester);
  await tester.pumpWidget(
    buildLocalizedTestApp(
      child:
          style == null
              ? screen
              : Builder(
                builder:
                    (context) => Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(extensions: <ThemeExtension<dynamic>>[style]),
                      child: screen,
                    ),
              ),
    ),
  );
  await tester.pumpAndSettle();

  final row = find.byType(ParsSectionRow).first;
  final container = find.byType(DecoratedBox).hitTestable().first;
  final section = find.byType(AppSectionBox).first;
  final header =
      find.descendant(of: section, matching: find.byType(Text)).first;

  return _SectionMetrics(
    rowHeight: tester.getSize(row).height,
    sectionLeft: tester.getTopLeft(container).dx,
    sectionWidth: tester.getSize(container).width,
    headerToContainerGap:
        tester.getTopLeft(container).dy - tester.getBottomLeft(header).dy,
  );
}
