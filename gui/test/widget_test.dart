import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';

void main() {
  testWidgets('Pars app starts at gesture onboarding', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());

    expect(find.text('Set gesture lock'), findsOneWidget);
  });
}
