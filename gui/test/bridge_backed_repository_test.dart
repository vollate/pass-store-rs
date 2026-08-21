import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/frb_generated/api.dart' as frb;
import 'package:pars_gui/bridge/pars_bridge_api.dart';
import 'package:pars_gui/models/key_record.dart';
import 'package:pars_gui/models/password_entry.dart';
import 'package:pars_gui/models/pgp_key_import.dart';
import 'package:pars_gui/services/autofill_repository.dart';
import 'package:pars_gui/services/bridge_backed_repository.dart';
import 'package:pars_gui/services/mobile_pgp_backend.dart';
import 'package:pars_gui/services/security_repository.dart';
import 'package:pars_gui/services/store_lifecycle.dart';
import 'package:pars_gui/services/vault_metadata_store.dart';

void main() {
  test(
    'bridge-backed repository loads config stores entries and git status',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.refresh();

      expect(repository.currentRepoName, 'Personal');
      expect(repository.lifecycle.onboardingState, StoreOnboardingState.ready);
      expect(repository.gitStatus, RepoGitStatus.uncommitted);
      expect(
        repository.entries.map((entry) => entry.path),
        contains('work/github'),
      );
      expect(repository.search('git').single.displayName, 'github');
      final secret = await repository.readEntry(repository.entries.first);
      final copiedPassword = await repository.copyEntryPassword(
        repository.entries.first,
      );

      expect(secret.password, 'bridge-secret');
      expect(secret.fieldValue('username'), 'alice');
      expect(secret.fieldValue('url'), 'https://example.com');
      expect(copiedPassword, 'bridge-secret');
      expect(bridge.lastEntryRequest?.root, '/tmp/personal-store');
      expect(bridge.lastEntryRequest?.path, 'work/github');
      expect(bridge.lastEntryRequest?.configPath, '/tmp/pars_config.toml');
      expect(bridge.lastEntryRequest?.passphrase, isNull);
      expect(
        bridge.calledMethods,
        containsAll(<String>[
          'inspect_app_state',
          'list_keys',
          'list_entries',
          'git_status',
          'read_entry',
          'copy_entry_password',
        ]),
      );
      expect(repository.keys.single.name, 'github-mobile');
    },
  );

  test(
    'bridge-backed repository exposes password-store PGP references',
    () async {
      final store = await Directory.systemTemp.createTemp(
        'pars-store-key-reference-',
      );
      addTearDown(() => store.delete(recursive: true));
      await File('${store.path}/.gpg-id').writeAsString(
        '# password-store recipients\n'
        'alice@example.com\n'
        'A70291EF\n',
      );
      final bridge = _LifecycleBridge(storeRoot: store.path);
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.refresh();

      final references = repository.keys
          .where((key) => key.type == KeyRecordType.pgp)
          .toList(growable: false);
      expect(references.map((key) => key.fingerprint), <String>[
        'alice@example.com',
        'A70291EF',
      ]);
      expect(references.every((key) => !key.hasLocalKeyMaterial), isTrue);
      expect(references.every((key) => !key.hasPrivateKey), isTrue);
      expect(references.first.referencedByStores, <String>['Personal']);
    },
  );

  test('store key IDs do not duplicate matching local PGP keys', () async {
    final store = await Directory.systemTemp.createTemp(
      'pars-store-installed-key-',
    );
    addTearDown(() => store.delete(recursive: true));
    await File('${store.path}/.gpg-id').writeAsString('A70291EF\n');
    final bridge = _LifecycleBridge(
      storeRoot: store.path,
      listedKeys: const <frb.KeyRecordDto>[
        frb.KeyRecordDto(
          keyType: 'pgp',
          name: 'Vollate <me@example.com>',
          fingerprint: '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF',
          source: 'GnuPG keyring',
          hasPrivateKey: true,
        ),
      ],
    );
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.refresh();

    expect(repository.keys, hasLength(1));
    expect(repository.keys.single.hasLocalKeyMaterial, isTrue);
    expect(repository.keys.single.hasPrivateKey, isTrue);
  });

  test(
    'bridge-backed repository passes active pgp session passphrase to entry reads',
    () async {
      final bridge = _LifecycleBridge();
      final securityRepository = InMemorySecurityRepository();
      await securityRepository.startPgpSession(
        fingerprint: 'ABC123',
        passphrase: 'session-passphrase',
      );
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        securityRepository: securityRepository,
      );

      await repository.refresh();
      await repository.readEntry(repository.entries.first);

      expect(bridge.lastEntryRequest?.passphrase, 'session-passphrase');
    },
  );

  test(
    'metadata-only entry reads do not rebuild the full autofill index',
    () async {
      final bridge = _LifecycleBridge();
      final autofillRepository = FakeAutofillRepository();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        autofillRepository: autofillRepository,
        metadataStore: InMemoryVaultMetadataStore(),
      );

      await repository.refresh();
      await repository.readEntry(repository.entries.first);
      await repository.toggleFavorite(repository.entries.first);

      expect(repository.recentEntries().single.path, 'work/github');
      expect(repository.entries.first.isFavorite, isTrue);
      expect(autofillRepository.operations, isNot(contains('rebuild')));
      expect(
        autofillRepository.operations.where((value) => value == 'ranking'),
        hasLength(2),
      );
      expect(autofillRepository.lastRankingEntries.single.path, 'work/github');
    },
  );

  test(
    'bridge-backed repository incrementally upserts autofill after entry changes',
    () async {
      final bridge = _LifecycleBridge();
      final autofillRepository = FakeAutofillRepository();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        autofillRepository: autofillRepository,
      );

      await repository.refresh();
      await repository.saveEntry(
        path: 'work/new',
        content: 'secret',
        overwrite: false,
      );

      expect(autofillRepository.operations, contains('upsert:work/new'));
      expect(autofillRepository.operations, isNot(contains('rebuild')));
    },
  );

  test(
    'autofill update failures do not roll back successful vault mutations',
    () async {
      final bridge = _LifecycleBridge();
      final autofillRepository = FakeAutofillRepository(
        operationError: StateError('index unavailable'),
      );
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        autofillRepository: autofillRepository,
        metadataStore: InMemoryVaultMetadataStore(),
      );

      await repository.refresh();
      final result = await repository.saveEntry(
        path: 'work/new',
        content: 'secret',
        overwrite: false,
      );

      expect(result.path, 'work/new');
      expect(bridge.calledMethods, contains('insert_entry'));
      expect(autofillRepository.operations, contains('upsert:work/new'));
      expect(autofillRepository.status.message, contains('Rebuild'));
    },
  );

  test(
    'bridge-backed repository clears autofill index when selected store is removed',
    () async {
      final bridge = _LifecycleBridge();
      final autofillRepository = FakeAutofillRepository();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        autofillRepository: autofillRepository,
      );

      await repository.refresh();
      await repository.removeStore(root: '/tmp/personal-store');

      expect(autofillRepository.cleared, isTrue);
    },
  );

  test(
    'canonical removal clears metadata session and Autofill before replacement',
    () async {
      final operations = <String>[];
      final bridge = _LifecycleBridge();
      final metadataStore = _RecordingMetadataStore(
        operations,
        const VaultMetadata(
          recentPaths: <String>['work/github'],
          favoritePaths: <String>{'work/github'},
        ),
      );
      final security = _RecordingSecurityRepository(operations);
      await security.savePgpPassphrase(
        fingerprint: 'ABCD 1234',
        passphrase: 'durable',
      );
      await security.startPgpSession(
        fingerprint: 'ABCD 1234',
        passphrase: 'session',
      );
      final autofill = _RecordingAutofillRepository(operations);
      await autofill.enrichWebsites(<String>['work/github']);
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        securityRepository: security,
        autofillRepository: autofill,
        metadataStore: metadataStore,
      );
      await repository.refresh();
      operations.clear();
      autofill.operations.clear();
      repository.lifecycleRevision.addListener(
        () => operations.add('lifecycle-published'),
      );

      await repository.removeStore(root: '/tmp/personal-store');

      expect(repository.lifecycle.requiresStoreSetup, isTrue);
      expect(repository.entries, isEmpty);
      expect(repository.recentEntries(), isEmpty);
      expect(repository.entries.where((entry) => entry.isFavorite), isEmpty);
      expect(operations, <String>[
        'lifecycle-published',
        'metadata-removal-marker',
        'metadata-clear',
        'session-clear',
        'autofill-clear',
        'lifecycle-published',
      ]);
      expect(await security.readActivePgpPassphrase(), isNull);
      expect((await security.readPgpPassphrase())?.passphrase, 'durable');
      expect((await metadataStore.load()).recentPaths, isEmpty);
      expect(autofill.lastEnrichedPaths, isEmpty);

      bridge
        ..storePresent = true
        ..storeRoot = '/tmp/replacement-store';
      operations.clear();
      autofill.operations.clear();
      await repository.refresh();

      expect(repository.store?.root, '/tmp/replacement-store');
      expect(repository.recentEntries(), isEmpty);
      expect(repository.entries.where((entry) => entry.isFavorite), isEmpty);
      expect(autofill.operations, isNot(contains('reconcile')));
      expect(autofill.operations, isNot(contains('rebuild')));
      expect(autofill.status.kind, AutofillStatusKind.needsRebuild);
      expect(autofill.lastEnrichedPaths, isEmpty);
    },
  );

  test('one durable metadata sentinel is sufficient for removal', () async {
    final operations = <String>[];
    final bridge = _LifecycleBridge();
    final metadataStore = _RecordingMetadataStore(
      operations,
      const VaultMetadata(
        recentPaths: <String>['work/github'],
        favoritePaths: <String>{'work/github'},
      ),
      failClear: true,
    );
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      autofillRepository: _RecordingAutofillRepository(operations),
      metadataStore: metadataStore,
    );
    await repository.refresh();
    bridge.calledMethods.clear();

    await repository.removeStore(root: '/tmp/personal-store');

    expect(metadataStore.removalMarked, isTrue);
    expect(bridge.calledMethods, contains('disconnect_store'));
    expect(repository.lifecycle.requiresStoreSetup, isTrue);
  });

  test(
    'both metadata sentinel failures cancel removal before bridge',
    () async {
      final operations = <String>[];
      final bridge = _LifecycleBridge();
      final metadataStore = _RecordingMetadataStore(
        operations,
        const VaultMetadata(
          recentPaths: <String>['work/github'],
          favoritePaths: <String>{'work/github'},
        ),
        failClear: true,
        failMarker: true,
      );
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        autofillRepository: _RecordingAutofillRepository(operations),
        metadataStore: metadataStore,
      );
      await repository.refresh();
      bridge.calledMethods.clear();

      await expectLater(
        repository.removeStore(root: '/tmp/personal-store'),
        throwsA(
          isA<BridgeRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('privacy cleanup could not be saved'),
          ),
        ),
      );

      expect(bridge.calledMethods, isNot(contains('disconnect_store')));
      expect(bridge.storePresent, isTrue);
      expect(bridge.storeRoot, '/tmp/personal-store');
      expect(repository.store?.root, '/tmp/personal-store');
      expect(repository.storeRemovalInProgress, isFalse);
      expect(repository.entries, isEmpty);
      expect(repository.recentEntries(), isEmpty);

      final restarted = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        metadataStore: metadataStore,
      );
      await restarted.refresh();
      expect(restarted.store?.root, '/tmp/personal-store');
      expect(restarted.store?.root, isNot('/tmp/replacement-store'));
    },
  );

  test('Autofill cleanup failure cancels disconnect fail-closed', () async {
    final operations = <String>[];
    final bridge = _LifecycleBridge();
    final metadataStore = _RecordingMetadataStore(
      operations,
      const VaultMetadata(
        recentPaths: <String>['work/github'],
        favoritePaths: <String>{'work/github'},
      ),
      failClear: true,
    );
    final security = _RecordingSecurityRepository(operations);
    await security.startPgpSession(
      fingerprint: 'ABCD 1234',
      passphrase: 'session',
    );
    final autofill = _RecordingAutofillRepository(operations, failClear: true);
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      securityRepository: security,
      autofillRepository: autofill,
      metadataStore: metadataStore,
    );
    await repository.refresh();
    operations.clear();

    await expectLater(
      repository.removeStore(root: '/tmp/personal-store'),
      throwsA(isA<AutofillRepositoryException>()),
    );

    expect(bridge.storePresent, isTrue);
    expect(repository.store?.root, '/tmp/personal-store');
    expect(repository.storeRemovalInProgress, isFalse);
    expect(repository.recentEntries(), isEmpty);
    expect(await security.readActivePgpPassphrase(), isNull);
    expect(autofill.cleared, isTrue);
    expect(autofill.status.kind, AutofillStatusKind.needsRebuild);
    expect(
      operations,
      containsAllInOrder(<String>[
        'metadata-removal-marker',
        'metadata-clear',
        'session-clear',
        'autofill-clear',
      ]),
    );

    final restarted = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      metadataStore: metadataStore,
    );
    await restarted.refresh();
    expect(restarted.recentEntries(), isEmpty);
    expect(restarted.entries.where((entry) => entry.isFavorite), isEmpty);
  });

  test('failed disconnect remounts only after fail-closed cleanup', () async {
    final operations = <String>[];
    final bridge = _LifecycleBridge()..failDisconnect = true;
    final security = _RecordingSecurityRepository(operations);
    await security.startPgpSession(
      fingerprint: 'ABCD 1234',
      passphrase: 'session',
    );
    final autofill = _RecordingAutofillRepository(operations);
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      securityRepository: security,
      autofillRepository: autofill,
      metadataStore: _RecordingMetadataStore(
        operations,
        const VaultMetadata(
          recentPaths: <String>['work/github'],
          favoritePaths: <String>{'work/github'},
        ),
      ),
    );
    await repository.refresh();
    operations.clear();
    autofill.operations.clear();

    await expectLater(
      repository.removeStore(root: '/tmp/personal-store'),
      throwsA(isA<BridgeRepositoryException>()),
    );

    expect(bridge.storePresent, isTrue);
    expect(repository.store?.root, '/tmp/personal-store');
    expect(repository.storeRemovalInProgress, isFalse);
    expect(await security.readActivePgpPassphrase(), isNull);
    expect(autofill.cleared, isTrue);
    expect(autofill.operations, isNot(contains('reconcile')));
    expect(autofill.status.kind, AutofillStatusKind.needsRebuild);
    expect(repository.recentEntries(), isEmpty);
  });

  test('removal clear is serialized after an in-flight reconcile', () async {
    final operations = <String>[];
    final bridge = _LifecycleBridge();
    final autofill = _RecordingAutofillRepository(operations);
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      autofillRepository: autofill,
    );
    await repository.refresh();
    operations.clear();
    autofill.operations.clear();

    final gate = Completer<void>();
    final started = Completer<void>();
    autofill
      ..reconcileGate = gate
      ..reconcileStarted = started;
    final refresh = repository.refresh();
    await started.future;
    final removal = repository.removeStore(root: '/tmp/personal-store');
    await Future<void>.delayed(Duration.zero);
    expect(bridge.storePresent, isTrue, reason: 'removal waits for reconcile');

    gate.complete();
    await refresh;
    await removal;

    expect(repository.lifecycle.requiresStoreSetup, isTrue);
    expect(repository.store, isNull);
    expect(repository.entries, isEmpty);
    expect(autofill.cleared, isTrue);
    expect(
      operations,
      containsAllInOrder(<String>[
        'autofill-reconcile-start',
        'autofill-reconcile-finish',
        'autofill-clear',
      ]),
    );
    expect(operations.last, 'autofill-clear');
  });

  test('generic remove disconnects even an app-managed store', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      managedStoreBaseDir: '/tmp',
    );

    await repository.refresh();
    bridge.calledMethods.clear();
    await repository.removeStore(root: '/tmp/personal-store');

    expect(bridge.calledMethods, contains('disconnect_store'));
    expect(bridge.calledMethods, isNot(contains('delete_local_store')));
  });

  test(
    'bridge-backed repository passes custom system gpg path to bridge',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        pgpExecutable: '/usr/local/bin/gpg',
        pgpBackendLabel: 'System GPG at /usr/local/bin/gpg',
      );

      await repository.refresh();

      expect(
        bridge.lastInspectAppStateRequest?.pgpExecutable,
        '/usr/local/bin/gpg',
      );
      expect(bridge.lastListKeysRequest?.pgpExecutable, '/usr/local/bin/gpg');
      expect(
        repository.runtimeDiagnostics(InMemorySecurityRepository()).pgpBackend,
        'System GPG at /usr/local/bin/gpg',
      );
    },
  );

  test('mobile pgp runtime configures pure rust backend', () async {
    final supportDir = await Directory.systemTemp.createTemp(
      'pars-mobile-pgp-',
    );
    addTearDown(() => supportDir.delete(recursive: true));
    final bridge = _LifecycleBridge();

    final runtime = await configureDefaultPgpRuntime(
      bridge: bridge,
      desktopConfigPath: '/tmp/desktop_config.toml',
      environment: PgpRuntimeEnvironment(
        isMobile: true,
        supportDirectory: () async => supportDir,
      ),
    );

    expect(runtime.configPath, '${supportDir.path}/pars_config.toml');
    expect(runtime.sshDir, '${supportDir.path}/ssh');
    expect(runtime.storeBaseDir, '${supportDir.path}/stores');
    expect(runtime.pgpExecutable, isNull);
    expect(runtime.diagnosticsLabel, 'Pure Rust OpenPGP (rPGP)');
    expect(
      bridge.lastConfigurePgpBackendRequest?.configPath,
      '${supportDir.path}/pars_config.toml',
    );
    expect(bridge.lastConfigurePgpBackendRequest?.backend, 'pure_rust');
    expect(
      bridge.lastConfigurePgpBackendRequest?.keyringHome,
      '${supportDir.path}/pgp',
    );
    expect(await Directory('${supportDir.path}/pgp').exists(), isTrue);
    expect(await Directory('${supportDir.path}/ssh').exists(), isTrue);
    expect(await Directory('${supportDir.path}/stores').exists(), isTrue);
  });

  test('bridge-backed repository derives app-managed mobile store roots', () {
    final repository = BridgeBackedRepository(
      bridge: _LifecycleBridge(),
      configPath: '/tmp/pars_config.toml',
      managedStoreBaseDir: '/app/support/stores',
    );

    expect(repository.usesAppManagedPaths, isTrue);
    expect(
      repository.storeRootForName('Personal Store'),
      '/app/support/stores/personal-store',
    );
    expect(
      repository.storeRootForRemote('git@example.com:org/passwords.git'),
      '/app/support/stores/passwords',
    );
  });

  test('bridge-backed repository persists vault metadata', () async {
    final metadataStore = InMemoryVaultMetadataStore();
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      metadataStore: metadataStore,
    );

    await repository.refresh();

    expect(repository.browseEntries(null).map((entry) => entry.path), <String>[
      'work',
    ]);
    expect(
      repository.browseEntries('work').map((entry) => entry.path),
      <String>['work/github'],
    );

    await repository.readEntry(repository.entries.first);
    await repository.toggleFavorite(repository.entries.first);

    expect(repository.recentEntries().single.path, 'work/github');
    expect(repository.entries.first.isFavorite, isTrue);

    final nextRepository = BridgeBackedRepository(
      bridge: _LifecycleBridge(),
      configPath: '/tmp/pars_config.toml',
      metadataStore: metadataStore,
    );
    await nextRepository.refresh();

    expect(nextRepository.recentEntries().single.path, 'work/github');
    expect(nextRepository.entries.first.isFavorite, isTrue);
  });

  test('bridge-backed repository exposes manage operations', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.refresh();

    final saved = await repository.saveEntry(
      path: 'work/new',
      content: 'new-secret',
      overwrite: false,
    );
    final generated = await repository.generateEntry(
      path: 'work/generated',
      length: 32,
      noSymbols: true,
      overwrite: true,
    );
    final edited = await repository.editEntry(
      path: 'work/new',
      content: 'edited-secret\nnote',
    );
    final replaced = await repository.replaceEntryPassword(
      entry: repository.entries.first,
      password: 'rotated-secret',
    );
    final moved = await repository.moveEntry(
      fromPath: 'work/new',
      toPath: 'archive/new',
      overwrite: false,
    );
    final deleted = await repository.deleteEntry(
      path: 'archive/new',
      recursive: false,
    );
    final commit = await repository.commitChanges('Update archive/new');

    expect(saved.path, 'work/new');
    expect(generated.path, 'work/generated');
    expect(edited.path, 'work/new');
    expect(replaced.action, 'Replaced password for');
    expect(moved.path, 'archive/new');
    expect(deleted.action, 'Deleted');
    expect(commit.success, isTrue);
    expect(bridge.lastInsertRequest?.content, 'new-secret');
    expect(bridge.lastInsertRequest?.configPath, '/tmp/pars_config.toml');
    expect(bridge.lastInsertRequest?.pgpExecutable, 'gpg');
    expect(bridge.lastGenerateRequest?.length, 32);
    expect(bridge.lastGenerateRequest?.configPath, '/tmp/pars_config.toml');
    expect(bridge.lastGenerateRequest?.pgpExecutable, 'gpg');
    expect(bridge.lastGenerateRequest?.noSymbols, isTrue);
    expect(bridge.lastEditRequest?.content, contains('rotated-secret'));
    expect(bridge.lastEditRequest?.configPath, '/tmp/pars_config.toml');
    expect(bridge.lastEditRequest?.pgpExecutable, 'gpg');
    expect(bridge.lastEditRequest?.content, contains('username: alice'));
    expect(bridge.lastMoveRequest?.fromPath, 'work/new');
    expect(bridge.lastMoveRequest?.toPath, 'archive/new');
    expect(bridge.lastDeleteRequest?.path, 'archive/new');
    expect(bridge.lastGitCommitRequest?.message, 'Update archive/new');
    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'insert_entry',
        'generate_entry',
        'edit_entry',
        'move_entry',
        'delete_entry',
        'git_commit',
      ]),
    );
  });

  test('bridge-backed repository exposes git operations and remotes', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.refresh();

    final status = await repository.refreshGitStatus();
    final pull = await repository.pull();
    final push = await repository.push();
    final commit = await repository.commit('Sync passwords');
    final remotes = await repository.listRemotes();
    final added = await repository.addRemote(
      name: 'backup',
      url: 'git@example.com:backup/pass.git',
    );
    final edited = await repository.editRemote(
      name: 'origin',
      url: 'git@example.com:new/pass.git',
    );
    final removed = await repository.removeRemote('backup');

    expect(status.command, 'git status --short --branch');
    expect(pull.command, 'git pull');
    expect(push.command, 'git push');
    expect(commit.command, 'git commit -m "Sync passwords"');
    expect(remotes.single.name, 'origin');
    expect(remotes.single.fetchUrl, '***@example.com:org/pass.git');
    expect(
      added.command,
      'git remote add backup ***@example.com:backup/pass.git',
    );
    expect(
      edited.command,
      'git remote set-url origin ***@example.com:new/pass.git',
    );
    expect(removed.command, 'git remote remove backup');
    expect(bridge.lastGitCommitRequest?.message, 'Sync passwords');
    expect(bridge.lastGitArgsRequest, isNull);
    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'git_list_remotes',
        'git_add_remote',
        'git_set_remote_url',
        'git_remove_remote',
      ]),
    );
  });

  test('remote mutation results redact credential-bearing URLs', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );
    await repository.refresh();

    final added = await repository.addRemote(
      name: 'backup',
      url: 'https://token@example.com/pass.git?access_token=secret#fragment',
    );
    final edited = await repository.editRemote(
      name: 'origin',
      url: 'ssh://password@example.com/pass.git?secret=value',
    );
    final scp = await repository.addRemote(
      name: 'scp',
      url: 'token-123@example.com:org/pass.git?secret=value',
    );

    final disabledRepository = BridgeBackedRepository(
      bridge: _LifecycleBridge(gitMode: frb.StoreGitModeDto.disabled),
      configPath: '/tmp/disabled.toml',
    );
    await disabledRepository.refresh();
    final disabled = await disabledRepository.addRemote(
      name: 'backup',
      url: 'https://disabled-secret@example.com/pass.git?token=x',
    );
    final invalidRepository = BridgeBackedRepository(
      bridge: _LifecycleBridge(gitMode: frb.StoreGitModeDto.invalid),
      configPath: '/tmp/invalid.toml',
    );
    await invalidRepository.refresh();
    final invalid = await invalidRepository.editRemote(
      name: 'origin',
      url: 'https://invalid-secret@example.com/pass.git#token',
    );

    for (final result in <GitOperationResult>[
      added,
      edited,
      scp,
      disabled,
      invalid,
    ]) {
      expect(result.command, isNot(contains('token@example')));
      expect(result.command, isNot(contains('password@example')));
      expect(result.command, isNot(contains('token-123@example')));
      expect(result.command, isNot(contains('disabled-secret')));
      expect(result.command, isNot(contains('invalid-secret')));
      expect(result.command, isNot(contains('access_token')));
      expect(result.command, isNot(contains('secret=value')));
      expect(result.command, contains('***@example.com'));
    }
  });

  test(
    'Git-disabled store skips commands and can initialize locally',
    () async {
      final bridge = _LifecycleBridge(gitMode: frb.StoreGitModeDto.disabled);
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.refresh();
      expect(repository.gitStatus, RepoGitStatus.disabled);
      expect(bridge.calledMethods, isNot(contains('git_status')));

      final skippedStatus = await repository.refreshGitStatus();
      final skippedCommit = await repository.commit('No Git commit');
      expect(skippedStatus.success, isTrue);
      expect(skippedCommit.success, isTrue);
      expect(bridge.calledMethods, isNot(contains('git_commit')));

      final initialized = await repository.initializeRepository();
      expect(initialized.command, 'git init');
      expect(bridge.calledMethods, contains('initialize_git_repository'));
      expect(repository.lifecycle.store?.gitMode, StoreGitMode.local);
      expect(repository.gitStatus, isNot(RepoGitStatus.syncFailed));
    },
  );

  test('failed Git initialization leaves local-only store usable', () async {
    final bridge = _LifecycleBridge(
      gitMode: frb.StoreGitModeDto.disabled,
      failGitInitialization: true,
    );
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );
    await repository.refresh();

    await expectLater(
      repository.initializeRepository(),
      throwsA(isA<BridgeRepositoryException>()),
    );
    expect(repository.lifecycle.store?.gitMode, StoreGitMode.disabled);
    expect(repository.entries, isNotEmpty);
    expect((await repository.refreshGitStatus()).success, isTrue);
  });

  test(
    'local Git without remote keeps status but skips pull and push',
    () async {
      final bridge = _LifecycleBridge(gitMode: frb.StoreGitModeDto.local);
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.refresh();
      expect(repository.lifecycle.store?.gitMode, StoreGitMode.local);
      expect(bridge.calledMethods, contains('git_status'));
      bridge.calledMethods.clear();

      final pull = await repository.pull();
      final push = await repository.push();
      expect(pull.stdout, contains('no Git remote'));
      expect(push.stdout, contains('no Git remote'));
      expect(bridge.calledMethods, isNot(contains('git_pull')));
      expect(bridge.calledMethods, isNot(contains('git_push')));
    },
  );

  test(
    'invalid Git remains distinct from disabled and dispatches no status',
    () async {
      final bridge = _LifecycleBridge(gitMode: frb.StoreGitModeDto.invalid);
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.refresh();
      expect(repository.gitStatus, RepoGitStatus.invalid);
      final result = await repository.refreshGitStatus();
      expect(result.success, isFalse);
      expect(result.stderr, contains('invalid Git metadata'));
      expect(bridge.calledMethods, isNot(contains('git_status')));
    },
  );

  test('bridge-backed repository exposes store lifecycle operations', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    await repository.createLocalStore(
      name: 'Work',
      root: '/tmp/work-store',
      pgpKeys: const <String>['alice@example.com'],
      initializeGit: true,
    );
    await repository.importLocalStore(root: '/tmp/existing-store');
    await repository.cloneStore(
      remoteUrl: 'git@example.com:org/pass.git',
      root: '/tmp/cloned-store',
    );
    await repository.removeStore(root: '/tmp/personal-store');
    final deleteRepository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      managedStoreBaseDir: '/tmp',
    );
    await deleteRepository.refresh();
    await deleteRepository.deleteLocalStore(
      root: '/tmp/personal-store',
      confirmation: 'personal-store',
    );

    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'create_local_store',
        'import_local_store',
        'clone_store',
        'disconnect_store',
        'delete_local_store',
      ]),
    );
  });

  test('app-managed repository honors explicit git initialization', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      managedStoreBaseDir: '/app/support/stores',
    );

    await repository.createLocalStore(
      name: 'Work',
      root: '/app/support/stores/work',
      pgpKeys: const <String>['alice@example.com'],
      initializeGit: true,
    );

    expect(bridge.lastCreateLocalStoreRequest?.initializeGit, isTrue);
  });

  test(
    'bridge-backed repository exposes contextual PGP and SSH operations',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
        sshDir: '/tmp/pars-ssh',
      );

      final key = await repository.generateSshKey('github-mobile');
      final publicKey = await repository.exportSshPublicKey('github-mobile');
      final prepared = await repository.preparePgpPrivateKey(
        fingerprint: 'ABCD 1234',
        passphrase: 'test passphrase',
      );
      await repository.deleteSshKey('github-mobile');
      final github = await repository.githubSshSettingsUri();

      expect(key.type, KeyRecordType.ssh);
      expect(publicKey, startsWith('ssh-ed25519 '));
      expect(bridge.lastDeleteSshKeyRequest?.name, 'github-mobile');
      expect(bridge.lastDeleteSshKeyRequest?.sshDir, '/tmp/pars-ssh');
      expect(bridge.lastPreparePgpPrivateKeyRequest?.fingerprint, 'ABCD 1234');
      expect(
        bridge.lastPreparePgpPrivateKeyRequest?.passphrase,
        'test passphrase',
      );
      expect(prepared.fingerprint, 'ABCD 1234');
      expect(prepared.migrated, isFalse);
      expect(github.toString(), 'https://github.com/settings/keys');
      expect(
        bridge.calledMethods,
        containsAll(<String>[
          'generate_ssh_key',
          'export_ssh_public_key',
          'delete_ssh_key',
          'prepare_pgp_private_key',
          'open_github_ssh_settings',
        ]),
      );
    },
  );

  test(
    'bridge-backed repository exposes generated PGP keys immediately',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      await repository.generatePgpKey(
        name: 'Alice',
        email: 'alice@example.com',
      );

      expect(
        repository.keys.map((key) => key.fingerprint),
        contains('GENERATED PGP'),
      );
    },
  );

  test(
    'PGP file inspection sends only the path, never file contents',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      final inspection = await repository.inspectPgpKeyFile(
        '/tmp/keys/alice.gpg',
      );

      expect(bridge.lastInspectPgpKeyFileRequest?.path, '/tmp/keys/alice.gpg');
      // The request DTO has no field that could carry key bytes back into Dart.
      expect(inspection.fingerprint, 'INSPECTED PGP');
      expect(inspection.identity, 'Alice <alice@example.com>');
      expect(inspection.kind, PgpKeyKind.public);
      expect(inspection.requiresPassphrase, isFalse);
      expect(bridge.calledMethods, contains('inspect_pgp_key_file'));
    },
  );

  test(
    'PGP import preserves the canonical fingerprint from the bridge',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      final result = await repository.importPgpKeyText(
        '-----BEGIN PGP PUBLIC KEY BLOCK-----',
      );

      expect(result.key.fingerprint, 'IMPORTED PGP');
      expect(result.inspection.fingerprint, 'IMPORTED PGP');
      expect(result.key.type, KeyRecordType.pgp);
      // The imported key is visible without an extra refresh.
      expect(
        repository.keys.map((key) => key.fingerprint),
        contains('IMPORTED PGP'),
      );
    },
  );

  test(
    'protected PGP import forwards the passphrase and reports protection',
    () async {
      final bridge = _LifecycleBridge();
      const protected = frb.PgpKeyInspectionDto(
        kind: frb.PgpKeyKindDto.private,
        fingerprint: 'PROTECTED PGP',
        identity: 'Protected <protected@example.com>',
        hasPrivateKey: true,
        requiresPassphrase: true,
        armored: true,
      );
      bridge.pgpImportResponse = const frb.PgpKeyImportResponse(
        inspection: protected,
        key: frb.KeyRecordDto(
          keyType: 'pgp',
          name: 'Protected <protected@example.com>',
          fingerprint: 'PROTECTED PGP',
          source: 'Imported private key',
          hasPrivateKey: true,
        ),
      );
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      final result = await repository.importPgpKeyFile(
        '/tmp/keys/protected.asc',
        passphrase: 'correct passphrase',
      );

      expect(
        bridge.lastImportPgpKeyFileRequest?.passphrase,
        'correct passphrase',
      );
      expect(result.inspection.requiresPassphrase, isTrue);
      expect(result.key.hasPrivateKey, isTrue);
      expect(result.key.fingerprint, 'PROTECTED PGP');
    },
  );

  test(
    'typed PGP import failures are mapped without leaking secret text',
    () async {
      final bridge = _LifecycleBridge();
      final repository = BridgeBackedRepository(
        bridge: bridge,
        configPath: '/tmp/pars_config.toml',
      );

      const cases = <frb.PgpImportFailureKind, PgpImportFailureKind>{
        frb.PgpImportFailureKind.unsupportedMaterial:
            PgpImportFailureKind.unsupportedMaterial,
        frb.PgpImportFailureKind.kindMismatch:
            PgpImportFailureKind.kindMismatch,
        frb.PgpImportFailureKind.passphraseRequired:
            PgpImportFailureKind.passphraseRequired,
        frb.PgpImportFailureKind.incorrectPassphrase:
            PgpImportFailureKind.incorrectPassphrase,
        frb.PgpImportFailureKind.unsupportedProtection:
            PgpImportFailureKind.unsupportedProtection,
        frb.PgpImportFailureKind.reprotectionFailed:
            PgpImportFailureKind.reprotectionFailed,
        frb.PgpImportFailureKind.backendError:
            PgpImportFailureKind.backendError,
      };

      for (final entry in cases.entries) {
        bridge.pgpImportResponse = frb.PgpKeyImportResponse(
          error: frb.BridgeFailure(
            category: frb.BridgeFailureCategory.validationError,
            message: 'the PGP private key passphrase is incorrect',
            pgpImportKind: entry.key,
          ),
        );

        await expectLater(
          repository.importPgpKeyText('material', passphrase: 'super secret'),
          throwsA(
            isA<PgpImportException>()
                .having((error) => error.kind, 'kind', entry.value)
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('super secret')),
                ),
          ),
        );
      }

      // A failure the bridge did not classify still surfaces as a typed exception.
      bridge.pgpImportResponse = const frb.PgpKeyImportResponse(
        error: frb.BridgeFailure(
          category: frb.BridgeFailureCategory.pgpError,
          message: 'something else went wrong',
        ),
      );
      await expectLater(
        repository.importPgpKeyText('material'),
        throwsA(
          isA<PgpImportException>().having(
            (error) => error.kind,
            'kind',
            PgpImportFailureKind.unknown,
          ),
        ),
      );
    },
  );
}

