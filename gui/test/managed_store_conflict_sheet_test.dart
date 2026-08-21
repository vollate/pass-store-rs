import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/app/pars_theme.dart';
import 'package:pars_gui/l10n/app_localizations.dart';
import 'package:pars_gui/services/path_picker_service.dart';
import 'package:pars_gui/widgets/managed_store_conflict_sheet.dart';

void main() {
  testWidgets('managed store conflict uses localized Pars bottom sheet', (
    tester,
  ) async {
    ManagedStoreConflictPolicy? selectedPolicy;

    await tester.pumpWidget(
      _ConflictSheetHarness(
        locale: const Locale('zh'),
        onSelected: (policy) => selectedPolicy = policy,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('同名仓库已存在'), findsOneWidget);
    expect(find.text('彻底覆盖'), findsOneWidget);
    expect(find.text('增量覆盖'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.textContaining('pass-store'), findsOneWidget);
    expect(find.textContaining('/data/'), findsNothing);

    await tester.tap(find.text('彻底覆盖'));
    await tester.pumpAndSettle();

    expect(selectedPolicy, ManagedStoreConflictPolicy.replace);
  });

  testWidgets('managed store conflict resolves the English replace action', (
    tester,
  ) async {
    ManagedStoreConflictPolicy? selectedPolicy;

    await tester.pumpWidget(
      _ConflictSheetHarness(
        locale: const Locale('en'),
        onSelected: (policy) => selectedPolicy = policy,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Store already exists'), findsOneWidget);
    expect(find.text('Replace completely'), findsOneWidget);
    expect(find.text('Merge and overwrite'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Replace completely'));
    await tester.pumpAndSettle();

    expect(selectedPolicy, ManagedStoreConflictPolicy.replace);
  });

  testWidgets('managed store conflict can be cancelled without a policy', (
    tester,
  ) async {
    var completed = false;
    ManagedStoreConflictPolicy? selectedPolicy;

    await tester.pumpWidget(
      _ConflictSheetHarness(
        locale: const Locale('en'),
        onSelected: (policy) {
          completed = true;
          selectedPolicy = policy;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(selectedPolicy, isNull);
  });
}

class _ConflictSheetHarness extends StatelessWidget {
  const _ConflictSheetHarness({required this.locale, required this.onSelected});

  final Locale locale;
  final ValueChanged<ManagedStoreConflictPolicy?> onSelected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ParsTheme.light(),
      home: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    final policy = await showManagedStoreConflictSheet(
                      context,
                      const ManagedStoreConflict(
                        destinationPath:
                            '/data/user/0/top.vollate.pars_gui/files/stores/pass-store',
                      ),
                    );
                    onSelected(policy);
                  },
                  child: const Text('Open'),
                ),
              ),
        ),
      ),
    );
  }
}
