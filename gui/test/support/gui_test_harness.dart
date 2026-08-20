import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_theme.dart';
import 'package:pars_gui/l10n/app_localizations.dart';

enum GuiTestViewport {
  compactPhone(Size(390, 844), 0),
  keyboardPhone(Size(390, 844), 320),
  compactLandscape(Size(844, 390), 0),
  medium(Size(700, 900), 0),
  expanded(Size(1100, 900), 0);

  const GuiTestViewport(this.size, this.keyboardInset);

  final Size size;
  final double keyboardInset;
}

Future<void> configureGuiTestViewport(
  WidgetTester tester, {
  GuiTestViewport viewport = GuiTestViewport.compactPhone,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport.size;
  tester.view.viewInsets = FakeViewPadding(bottom: viewport.keyboardInset);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
}

Widget buildLocalizedTestApp({
  required Widget child,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ParsTheme.light(),
    darkTheme: ParsTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder:
        (context, appChild) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: appChild!,
        ),
    home: Scaffold(body: SafeArea(child: child)),
  );
}

void expectNoFlutterOverflow(WidgetTester tester) {
  final exceptions = <Object>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    exceptions.add(exception!);
  }
  expect(
    exceptions,
    isEmpty,
    reason: 'Expected no Flutter layout exceptions, found: $exceptions',
  );
}
