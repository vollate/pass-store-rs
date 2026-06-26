import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/widgets/app_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            return null;
          }
          return null;
        });
  });

  tearDown(() {
    AppNotification.dismiss();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('vault copy messages appear in the top overlay', (tester) async {
    const repository = FakeParsRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: VaultScreen(
              vaultRepository: repository,
              gitRepository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Copy').first);
    await tester.pump(const Duration(milliseconds: 400));

    final message = find.text('Copied GitHub password');
    expect(message, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester.getCenter(message).dy,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 3,
      ),
    );

    AppNotification.dismiss();
  });
}