class _RecordingMetadataStore implements VaultMetadataStore {
  _RecordingMetadataStore(
    this.operations,
    this.metadata, {
    this.failClear = false,
    this.failMarker = false,
  });

  final List<String> operations;
  final bool failClear;
  final bool failMarker;
  VaultMetadata metadata;
  bool removalMarked = false;

  @override
  Future<VaultMetadata> load() async => metadata;

  @override
  Future<void> save(VaultMetadata value) async {
    if (value.recentPaths.isEmpty && value.favoritePaths.isEmpty) {
      operations.add('metadata-clear');
      if (failClear) throw StateError('metadata cleanup failed');
    }
    metadata = value;
  }

  @override
  Future<void> markStoreRemoved() async {
    operations.add('metadata-removal-marker');
    if (failMarker) throw StateError('metadata marker failed');
    removalMarked = true;
  }

  @override
  Future<bool> wasStoreRemoved() async => removalMarked;

  @override
  Future<void> clearStoreRemovedMarker() async {
    removalMarked = false;
  }
}

class _RecordingSecurityRepository extends InMemorySecurityRepository {
  _RecordingSecurityRepository(this.operations);

  final List<String> operations;

  @override
  Future<void> clearPgpSession() async {
    operations.add('session-clear');
    await super.clearPgpSession();
  }
}

