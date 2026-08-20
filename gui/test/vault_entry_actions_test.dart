import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/screens/vault/entry_detail_sheet.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/widgets/app_notification.dart';

void main() {
  setUp(AppNotification.dismiss);
  tearDown(AppNotification.dismiss);

  testWidgets('entry detail action callbacks are disabled when absent', (
    tester,
  ) async {
    final repository = _RecordingManageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryDetailSheet(
            entry: repository.entries.single,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    for (final label in <String>['Edit', 'Regenerate', 'Delete']) {
      expect(
        find.text(label),
        findsNothing,
        reason: '$label must not be presented as supported',
      );
    }
    expect(find.text('QR code'), findsOneWidget);
  });

  testWidgets('entry detail invokes every supplied mutation callback', (
    tester,
  ) async {
    final repository = _RecordingManageRepository();
    var editCalls = 0;
    var regenerateCalls = 0;
    var deleteCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryDetailSheet(
            entry: repository.entries.single,
            repository: repository,
            onEdit: () => editCalls += 1,
            onRegenerate: () => regenerateCalls += 1,
            onDelete: () => deleteCalls += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in <String>['Edit', 'Regenerate', 'Delete']) {
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(editCalls, 1);
    expect(regenerateCalls, 1);
    expect(deleteCalls, 1);
  });

  testWidgets('vault detail actions close before focused sheets and cancel', (
    tester,
  ) async {
    final repository = _RecordingManageRepository();
    await _pumpVault(tester, repository);

    for (final action in <(String, String)>[
      ('Edit', 'Edit entries'),
      ('Regenerate', 'Regenerate'),
      ('Delete', 'Delete entry'),
    ]) {
      await _openEntry(tester);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action.$1));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('entry-detail-sheet')),
        findsNothing,
      );
      expect(find.text(action.$2), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    expect(repository.editAttempts, 0);
    expect(repository.regenerateCalls, 0);
    expect(repository.deleteAttempts, 0);
    expect(find.textContaining('Edited '), findsNothing);
    expect(find.textContaining('Regenerated '), findsNothing);
    expect(find.textContaining('Deleted '), findsNothing);
  });

  testWidgets('focused edit targets displayed path and reports success', (
    tester,
  ) async {
    final repository = _RecordingManageRepository();
    await _pumpVault(tester, repository);
    await _openFocusedAction(tester, 'Edit');

    await tester.enterText(_textFormField('Raw notes'), 'updated note');
    await tester.tap(find.widgetWithText(FilledButton, 'Save edited entry'));
    await tester.pumpAndSettle();

    expect(repository.editAttempts, 1);
    expect(repository.lastEditedPath, _RecordingManageRepository.entryPath);
    expect(
      repository.entries.single.encryptedContent,
      contains('updated note'),
    );
    expect(
      find.textContaining('Edited ${_RecordingManageRepository.entryPath}'),
      findsOneWidget,
    );
  });

  testWidgets(
    'focused regenerate passes exactly one entry and reports success',
    (tester) async {
      final repository = _RecordingManageRepository();
      await _pumpVault(tester, repository);
      await _openFocusedAction(tester, 'Regenerate');

      await tester.tap(find.text('No symbols'));
      await tester.tap(find.widgetWithText(FilledButton, 'Regenerate'));
      await tester.pumpAndSettle();

      expect(repository.regenerateCalls, 1);
      expect(repository.lastRegeneratedEntries, hasLength(1));
      expect(
        repository.lastRegeneratedEntries.single.path,
        _RecordingManageRepository.entryPath,
      );
      expect(repository.lastRegenerateLength, 24);
      expect(repository.lastRegenerateNoSymbols, isTrue);
      expect(
        repository.regeneratedOriginalContent,
        contains('username: alice'),
      );
      expect(repository.regeneratedOriginalContent, contains('original note'));
      expect(
        repository.entries.single.encryptedContent,
        contains('username: alice'),
      );
      expect(
        repository.entries.single.encryptedContent,
        contains('original note'),
      );
      expect(find.text('Regenerated 1 entries'), findsOneWidget);
    },
  );

  testWidgets('focused delete blocks wrong confirmation then removes entry', (
    tester,
  ) async {
    final repository = _RecordingManageRepository();
    await _pumpVault(tester, repository);
    await _openFocusedAction(tester, 'Delete');

    expect(
      find.text('Path: ${_RecordingManageRepository.entryPath}'),
      findsOneWidget,
    );
    final confirmation = find.byType(TextFormField);
    expect(confirmation, findsOneWidget);
    await tester.enterText(confirmation, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pump();

    expect(repository.deleteAttempts, 0);
    expect(find.text('Type Alice to confirm'), findsWidgets);

    await tester.enterText(confirmation, 'Alice');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete entry'));
    await tester.pumpAndSettle();

    expect(repository.deleteAttempts, 1);
    expect(repository.lastDeletedPath, _RecordingManageRepository.entryPath);
    expect(repository.lastDeleteRecursive, isFalse);
    expect(repository.entries, isEmpty);
    expect(find.text('Alice'), findsNothing);
    expect(
      find.textContaining('Deleted ${_RecordingManageRepository.entryPath}'),
      findsOneWidget,
    );
  });

  testWidgets('focused action failure stays open with an actionable error', (
    tester,
  ) async {
    final repository = _RecordingManageRepository()..failEdits = true;
    await _pumpVault(tester, repository);
    await _openFocusedAction(tester, 'Edit');

    await tester.tap(find.widgetWithText(FilledButton, 'Save edited entry'));
    await tester.pumpAndSettle();

    expect(repository.editAttempts, 1);
    expect(find.text('Edit entries'), findsOneWidget);
    expect(
      find.text('Operation failed. Try again or open Details.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Save edited entry'),
      findsOneWidget,
    );
  });

  testWidgets(
    'failed optional commit states that mutation was not rolled back',
    (tester) async {
      final repository = _RecordingManageRepository()..failCommits = true;
      await _pumpVault(tester, repository);
      await _openFocusedAction(tester, 'Edit');

      await tester.tap(find.text('Commit after operation'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save edited entry'));
      await tester.pumpAndSettle();

      expect(repository.editAttempts, 1);
      expect(repository.commitAttempts, 1);
      expect(find.text('Edit entries'), findsOneWidget);
      expect(find.textContaining('optional Git commit failed'), findsOneWidget);
      expect(find.textContaining('was not rolled back'), findsOneWidget);
      expect(
        find.textContaining('Edited ${_RecordingManageRepository.entryPath}'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpVault(
  WidgetTester tester,
  _RecordingManageRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openEntry(WidgetTester tester) async {
  await tester.tap(find.text('Alice').first);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('entry-detail-sheet')),
    findsOneWidget,
  );
}

Future<void> _openFocusedAction(WidgetTester tester, String action) async {
  await _openEntry(tester);
  await tester.tap(find.byTooltip('More actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Finder _textFormField(String label) {
  return find
      .ancestor(of: find.text(label), matching: find.byType(TextFormField))
      .first;
}

class _RecordingManageRepository extends FakeParsRepository {
  _RecordingManageRepository();

  static const entryPath = 'example.com/alice';
  final List<PasswordEntry> _entries = <PasswordEntry>[
    const PasswordEntry(
      path: entryPath,
      displayName: 'Alice',
      repoName: 'Test store',
      encryptedContent:
          'original-password\nusername: alice\nurl: https://example.com\noriginal note',
      lastUsedLabel: 'Now',
    ),
  ];

  int editAttempts = 0;
  int regenerateCalls = 0;
  int deleteAttempts = 0;
  int commitAttempts = 0;
  String? lastEditedPath;
  List<PasswordEntry> lastRegeneratedEntries = const <PasswordEntry>[];
  int? lastRegenerateLength;
  bool? lastRegenerateNoSymbols;
  String? regeneratedOriginalContent;
  String? lastDeletedPath;
  bool? lastDeleteRecursive;
  bool failEdits = false;
  bool failCommits = false;

  @override
  String get currentRepoName => 'Test store';

  @override
  List<PasswordEntry> get entries => List<PasswordEntry>.unmodifiable(_entries);

  @override
  Future<void> refresh() async {}

  @override
  Future<EntryOperationResult> editEntry({
    required String path,
    required String content,
  }) async {
    editAttempts += 1;
    lastEditedPath = path;
    if (failEdits) {
      throw StateError('edit failed');
    }
    final index = _entries.indexWhere((entry) => entry.path == path);
    final current = _entries[index];
    _entries[index] = PasswordEntry(
      path: current.path,
      displayName: current.displayName,
      repoName: current.repoName,
      encryptedContent: content,
      isFavorite: current.isFavorite,
      lastUsedLabel: current.lastUsedLabel,
    );
    return EntryOperationResult(
      path: path,
      overwroteExisting: true,
      action: 'Edited',
    );
  }

  @override
  Future<BatchOperationResult> batchRegenerateEntries({
    required List<PasswordEntry> entries,
    required int length,
    required bool noSymbols,
  }) async {
    regenerateCalls += 1;
    lastRegeneratedEntries = List<PasswordEntry>.of(entries);
    lastRegenerateLength = length;
    lastRegenerateNoSymbols = noSymbols;
    regeneratedOriginalContent = entries.single.encryptedContent;

    final index = _entries.indexWhere(
      (entry) => entry.path == entries.single.path,
    );
    final current = _entries[index];
    final lines = current.encryptedContent.split('\n');
    _entries[index] = PasswordEntry(
      path: current.path,
      displayName: current.displayName,
      repoName: current.repoName,
      encryptedContent: <String>[
        'regenerated-password',
        ...lines.skip(1),
      ].join('\n'),
      isFavorite: current.isFavorite,
      lastUsedLabel: current.lastUsedLabel,
    );
    return BatchOperationResult(
      action: 'Regenerated',
      affectedPaths: <String>[entries.single.path],
    );
  }

  @override
  Future<EntryOperationResult> deleteEntry({
    required String path,
    required bool recursive,
  }) async {
    deleteAttempts += 1;
    lastDeletedPath = path;
    lastDeleteRecursive = recursive;
    _entries.removeWhere((entry) => entry.path == path);
    return EntryOperationResult(
      path: path,
      overwroteExisting: false,
      action: 'Deleted',
    );
  }

  @override
  Future<GitOperationResult> commitChanges(String message) async {
    commitAttempts += 1;
    return GitOperationResult(
      command: 'git commit',
      stdout: '',
      stderr: failCommits ? 'signing failed' : '',
      success: !failCommits,
      exitCode: failCommits ? 1 : 0,
    );
  }
}
