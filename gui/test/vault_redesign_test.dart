import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/screens/vault/entry_detail_sheet.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/widgets/entry_tile.dart';
import 'package:pars_gui/widgets/pars_adaptive_surface.dart';

import 'support/gui_test_harness.dart';

void main() {
  testWidgets('Vault exposes Favorites and Browse without Recent', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    final repository = _VaultPresentationRepository(
      entries: <PasswordEntry>[
        _entry('favorite/alice', favorite: true),
        _entry('bob'),
        _directory('favorite'),
      ],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FAVORITES'), findsOneWidget);
    expect(find.text('RECENT'), findsNothing);
    expect(find.text('BROWSE'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(EntryTile), matching: find.text('alice')),
      findsOneWidget,
    );
    expect(find.text('bob'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('search results replace Favorites and Browse', (tester) async {
    await configureGuiTestViewport(tester);
    final repository = _VaultPresentationRepository(
      entries: <PasswordEntry>[_entry('service/alice'), _directory('service')],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alice');
    await tester.pumpAndSettle();

    expect(find.text('SEARCH RESULTS'), findsOneWidget);
    expect(find.text('FAVORITES'), findsNothing);
    expect(find.text('BROWSE'), findsNothing);
    expect(
      find.descendant(of: find.byType(EntryTile), matching: find.text('alice')),
      findsOneWidget,
    );
  });

  testWidgets(
    'favorite action updates visible row state without reading secret',
    (tester) async {
      await configureGuiTestViewport(tester);
      final repository = _VaultPresentationRepository(
        entries: <PasswordEntry>[_entry('alice'), _directory('folder')],
      );

      await tester.pumpWidget(
        buildLocalizedTestApp(
          child: VaultScreen(
            vaultRepository: repository,
            gitRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorite').first);
      await tester.pumpAndSettle();

      expect(repository.favoriteUpdates, 1);
      expect(repository.readCount, 0);
      expect(find.byTooltip('Unfavorite'), findsWidgets);
    },
  );

  testWidgets('entry detail exposes exactly one reveal and hide control', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    final entry = repository.entries.firstWhere((entry) => !entry.isDirectory);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: EntryDetailSheet(entry: entry, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reveal'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reveal'), findsNothing);
    await tester.tap(find.byTooltip('Reveal'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Hide'), findsOneWidget);
    expect(find.text('s3cret-github'), findsOneWidget);
  });

  testWidgets('privacy transition closes detail and clears loaded secret', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    const repository = FakeParsRepository();
    final entry = repository.entries.firstWhere((entry) => !entry.isDirectory);
    final privacyEvents = ValueNotifier<int>(0);
    addTearDown(privacyEvents.dispose);
    var cleared = 0;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: Builder(
          builder:
              (context) => FilledButton(
                onPressed:
                    () => showParsAdaptiveDetail<void>(
                      context: context,
                      builder:
                          (_) => EntryDetailSheet(
                            entry: entry,
                            repository: repository,
                            privacyEvents: privacyEvents,
                            onSecretCleared: () => cleared += 1,
                          ),
                    ),
                child: const Text('Open detail'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('entry-detail-sheet')),
      findsOneWidget,
    );

    privacyEvents.value += 1;
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('entry-detail-sheet')),
      findsNothing,
    );
    expect(cleared, 1);
  });

  testWidgets('Chinese Vault localizes disabled and local Git modes', (
    tester,
  ) async {
    await configureGuiTestViewport(tester);
    for (final mode in <StoreGitMode>[
      StoreGitMode.disabled,
      StoreGitMode.local,
    ]) {
      final repository = _VaultPresentationRepository(
        entries: <PasswordEntry>[_directory('folder')],
        status:
            mode == StoreGitMode.disabled
                ? RepoGitStatus.disabled
                : RepoGitStatus.clean,
        mode: mode,
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: const Locale('zh'),
          child: VaultScreen(
            vaultRepository: repository,
            gitRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          mode == StoreGitMode.disabled ? '未启用 Git · 仅本地密码库' : '本地 Git · 无远端',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('failed Git status never renders a success icon', (tester) async {
    await configureGuiTestViewport(tester);
    final repository = _VaultPresentationRepository(
      entries: <PasswordEntry>[_directory('folder')],
      status: RepoGitStatus.syncFailed,
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });
}

PasswordEntry _entry(String path, {bool favorite = false}) {
  final name = path.split('/').last;
  return PasswordEntry(
    path: path,
    displayName: name,
    repoName: 'test-store',
    encryptedContent: 'password',
    isFavorite: favorite,
  );
}

PasswordEntry _directory(String path) {
  return PasswordEntry(
    path: path,
    displayName: path.split('/').last,
    repoName: 'test-store',
    encryptedContent: '',
    isDirectory: true,
    childCount: 1,
  );
}

class _VaultPresentationRepository extends FakeParsRepository {
  _VaultPresentationRepository({
    required List<PasswordEntry> entries,
    RepoGitStatus status = RepoGitStatus.clean,
    StoreGitMode mode = StoreGitMode.remote,
  }) : _entries = entries,
       _status = status,
       _mode = mode;

  List<PasswordEntry> _entries;
  final RepoGitStatus _status;
  final StoreGitMode _mode;
  int favoriteUpdates = 0;
  int readCount = 0;

  @override
  String get currentRepoName => 'test-store';

  @override
  List<PasswordEntry> get entries => _entries;

  @override
  RepoGitStatus get gitStatus => _status;

  @override
  StoreGitMode get gitMode => _mode;

  @override
  Future<void> toggleFavorite(PasswordEntry entry) async {
    favoriteUpdates += 1;
    _entries = _entries
        .map(
          (candidate) =>
              candidate.path == entry.path
                  ? candidate.copyWith(isFavorite: !candidate.isFavorite)
                  : candidate,
        )
        .toList(growable: false);
  }

  @override
  Future<SecretContent> readEntry(PasswordEntry entry) async {
    readCount += 1;
    return super.readEntry(entry);
  }
}