class _RecordingAutofillRepository extends FakeAutofillRepository {
  _RecordingAutofillRepository(
    this.cleanupOperations, {
    this.failClear = false,
  });

  final List<String> cleanupOperations;
  final bool failClear;
  Completer<void>? reconcileGate;
  Completer<void>? reconcileStarted;

  @override
  Future<void> reconcileIndex(List<PasswordEntry> entries) async {
    cleanupOperations.add('autofill-reconcile-start');
    reconcileStarted?.complete();
    await reconcileGate?.future;
    await super.reconcileIndex(entries);
    cleanupOperations.add('autofill-reconcile-finish');
  }

  @override
  Future<void> clearIndex() async {
    cleanupOperations.add('autofill-clear');
    await super.clearIndex();
    if (failClear) throw StateError('autofill file cleanup failed');
  }

  @override
  Future<void> publishPlatformState() async {
    cleanupOperations.add('autofill-publish');
    await super.publishPlatformState();
  }
}

class _LifecycleBridge implements ParsBridgeApi {
  _LifecycleBridge({
    this.storeRoot = '/tmp/personal-store',
    this.gitMode = frb.StoreGitModeDto.remote,
    this.failGitInitialization = false,
    this.listedKeys = const <frb.KeyRecordDto>[
      frb.KeyRecordDto(
        keyType: 'ssh',
        name: 'github-mobile',
        fingerprint: 'SHA256:test',
        source: 'SSH key directory',
        hasPrivateKey: true,
      ),
    ],
  });

