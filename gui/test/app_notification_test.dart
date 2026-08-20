import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/widgets/app_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sensitiveClipboardChannel = MethodChannel(
    'top.vollate.pars_gui/sensitive_clipboard',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            return null;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          sensitiveClipboardChannel,
          (call) async => null,
        );
  });

  tearDown(() {
    AppNotification.dismiss();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sensitiveClipboardChannel, null);
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

    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Copy password',
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
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

  testWidgets('durable warning is not replaced by routine success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: FilledButton(
                  onPressed: () {
                    AppNotification.show(
                      context,
                      'Mutation succeeded but commit failed',
                      severity: AppNotificationSeverity.warning,
                      duration: Duration.zero,
                    );
                    AppNotification.show(
                      context,
                      'Copied',
                      severity: AppNotificationSeverity.success,
                    );
                  },
                  child: const Text('Show'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('Mutation succeeded but commit failed'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Mutation succeeded but commit failed'), findsOneWidget);
  });

  testWidgets('recoverable notification action is operable', (tester) async {
    var actionCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: FilledButton(
                  onPressed:
                      () => AppNotification.show(
                        context,
                        'Needs recovery',
                        severity: AppNotificationSeverity.error,
                        actionLabel: 'Retry',
                        onAction: () => actionCalls += 1,
                      ),
                  child: const Text('Show'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(actionCalls, 1);
    expect(find.text('Needs recovery'), findsNothing);
  });
}
