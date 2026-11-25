import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_gui_app.dart';

void main() {
  testWidgets('Pars app starts at PIN onboarding', (tester) async {
    await tester.pumpWidget(ParsGuiApp.fake());

    expect(find.text('Set PIN lock'), findsOneWidget);
    expect(find.text('Enter a 6-digit PIN.'), findsOneWidget);
  });
}