  String storeRoot;
  bool storePresent = true;
  bool failDisconnect = false;
  frb.StoreGitModeDto gitMode;
  final bool failGitInitialization;
  final List<frb.KeyRecordDto> listedKeys;
  final List<String> calledMethods = <String>[];
  Completer<void>? inspectGate;
  frb.InspectAppStateRequest? lastInspectAppStateRequest;
  frb.ConfigurePgpBackendRequest? lastConfigurePgpBackendRequest;
  frb.ListKeysRequest? lastListKeysRequest;
  frb.EntryRequest? lastEntryRequest;
  frb.InsertEntryRequest? lastInsertRequest;
  frb.GenerateEntryRequest? lastGenerateRequest;
  frb.EditEntryRequest? lastEditRequest;
  frb.MoveEntryRequest? lastMoveRequest;
  frb.DeleteEntryRequest? lastDeleteRequest;
  frb.PreparePgpPrivateKeyRequest? lastPreparePgpPrivateKeyRequest;
  frb.DeleteSshKeyRequest? lastDeleteSshKeyRequest;
  frb.CreateLocalStoreRequest? lastCreateLocalStoreRequest;
  frb.GitCommitRequest? lastGitCommitRequest;
  frb.GitArgsRequest? lastGitArgsRequest;
  frb.InspectPgpKeyTextRequest? lastInspectPgpKeyTextRequest;
  frb.InspectPgpKeyFileRequest? lastInspectPgpKeyFileRequest;
  frb.ImportPgpKeyTextRequest? lastImportPgpKeyTextRequest;
  frb.ImportPgpKeyFileRequest? lastImportPgpKeyFileRequest;
  frb.PgpKeyInspectionResponse pgpInspectionResponse =
      const frb.PgpKeyInspectionResponse(
        inspection: frb.PgpKeyInspectionDto(
          kind: frb.PgpKeyKindDto.public,
          fingerprint: 'INSPECTED PGP',
          identity: 'Alice <alice@example.com>',
          hasPrivateKey: false,
          requiresPassphrase: false,
          armored: true,
        ),
      );
  frb.PgpKeyImportResponse pgpImportResponse = const frb.PgpKeyImportResponse(
    inspection: frb.PgpKeyInspectionDto(
      kind: frb.PgpKeyKindDto.public,
      fingerprint: 'IMPORTED PGP',
      identity: 'Alice <alice@example.com>',
      hasPrivateKey: false,
      requiresPassphrase: false,
      armored: true,
    ),
    key: frb.KeyRecordDto(
      keyType: 'pgp',
      name: 'Alice <alice@example.com>',
      fingerprint: 'IMPORTED PGP',
      source: 'Imported public key',
      hasPrivateKey: false,
    ),
  );

