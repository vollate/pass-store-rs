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
      expect(repository.gitStatus.label, 'Uncommitted');
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
    'bridge-backed repository refreshes autofill index after entry changes',
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

      expect(autofillRepository.lastRefreshedEntries, isNotEmpty);
      expect(
        autofillRepository.lastRefreshedEntries.map((entry) => entry.path),
        contains('work/github'),
      );
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
    expect(remotes.single.fetchUrl, 'git@example.com:org/pass.git');
    expect(
      added.command,
      'git remote add backup git@example.com:backup/pass.git',
    );
    expect(
      edited.command,
      'git remote set-url origin git@example.com:new/pass.git',
    );
    expect(removed.command, 'git remote remove backup');
    expect(bridge.lastGitCommitRequest?.message, 'Sync passwords');
    expect(bridge.lastGitArgsRequest?.args, <String>[
      'remote',
      'remove',
      'backup',
    ]);
  });

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
      setDefault: true,
      initializeGit: true,
    );
    await repository.selectStore('/tmp/work-store');
    await repository.importLocalStore(
      root: '/tmp/existing-store',
      setDefault: false,
    );
    await repository.cloneStore(
      remoteUrl: 'git@example.com:org/pass.git',
      root: '/tmp/cloned-store',
      setDefault: true,
    );
    await repository.removeStore(root: '/tmp/old-store');
    await repository.deleteLocalStore(
      root: '/tmp/old-store',
      confirmation: 'old-store',
    );

    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'create_local_store',
        'select_store',
        'import_local_store',
        'clone_store',
        'remove_store',
        'delete_local_store',
      ]),
    );
  });

  test('app-managed repository skips local git initialization', () async {
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
      setDefault: true,
      initializeGit: true,
    );

    expect(bridge.lastCreateLocalStoreRequest?.initializeGit, isFalse);
  });

  test('bridge-backed repository exposes key management operations', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
      sshDir: '/tmp/pars-ssh',
    );

    final key = await repository.generateSshKey('github-mobile');
    final publicKey = await repository.exportSshPublicKey('github-mobile');
    await repository.deleteSshKey('github-mobile');
    await repository.deletePgpKey('ABCD 1234');
    final github = await repository.githubSshSettingsUri();

    expect(key.type, KeyRecordType.ssh);
    expect(publicKey, startsWith('ssh-ed25519 '));
    expect(bridge.lastDeleteSshKeyRequest?.name, 'github-mobile');
    expect(bridge.lastDeleteSshKeyRequest?.sshDir, '/tmp/pars-ssh');
    expect(bridge.lastDeletePgpKeyRequest?.fingerprint, 'ABCD 1234');
    expect(bridge.lastDeletePgpKeyRequest?.configPath, '/tmp/pars_config.toml');
    expect(github.toString(), 'https://github.com/settings/keys');
    expect(
      bridge.calledMethods,
      containsAll(<String>[
        'generate_ssh_key',
        'export_ssh_public_key',
        'delete_ssh_key',
        'delete_pgp_key',
        'open_github_ssh_settings',
      ]),
    );
  });

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

  test('PGP file inspection sends only the path, never file contents', () async {
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
  });

  test('PGP import preserves the canonical fingerprint from the bridge', () async {
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
  });

  test('protected PGP import forwards the passphrase and reports protection', () async {
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
  });

  test('typed PGP import failures are mapped without leaking secret text', () async {
    final bridge = _LifecycleBridge();
    final repository = BridgeBackedRepository(
      bridge: bridge,
      configPath: '/tmp/pars_config.toml',
    );

    const cases = <frb.PgpImportFailureKind, PgpImportFailureKind>{
      frb.PgpImportFailureKind.unsupportedMaterial:
          PgpImportFailureKind.unsupportedMaterial,
      frb.PgpImportFailureKind.kindMismatch: PgpImportFailureKind.kindMismatch,
      frb.PgpImportFailureKind.passphraseRequired:
          PgpImportFailureKind.passphraseRequired,
      frb.PgpImportFailureKind.incorrectPassphrase:
          PgpImportFailureKind.incorrectPassphrase,
      frb.PgpImportFailureKind.backendError: PgpImportFailureKind.backendError,
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
  });
}

class _LifecycleBridge implements ParsBridgeApi {
  final List<String> calledMethods = <String>[];
  frb.InspectAppStateRequest? lastInspectAppStateRequest;
  frb.ConfigurePgpBackendRequest? lastConfigurePgpBackendRequest;
  frb.ListKeysRequest? lastListKeysRequest;
  frb.EntryRequest? lastEntryRequest;
  frb.InsertEntryRequest? lastInsertRequest;
  frb.GenerateEntryRequest? lastGenerateRequest;
  frb.EditEntryRequest? lastEditRequest;
  frb.MoveEntryRequest? lastMoveRequest;
  frb.DeleteEntryRequest? lastDeleteRequest;
  frb.DeletePgpKeyRequest? lastDeletePgpKeyRequest;
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
  Future<frb.AppStateResponse> inspectAppState({
    required frb.InspectAppStateRequest request,
  }) async {
    calledMethods.add('inspect_app_state');
    lastInspectAppStateRequest = request;
    return const frb.AppStateResponse(
      state: frb.AppStateDto(
        configPath: '/tmp/pars_config.toml',
        configExists: true,
        selectedStoreId: 'store-0',
        selectedStoreRoot: '/tmp/personal-store',
        onboardingState: 'ready',
        issues: <String>[],
        stores: <frb.StoreStatusDto>[
          frb.StoreStatusDto(
            id: 'store-0',
            name: 'Personal',
            root: '/tmp/personal-store',
            isDefault: true,
            exists: true,
            hasGpgId: true,
            hasGitRemote: true,
            pgpKeyMissing: false,
            issues: <String>[],
          ),
        ],
      ),
    );
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
    return const frb.ListKeysResponse(
      keys: <frb.KeyRecordDto>[
        frb.KeyRecordDto(
          keyType: 'ssh',
          name: 'github-mobile',
          fingerprint: 'SHA256:test',
          source: 'SSH key directory',
          hasPrivateKey: true,
        ),
      ],
    );
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
  Future<frb.UnitResponse> selectStore({
    required frb.SelectStoreRequest request,
  }) async {
    calledMethods.add('select_store');
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
  Future<frb.UnitResponse> removeStore({
    required frb.RemoveStoreRequest request,
  }) async {
    calledMethods.add('remove_store');
    return const frb.UnitResponse();
  }

  @override
  Future<frb.UnitResponse> deleteLocalStore({
    required frb.DeleteLocalStoreRequest request,
  }) async {
    calledMethods.add('delete_local_store');
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
  Future<frb.UnitResponse> deletePgpKey({
    required frb.DeletePgpKeyRequest request,
  }) async {
    calledMethods.add('delete_pgp_key');
    lastDeletePgpKeyRequest = request;
    return const frb.UnitResponse();
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
  Future<frb.ListStoresResponse> listStores({
    required frb.ListStoresRequest request,
  }) {
    throw UnimplementedError();
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
  Future<frb.KeyMutationResponse> importPgpPublicKey({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyFile({
    required frb.ImportKeyFileRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyMutationResponse> importPgpPrivateKeyText({
    required frb.ImportKeyTextRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyExportResponse> exportPgpPublicKey({
    required frb.ExportPgpKeyRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.KeyExportResponse> exportPgpPrivateKey({
    required frb.ExportPgpKeyRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<frb.UnitResponse> addPgpKeyToGpgId({
    required frb.AddPgpKeyToGpgIdRequest request,
  }) {
    throw UnimplementedError();
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
