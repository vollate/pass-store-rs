import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/models/git_sync.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/screens/settings/settings_screen.dart';
import 'package:pars_gui/screens/vault/vault_screen.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/widgets/app_notification.dart';

import 'support/gui_test_harness.dart';

void main() {
  tearDown(AppNotification.dismiss);

  Future<void> pumpVault(
    WidgetTester tester,
    _SyncRepository repository,
  ) async {
    await configureGuiTestViewport(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: VaultScreen(
          vaultRepository: repository,
          gitRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A prompt keeps the refresh spinner running, so this pumps fixed frames
  /// instead of waiting for the tree to settle.
  Future<void> pullToRefresh(WidgetTester tester) async {
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('pull-to-refresh commits and syncs when every change commits', (
    tester,
  ) async {
    final repository = _SyncRepository(changed: 1);
    await pumpVault(tester, repository);

    await pullToRefresh(tester);

    expect(repository.syncCalls, <bool>[true]);
    expect(find.text('Pushed local commits'), findsOneWidget);
    expect(find.text('Commit changes first?'), findsNothing);
  });

  testWidgets(
    'pull-to-refresh asks before committing when the setting is off',
    (tester) async {
      final repository = _SyncRepository(changed: 2)
        ..gitPreferences = const GitPreferences(commitEveryChange: false);
      await pumpVault(tester, repository);

      await pullToRefresh(tester);
      expect(find.text('Commit changes first?'), findsOneWidget);
      expect(find.text('2 changes are not committed.'), findsOneWidget);
      expect(repository.syncCalls, isEmpty);

      await tester.tap(find.text('Sync without committing'));
      await tester.pumpAndSettle();
      expect(repository.syncCalls, <bool>[false]);
      AppNotification.dismiss();
      await tester.pumpAndSettle();

      await pullToRefresh(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(repository.syncCalls, <bool>[false]);
    },
  );

  testWidgets('pull-to-refresh on a local-only store only reloads', (
    tester,
  ) async {
    final repository = _SyncRepository(mode: StoreGitMode.local);
    await pumpVault(tester, repository);
    final refreshesBefore = repository.refreshes;

    await pullToRefresh(tester);

    expect(repository.syncCalls, isEmpty);
    expect(repository.refreshes, greaterThan(refreshesBefore));
  });

  testWidgets('a blocked sync explains that a commit is needed', (
    tester,
  ) async {
    final repository = _SyncRepository()..nextBlocked = true;
    await pumpVault(tester, repository);

    await pullToRefresh(tester);

    expect(
      find.text(
        'Commit your changes first: local and remote history have diverged.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a conflict shows on the badge and offers recovery', (
    tester,
  ) async {
    final repository =
        _SyncRepository()
          ..nextConflict = const GitSyncConflict(
            backupBranch: 'pars/backup-20260930-100000',
            paths: <String>['work/github.gpg'],
          );
    await pumpVault(tester, repository);

    await pullToRefresh(tester);
    expect(
      find.text(
        'Sync stopped on a conflict. Local commits are kept in '
        'pars/backup-20260930-100000.',
      ),
      findsOneWidget,
    );
    AppNotification.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Conflict'), findsOneWidget);

    await tester.tap(find.text('Conflict'));
    await tester.pumpAndSettle();
    expect(find.text('Sync conflict'), findsOneWidget);
    expect(find.textContaining('work/github.gpg'), findsOneWidget);
    expect(find.text('Push backup'), findsOneWidget);

    await tester.tap(find.text('Use remote'));
    await tester.pumpAndSettle();
    expect(repository.resets, 1);
    expect(find.text('Conflict'), findsNothing);
    expectNoFlutterOverflow(tester);
  });

  testWidgets('missing identity is asked for, prefilled, and retried', (
    tester,
  ) async {
    final repository = _SyncRepository(changed: 1)..identityMissing = true;
    await pumpVault(tester, repository);

    await pullToRefresh(tester);
    expect(find.text('Commit identity'), findsOneWidget);
    expect(find.text('Vollate'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.savedIdentity?.name, 'Vollate');
    expect(repository.syncCalls, <bool>[true, true]);
    expect(find.text('Pushed local commits'), findsOneWidget);
  });

  testWidgets('dismissing the identity prompt does not retry', (tester) async {
    final repository = _SyncRepository(changed: 1)..identityMissing = true;
    await pumpVault(tester, repository);

    await pullToRefresh(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(repository.savedIdentity, isNull);
    expect(repository.syncCalls, <bool>[true]);
  });

  testWidgets('new badge states have short labels', (tester) async {
    for (final (status, label) in <(RepoGitStatus, String)>[
      (RepoGitStatus.needPush, 'Push needed'),
      (RepoGitStatus.diverged, 'Diverged'),
      (RepoGitStatus.conflicted, 'Conflict'),
    ]) {
      final repository = _SyncRepository()..fixedStatus = status;
      await pumpVault(tester, repository);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Git settings switch the integration strategy', (tester) async {
    await configureGuiTestViewport(tester);
    final repository =
        _SyncRepository()
          ..savedIdentity = const GitIdentity(
            name: 'Vollate',
            email: 'me@example.com',
          );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        child: SettingsScreen(
          settingsRepository: repository,
          keyRepository: repository,
          gitRepository: repository,
          securityRepository: InMemorySecurityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Git sync and remotes'));
    await tester.tap(find.text('Git sync and remotes'));
    await tester.pumpAndSettle();

    expect(find.text('Rebase'), findsOneWidget);
    expect(find.text('Vollate <me@example.com>'), findsOneWidget);
    await tester.tap(find.byTooltip('Combine diverged history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge').last);
    await tester.pumpAndSettle();

    expect(repository.gitPreferences.strategy, GitIntegrationStrategy.merge);
    expect(find.text('Merge'), findsOneWidget);
    expectNoFlutterOverflow(tester);
  });
}

class _SyncRepository extends FakeParsRepository {
  _SyncRepository({this.changed = 0, this.mode = StoreGitMode.remote});

  final int changed;
  final StoreGitMode mode;
  GitPreferences gitPreferences = const GitPreferences();
  final List<bool> syncCalls = <bool>[];
  int refreshes = 0;
  int resets = 0;
  bool nextBlocked = false;
  GitSyncConflict? nextConflict;
  GitSyncConflict? conflict;
  bool identityMissing = false;
  GitIdentity? savedIdentity;
  RepoGitStatus? fixedStatus;

  @override
  StoreGitMode get gitMode => mode;

  @override
  StoreStatus? get store => StoreStatus(
    name: 'Test store',
    root: '/tmp/test-store',
    exists: true,
    hasGpgId: true,
    pgpKeyMissing: false,
    issues: const <String>[],
    gitMode: mode,
  );

  @override
  StoreLifecycleSnapshot get lifecycle => StoreLifecycleSnapshot(
    configPath: '/tmp/config.toml',
    configExists: true,
    onboardingState: StoreOnboardingState.ready,
    issues: const <String>[],
    store: store,
  );

  @override
  RepoGitStatus get gitStatus {
    if (fixedStatus != null) return fixedStatus!;
    if (conflict != null) return RepoGitStatus.conflicted;
    return changed > 0 ? RepoGitStatus.uncommitted : RepoGitStatus.clean;
  }

  @override
  GitStatusSummary? get statusSummary => GitStatusSummary(
    branch: 'main',
    upstream: 'origin/main',
    ahead: 0,
    behind: 0,
    changed: changed,
    conflicted: 0,
    operation: GitOperationState.none,
    lastFetchedAt: null,
  );

  @override
  GitSyncConflict? get lastConflict => conflict;

  @override
  GitPreferences get preferences => gitPreferences;

  @override
  Future<void> updatePreferences(GitPreferences preferences) async {
    gitPreferences = preferences;
  }

  @override
  Future<void> refresh() async {
    refreshes += 1;
  }

  @override
  Future<GitSyncOutcome> sync({
    required bool commitPending,
    String message = 'Sync password store',
  }) async {
    syncCalls.add(commitPending);
    if (identityMissing && commitPending && savedIdentity == null) {
      throw const GitIdentityRequiredException('identity');
    }
    conflict = nextConflict;
    final blocked = nextBlocked;
    return GitSyncOutcome(
      committed: commitPending,
      pulled: 0,
      pushed: !blocked && conflict == null,
      blockedByChanges: blocked,
      conflict: conflict,
      summary: statusSummary!,
    );
  }

  @override
  Future<GitResetOutcome> resetToUpstream() async {
    resets += 1;
    conflict = null;
    return GitResetOutcome(
      committed: false,
      backupBranch: null,
      summary: statusSummary!,
    );
  }

  @override
  Future<GitIdentity?> identity() async => savedIdentity;

  @override
  Future<void> setIdentity({
    required String name,
    required String email,
  }) async {
    savedIdentity = GitIdentity(name: name, email: email);
  }
}