  @override
  Future<frb.PgpKeyInspectionResponse> inspectPgpKeyText({
    required frb.InspectPgpKeyTextRequest request,
  }) async {
    calledMethods.add('inspect_pgp_key_text');
    lastInspectPgpKeyTextRequest = request;
    return pgpInspectionResponse;
  }

  @override
  Future<frb.PgpKeyInspectionResponse> inspectPgpKeyFile({
    required frb.InspectPgpKeyFileRequest request,
  }) async {
    calledMethods.add('inspect_pgp_key_file');
    lastInspectPgpKeyFileRequest = request;
    return pgpInspectionResponse;
  }

  @override
  Future<frb.PgpKeyImportResponse> importPgpKeyText({
    required frb.ImportPgpKeyTextRequest request,
  }) async {
    calledMethods.add('import_pgp_key_text');
    lastImportPgpKeyTextRequest = request;
    return pgpImportResponse;
  }

  @override
  Future<frb.PgpKeyImportResponse> importPgpKeyFile({
    required frb.ImportPgpKeyFileRequest request,
  }) async {
    calledMethods.add('import_pgp_key_file');
    lastImportPgpKeyFileRequest = request;
    return pgpImportResponse;
  }

  @override
  Future<frb.InspectStoreGitResponse> inspectStoreGit({
    required frb.InspectStoreGitRequest request,
  }) async => frb.InspectStoreGitResponse(mode: gitMode);

  @override
  Future<frb.UnitResponse> initializeGitRepository({
    required frb.InitializeGitRepositoryRequest request,
  }) async {
    calledMethods.add('initialize_git_repository');
    if (failGitInitialization) {
      return const frb.UnitResponse(
        error: frb.BridgeFailure(
          category: frb.BridgeFailureCategory.gitError,
          message: 'Git initialization failed',
        ),
      );
    }
    gitMode = frb.StoreGitModeDto.local;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.AppStateResponse> inspectAppState({
    required frb.InspectAppStateRequest request,
  }) async {
    calledMethods.add('inspect_app_state');
    lastInspectAppStateRequest = request;
    final response = frb.AppStateResponse(
      state: frb.AppStateDto(
        configPath: '/tmp/pars_config.toml',
        configExists: true,
        onboardingState: storePresent ? 'ready' : 'store_missing',
        issues:
            storePresent ? const <String>[] : const <String>['store_missing'],
        store:
            storePresent
                ? frb.StoreStatusDto(
                  name: 'Personal',
                  root: storeRoot,
                  exists: true,
                  hasGpgId: true,
                  pgpRecipients: const <String>['ABCD 1234'],
                  gitMode: gitMode,
                  pgpKeyMissing: false,
                  issues: const <String>[],
                )
                : null,
      ),
    );
    final gate = inspectGate;
    if (gate != null) {
      inspectGate = null;
      await gate.future;
    }
    return response;
  }

  @override
  Future<frb.ListEntriesResponse> listEntries({
    required frb.ListEntriesRequest request,
  }) async {
    calledMethods.add('list_entries');
    return const frb.ListEntriesResponse(
      entries: <frb.EntrySummaryDto>[
        frb.EntrySummaryDto(
          path: 'work/github',
          name: 'github',
          entryType: 'Password',
          childCount: 0,
        ),
        frb.EntrySummaryDto(
          path: 'work',
          name: 'work',
          entryType: 'Directory',
          childCount: 1,
        ),
      ],
    );
  }

  @override
  Future<frb.GitCommandResponse> gitStatus({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_status');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git status --short --branch',
        stdout: '## main\n M example.gpg\n',
        stderr: '',
        success: true,
      ),
    );
  }

  @override
  Future<frb.ListKeysResponse> listKeys({
    required frb.ListKeysRequest request,
  }) async {
    calledMethods.add('list_keys');
    lastListKeysRequest = request;
    return frb.ListKeysResponse(keys: listedKeys);
  }

  @override
  Future<frb.UnitResponse> createLocalStore({
    required frb.CreateLocalStoreRequest request,
  }) async {
    calledMethods.add('create_local_store');
    lastCreateLocalStoreRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> importLocalStore({
    required frb.ImportLocalStoreRequest request,
  }) async {
    calledMethods.add('import_local_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> cloneStore({
    required frb.CloneStoreRequest request,
  }) async {
    calledMethods.add('clone_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> disconnectStore({
    required frb.DisconnectStoreRequest request,
  }) async {
    calledMethods.add('disconnect_store');
    if (failDisconnect) {
      return const frb.UnitResponse(
        error: frb.BridgeFailure(
          category: frb.BridgeFailureCategory.storeError,
          message: 'disconnect failed',
        ),
      );
    }
    storePresent = false;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> deleteLocalStore({
    required frb.DeleteLocalStoreRequest request,
  }) async {
    calledMethods.add('delete_local_store');
    storePresent = false;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> initializeStoreRecipients({
    required frb.InitializeStoreRecipientsRequest request,
  }) async {
    calledMethods.add('initialize_store_recipients');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.KeyMutationResponse> generateSshKey({
    required frb.GenerateSshKeyRequest request,
  }) async {
    calledMethods.add('generate_ssh_key');
    return const frb.KeyMutationResponse(
      key: frb.KeyRecordDto(
        keyType: 'ssh',
        name: 'github-mobile',
        fingerprint: 'SHA256:test',
        source: 'SSH key directory',
        hasPrivateKey: true,
      ),
    );
  }

  @override
  Future<frb.KeyExportResponse> exportSshPublicKey({
    required frb.ExportSshKeyRequest request,
  }) async {
    calledMethods.add('export_ssh_public_key');
    return const frb.KeyExportResponse(
      export_: frb.KeyExportDto(armoredText: 'ssh-ed25519 AAAAtest'),
    );
  }

  @override
  Future<frb.UnitResponse> deleteSshKey({
    required frb.DeleteSshKeyRequest request,
  }) async {
    calledMethods.add('delete_ssh_key');
    lastDeleteSshKeyRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.PreparePgpPrivateKeyResponse> preparePgpPrivateKey({
    required frb.PreparePgpPrivateKeyRequest request,
  }) async {
    calledMethods.add('prepare_pgp_private_key');
    lastPreparePgpPrivateKeyRequest = request;
    return frb.PreparePgpPrivateKeyResponse(
      fingerprint: request.fingerprint,
      migrated: false,
    );
  }

  @override
  Future<frb.OpenExternalUrlResponse> openGithubSshSettings({
    required frb.OpenGithubSshSettingsRequest request,
  }) async {
    calledMethods.add('open_github_ssh_settings');
    return const frb.OpenExternalUrlResponse(
      url: 'https://github.com/settings/keys',
    );
  }

  @override
  Future<frb.ConfigResponse> loadConfig({
    required frb.LoadConfigRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.UnitResponse> saveConfig({
    required frb.SaveConfigRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.UnitResponse> configurePgpBackend({
    required frb.ConfigurePgpBackendRequest request,
  }) async {
    calledMethods.add('configure_pgp_backend');
    lastConfigurePgpBackendRequest = request;
    return const frb.UnitResponse();
  }

  @override
  Future<frb.EntrySecretResponse> readEntry({
    required frb.EntryRequest request,
  }) async {
    calledMethods.add('read_entry');
    lastEntryRequest = request;
    return const frb.EntrySecretResponse(
      secret: frb.EntrySecretDto(
        password: 'bridge-secret',
        fields: <frb.ParsedEntryFieldDto>[
          frb.ParsedEntryFieldDto(
            key: 'username',
            label: 'Username',
            value: 'alice',
          ),
          frb.ParsedEntryFieldDto(
            key: 'url',
            label: 'URL',
            value: 'https://example.com',
          ),
        ],
        rawNotes: 'raw note',
      ),
    );
  }

  @override
  Future<frb.CopyEntryPasswordResponse> copyEntryPassword({
    required frb.EntryRequest request,
  }) async {
    calledMethods.add('copy_entry_password');
    lastEntryRequest = request;
    return const frb.CopyEntryPasswordResponse(
      result: frb.CopyEntryPasswordResult(
        path: 'work/github',
        password: 'bridge-secret',
      ),
    );
  }

  @override
  Future<frb.InsertEntryResponse> insertEntry({
    required frb.InsertEntryRequest request,
  }) async {
    calledMethods.add('insert_entry');
    lastInsertRequest = request;
    return frb.InsertEntryResponse(
      result: frb.InsertEntryResultDto(
        entryPath: request.path,
        overwroteExisting: request.overwrite,
      ),
    );
  }

  @override
  Future<frb.GenerateEntryResponse> generateEntry({
    required frb.GenerateEntryRequest request,
  }) async {
    calledMethods.add('generate_entry');
    lastGenerateRequest = request;
    return frb.GenerateEntryResponse(
      result: frb.GenerateEntryResultDto(
        entryPath: request.path,
        password: 'generated-secret',
        overwroteExisting: request.overwrite,
      ),
    );
  }

  @override
  Future<frb.MutationResponse> editEntry({
    required frb.EditEntryRequest request,
  }) async {
    calledMethods.add('edit_entry');
    lastEditRequest = request;
    return frb.MutationResponse(
      result: frb.MutationResultDto(path: request.path),
    );
  }

  @override
  Future<frb.MutationResponse> moveEntry({
    required frb.MoveEntryRequest request,
  }) async {
    calledMethods.add('move_entry');
    lastMoveRequest = request;
    return frb.MutationResponse(
      result: frb.MutationResultDto(path: request.toPath),
    );
  }

  @override
  Future<frb.DeleteEntryResponse> deleteEntry({
    required frb.DeleteEntryRequest request,
  }) async {
    calledMethods.add('delete_entry');
    lastDeleteRequest = request;
    return frb.DeleteEntryResponse(
      result: frb.DeleteEntryResultDto(
        deletedPath: request.path,
        deletedType: 'Password',
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitPull({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_pull');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git pull',
        stdout: 'Already up to date.',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitPush({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_push');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git push',
        stdout: 'Pushed.',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitCommit({
    required frb.GitCommitRequest request,
  }) async {
    calledMethods.add('git_commit');
    lastGitCommitRequest = request;
    return frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git commit -m "${request.message}"',
        stdout: 'Committed',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitListRemotes({
    required frb.GitRequest request,
  }) async {
    calledMethods.add('git_list_remotes');
    return const frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git remote -v',
        stdout:
            'origin\tgit@example.com:org/pass.git (fetch)\norigin\tgit@example.com:org/pass.git (push)\n',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> gitAddRemote({
    required frb.GitRemoteRequest request,
  }) async {
    calledMethods.add('git_add_remote');
    return _successfulGitRemoteMutation('add', request);
  }

  @override
  Future<frb.GitCommandResponse> gitSetRemoteUrl({
    required frb.GitRemoteRequest request,
  }) async {
    calledMethods.add('git_set_remote_url');
    return _successfulGitRemoteMutation('set-url', request);
  }

  @override
  Future<frb.GitCommandResponse> gitRemoveRemote({
    required frb.GitRemoteRequest request,
  }) async {
    calledMethods.add('git_remove_remote');
    return _successfulGitRemoteMutation('remove', request);
  }

  frb.GitCommandResponse _successfulGitRemoteMutation(
    String action,
    frb.GitRemoteRequest request,
  ) {
    return frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: [
          'git remote',
          action,
          request.name,
          if (request.url != null) request.url!,
        ].join(' '),
        stdout: '',
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.GitCommandResponse> runGitArgs({
    required frb.GitArgsRequest request,
  }) async {
    calledMethods.add('run_git_args');
    lastGitArgsRequest = request;
    final args = request.args.join(' ');
    final stdout =
        args == 'remote -v'
            ? 'origin\tgit@example.com:org/pass.git (fetch)\norigin\tgit@example.com:org/pass.git (push)\n'
            : '';
    return frb.GitCommandResponse(
      output: frb.GitCommandOutputDto(
        command: 'git $args',
        stdout: stdout,
        stderr: '',
        exitCode: 0,
        success: true,
      ),
    );
  }

  @override
  Future<frb.KeyDetectionResponse> detectImportedKey({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> generatePgpKey({
    required frb.GeneratePgpKeyRequest request,
  }) async {
    calledMethods.add('generate_pgp_key');
    return const frb.KeyMutationResponse(
      key: frb.KeyRecordDto(
        keyType: 'pgp',
        name: 'Alice <alice@example.com>',
        fingerprint: 'GENERATED PGP',
        source: 'Generated key',
        hasPrivateKey: true,
      ),
    );
  }

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importSshPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyExportResponse> exportSshPrivateKey({
    required frb.ExportSshKeyRequest request,
  }) {
    throw UnimplementedError();
  }
}
