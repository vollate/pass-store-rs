import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../models/key_record.dart';
import '../../services/key_repository.dart';
import '../../services/path_picker_service.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../services/ui_problem.dart';
import '../../widgets/gesture_setup_panel.dart';
import '../../widgets/managed_store_conflict_sheet.dart';
import '../../widgets/path_picker_row.dart';
import '../../widgets/pgp_key_import_body.dart';

part 'widgets/onboarding_key_setup_widgets.dart';
part 'widgets/onboarding_step_widgets.dart';
part 'widgets/onboarding_store_setup_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.securityRepository,
    this.settingsRepository,
    this.keyRepository,
    this.pathPickerService = const SystemPathPickerService(),
  });

  final VoidCallback onComplete;
  final SecurityRepository securityRepository;
  final SettingsRepository? settingsRepository;
  final KeyRepository? keyRepository;
  final PathPickerService pathPickerService;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _OnboardingStep { gesture, biometrics, store, createRecipients, repair }

class _OnboardingScreenState extends State<OnboardingScreen> {
  late _OnboardingStep _step;
  final List<_OnboardingStep> _stepHistory = <_OnboardingStep>[];
  String? _error;
  String? _selectedPgpFingerprint;
  bool _finishing = false;

  StoreLifecycleSnapshot? get _lifecycle =>
      widget.settingsRepository?.lifecycle;

  KeyRepository? get _keyRepository => widget.keyRepository;

  bool get _needsStoreSetup => _lifecycle?.requiresStoreSetup ?? false;
  bool get _needsStoreRepair => _lifecycle?.requiresStoreRepair ?? false;

  List<KeyRecord> get _privatePgpKeys =>
      _keyRepository?.keys
          .where(
            (key) =>
                key.type == KeyRecordType.pgp &&
                key.hasLocalKeyMaterial &&
                key.hasPrivateKey,
          )
          .toList(growable: false) ??
      const <KeyRecord>[];

  List<KeyRecord> get _sshKeys =>
      _keyRepository?.keys
          .where(
            (key) => key.type == KeyRecordType.ssh && key.hasLocalKeyMaterial,
          )
          .toList(growable: false) ??
      const <KeyRecord>[];

  List<String> get _requiredRecipients =>
      _lifecycle?.store?.pgpRecipients ?? const <String>[];

  List<KeyRecord> get _matchingPrivatePgpKeys => _privatePgpKeys
      .where(
        (key) => pgpIdentityMatchesAnyRecipient(
          fingerprint: key.fingerprint,
          identity: key.name,
          recipients: _requiredRecipients,
        ),
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _step = _initialStep();
    if (_isReadyToFinish &&
        (widget.securityRepository.onboardingComplete ||
            widget.securityRepository.biometricUnlockEnabled)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishOnboarding());
    }
  }

  bool get _isReadyToFinish =>
      widget.securityRepository.hasGestureVerifier &&
      !_needsStoreSetup &&
      !_needsStoreRepair;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _stepHistory.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child:
              MediaQuery.textScalerOf(context).scale(1) >= 1.5
                  ? _buildLargeTextLayout(context)
                  : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 24),
                        Row(
                          children: <Widget>[
                            if (_stepHistory.isNotEmpty)
                              IconButton(
                                tooltip: context.l10n.back,
                                onPressed: _goBack,
                                icon: const Icon(Icons.arrow_back),
                              ),
                            Expanded(
                              child: Text(
                                _stepTitle(context.l10n, _step),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_stepSubtitle(context.l10n, _step)),
                        const SizedBox(height: 16),
                        _OnboardingProgress(
                          currentStep: _step,
                          steps: _progressSteps,
                        ),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Expanded(child: _buildStep(context)),
                        if (_finishing) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildLargeTextLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Flexible(
            flex: 2,
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 24),
                  Row(
                    children: <Widget>[
                      if (_stepHistory.isNotEmpty)
                        IconButton(
                          tooltip: context.l10n.back,
                          onPressed: _goBack,
                          icon: const Icon(Icons.arrow_back),
                        ),
                      Expanded(
                        child: Text(
                          _stepTitle(context.l10n, _step),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_stepSubtitle(context.l10n, _step)),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(flex: 3, child: _buildStep(context)),
          if (_finishing) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  _OnboardingStep _initialStep() {
    if (!widget.securityRepository.hasGestureVerifier) {
      return _OnboardingStep.gesture;
    }
    if (!widget.securityRepository.onboardingComplete &&
        !widget.securityRepository.biometricUnlockEnabled) {
      return _OnboardingStep.biometrics;
    }
    if (_needsStoreSetup) return _OnboardingStep.store;
    return _OnboardingStep.repair;
  }

  List<_OnboardingStep> get _progressSteps {
    if (widget.securityRepository.onboardingComplete) {
      return <_OnboardingStep>[
        _OnboardingStep.store,
        if (_needsStoreRepair) _OnboardingStep.repair,
      ];
    }
    return <_OnboardingStep>[
      _OnboardingStep.gesture,
      _OnboardingStep.biometrics,
      _OnboardingStep.store,
      if (_step == _OnboardingStep.createRecipients)
        _OnboardingStep.createRecipients,
      if (_needsStoreRepair || _step == _OnboardingStep.repair)
        _OnboardingStep.repair,
    ];
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case _OnboardingStep.gesture:
        return GestureSetupPanel(
          securityRepository: widget.securityRepository,
          onSaved: () => _setStep(_OnboardingStep.biometrics),
        );
      case _OnboardingStep.biometrics:
        return _BiometricSetupStep(
          securityRepository: widget.securityRepository,
          onEnable: _advanceAfterSecurity,
          onSkip: _advanceAfterSecurity,
          onError: _showError,
        );
      case _OnboardingStep.store:
        return _buildStoreStep(context);
      case _OnboardingStep.createRecipients:
        return _buildCreateRecipientsStep(context);
      case _OnboardingStep.repair:
        return _buildRepairStep(context);
    }
  }

  void _advanceAfterSecurity() {
    if (_needsStoreSetup) {
      _setStep(_OnboardingStep.store);
    } else if (_needsStoreRepair) {
      _setStep(_OnboardingStep.repair);
    } else {
      _finishOnboarding();
    }
  }

  Widget _buildStoreStep(BuildContext context) {
    final repository = widget.settingsRepository;
    final lifecycle = _lifecycle;
    if (repository == null || lifecycle == null) {
      return _EmptyOnboardingStep(
        icon: Icons.folder_off_outlined,
        title: context.l10n.noStoreRepository,
        buttonLabel: context.l10n.continueAction,
        onPressed: _finishOnboarding,
      );
    }

    final appManagedPaths =
        repository is AppManagedPathRepository
            ? repository as AppManagedPathRepository
            : null;
    final managedPaths =
        appManagedPaths != null && appManagedPaths.usesAppManagedPaths
            ? appManagedPaths
            : null;

    return _StoreSetupActions(
      lifecycle: lifecycle,
      managedPaths: managedPaths,
      selectedPgpFingerprint: _selectedPgpFingerprint,
      hasSshKey: _sshKeys.isNotEmpty,
      pathPickerService: widget.pathPickerService,
      onCreateNeedsRecipient: () => _setStep(_OnboardingStep.createRecipients),
      onGenerateSshKey: () => _showCreateSshKeyForm(context),
      onImportSshKey: () => _showImportSshKeyForm(context),
      onCreateLocalStore:
          ({
            required String name,
            required String root,
            required List<String> pgpKeys,
            required bool initializeGit,
          }) => repository.createLocalStore(
            name: name,
            root: root,
            pgpKeys: pgpKeys,
            initializeGit: initializeGit,
          ),
      onImportLocalStore: (root) => repository.importLocalStore(root: root),
      onCloneStore:
          ({required remoteUrl, required root}) =>
              repository.cloneStore(remoteUrl: remoteUrl, root: root),
      onStoreChanged: _handleStoreChanged,
    );
  }

  Widget _buildCreateRecipientsStep(BuildContext context) {
    final repository = _keyRepository;
    if (repository == null) {
      return _EmptyOnboardingStep(
        icon: Icons.enhanced_encryption_outlined,
        title: context.l10n.noKeyRepository,
        buttonLabel: context.l10n.back,
        onPressed: _goBack,
      );
    }
    return _PgpSetupStep(
      keys: _privatePgpKeys,
      emptyTitle: context.l10n.noPgpKeysFound,
      emptySubtitle: context.l10n.createOrImportEncryptionKey,
      onUseKey: (key) {
        _selectedPgpFingerprint = key.fingerprint;
        _setStep(_OnboardingStep.store);
      },
      onCreateKey: () => _showCreatePgpKeyForm(context, repository),
      onImportKey: () => _showImportPgpKeyForm(context, repository),
      allowCreate: true,
    );
  }

  Widget _buildRepairStep(BuildContext context) {
    final lifecycle = _lifecycle;
    final store = lifecycle?.store;
    if (lifecycle == null || store == null) {
      return _buildStoreStep(context);
    }
    if (store.gitMode == StoreGitMode.invalid) {
      final appManaged = _isAppManagedStoreRoot(store.root);
      return _StoreRepairStep(
        icon: Icons.account_tree_outlined,
        title: context.l10n.invalidGitMetadataTitle,
        message: context.l10n.invalidGitMetadataMessage,
        actionLabel:
            appManaged
                ? context.l10n.deleteAppCopy
                : context.l10n.disconnectStore,
        onAction:
            () =>
                appManaged
                    ? _confirmDeleteForRepair(store.root)
                    : _disconnectForRepair(store.root),
      );
    }

    final repository = _keyRepository;
    if (repository == null) {
      return _EmptyOnboardingStep(
        icon: Icons.key_off_outlined,
        title: context.l10n.noKeyRepository,
        buttonLabel: context.l10n.back,
        onPressed: _goBack,
      );
    }
    final missingGpgId = !store.hasGpgId;
    return _PgpSetupStep(
      keys: missingGpgId ? _privatePgpKeys : _matchingPrivatePgpKeys,
      emptyTitle:
          missingGpgId
              ? context.l10n.missingGpgIdTitle
              : context.l10n.requiredPgpKeyMissingTitle,
      emptySubtitle:
          missingGpgId
              ? context.l10n.missingGpgIdMessage
              : context.l10n.requiredPgpKeyMissingMessage(
                _requiredRecipients.join(', '),
              ),
      onUseKey: (key) => _completePgpRepair(key),
      onCreateKey:
          missingGpgId
              ? () => _showCreatePgpKeyForm(context, repository, repair: true)
              : null,
      onImportKey:
          () => _showImportPgpKeyForm(context, repository, repair: true),
      allowCreate: missingGpgId,
    );
  }

  bool _isAppManagedStoreRoot(String root) {
    final repository = widget.settingsRepository;
    if (repository is! AppManagedPathRepository) return false;
    final managed = repository as AppManagedPathRepository;
    return managed.usesAppManagedPaths && managed.isAppManagedStoreRoot(root);
  }

  Future<void> _disconnectForRepair(String root) async {
    await _runOnboardingAction(() async {
      await widget.settingsRepository!.removeStore(root: root);
      await widget.settingsRepository!.refresh();
      if (mounted) _setStep(_OnboardingStep.store);
    });
  }

  Future<void> _confirmDeleteForRepair(String root) async {
    final normalized = root.trim().replaceAll(RegExp(r'[/\\]+$'), '');
    final storeName = normalized.split(RegExp(r'[/\\]')).last;
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) =>
              _DeleteStoreConfirmationDialog(root: root, storeName: storeName),
    );
    if (approved != true || !mounted) return;
    await _runOnboardingAction(() async {
      await widget.settingsRepository!.deleteLocalStore(
        root: root,
        confirmation: storeName,
      );
      await widget.settingsRepository!.refresh();
      if (mounted) _setStep(_OnboardingStep.store);
    });
  }

  Future<void> _handleStoreChanged() async {
    await widget.settingsRepository?.refresh();
    if (!mounted) return;
    if (_needsStoreSetup) {
      setState(() {});
    } else if (_needsStoreRepair) {
      _setStep(_OnboardingStep.repair);
    } else {
      await _finishOnboarding();
    }
  }

  Future<void> _completePgpRepair(KeyRecord key) async {
    if (!key.hasPrivateKey || !key.hasLocalKeyMaterial) {
      _showError(StateError(context.l10n.requiredPrivatePgpKey));
      return;
    }
    final store = _lifecycle?.store;
    if (store == null) return;
    if (store.hasGpgId &&
        !pgpIdentityMatchesAnyRecipient(
          fingerprint: key.fingerprint,
          identity: key.name,
          recipients: _requiredRecipients,
        )) {
      _showError(StateError(context.l10n.pgpKeyDoesNotMatchStore));
      return;
    }
    await _runOnboardingAction(() async {
      if (!store.hasGpgId) {
        await _keyRepository!.initializeStoreRecipients(<String>[
          key.fingerprint,
        ]);
      }
      await widget.settingsRepository?.refresh();
      if (!mounted) return;
      if (_needsStoreRepair) {
        throw StateError(context.l10n.requiredPrivatePgpKey);
      }
      await _finishOnboarding();
    });
  }

  void _setStep(_OnboardingStep step, {bool recordHistory = true}) {
    if (!mounted) return;
    setState(() {
      if (recordHistory && step != _step) _stepHistory.add(_step);
      _step = step;
      _error = null;
    });
  }

  void _goBack() {
    if (_stepHistory.isEmpty) return;
    final previous = _stepHistory.removeLast();
    _setStep(previous, recordHistory: false);
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _error = UiProblem.fromError(context.l10n, error).summary);
  }

  void _showCreatePgpKeyForm(
    BuildContext context,
    KeyRepository repository, {
    bool repair = false,
  }) {
    final name = TextEditingController();
    final email = TextEditingController();
    final passphrase = TextEditingController();
    _showOnboardingForm(
      context: context,
      title: context.l10n.createPgpKey,
      fields: <Widget>[
        _CreatePgpKeyFields(name: name, email: email, passphrase: passphrase),
      ],
      submitLabel: context.l10n.create,
      onSubmit: () async {
        try {
          final key = await repository.generatePgpKey(
            name: name.text,
            email: email.text,
            passphrase: passphrase.text.trim().isEmpty ? null : passphrase.text,
          );
          if (repair) {
            await _completePgpRepair(key);
          } else {
            _selectedPgpFingerprint = key.fingerprint;
            _setStep(_OnboardingStep.store);
          }
        } finally {
          passphrase.clear();
        }
      },
    );
  }

  void _showImportPgpKeyForm(
    BuildContext context,
    KeyRepository repository, {
    bool repair = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheet).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.importPgpKey,
                      style: Theme.of(sheet).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PgpKeyImportBody(
                      keyRepository: repository,
                      securityRepository: widget.securityRepository,
                      pathPickerService: widget.pathPickerService,
                      initialDirectory: _defaultKeyFileBasePath(),
                      validateInspection: (inspection) {
                        if (!inspection.isPrivate ||
                            !inspection.hasPrivateKey) {
                          return context.l10n.requiredPrivatePgpKey;
                        }
                        if (repair &&
                            _lifecycle?.store?.hasGpgId == true &&
                            !pgpIdentityMatchesAnyRecipient(
                              fingerprint: inspection.fingerprint,
                              identity: inspection.identity,
                              recipients: _requiredRecipients,
                            )) {
                          return context.l10n.pgpKeyDoesNotMatchStore;
                        }
                        return null;
                      },
                      onCancel: () => Navigator.of(sheet).pop(),
                      onCompleted: (completion) async {
                        if (!completion.key.hasPrivateKey ||
                            !completion.key.hasLocalKeyMaterial) {
                          if (mounted) {
                            _showError(
                              StateError(context.l10n.requiredPrivatePgpKey),
                            );
                          }
                          return;
                        }
                        if (repair &&
                            _lifecycle?.store?.hasGpgId == true &&
                            !pgpIdentityMatchesAnyRecipient(
                              fingerprint: completion.key.fingerprint,
                              identity: completion.key.name,
                              recipients: _requiredRecipients,
                            )) {
                          if (mounted) {
                            _showError(
                              StateError(context.l10n.pgpKeyDoesNotMatchStore),
                            );
                          }
                          return;
                        }
                        if (sheet.mounted) Navigator.of(sheet).pop();
                        if (completion.rememberFailed && mounted) {
                          _error = context.l10n.importedKeyRememberFailed(
                            completion.key.name,
                          );
                        }
                        if (repair) {
                          await _completePgpRepair(completion.key);
                        } else {
                          _selectedPgpFingerprint = completion.key.fingerprint;
                          _setStep(_OnboardingStep.store);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  String _defaultKeyFileBasePath() {
    final root = _lifecycle?.store?.root;
    if (root != null && root.trim().isNotEmpty) return parentDirectory(root);
    final configPath = _lifecycle?.configPath;
    if (configPath != null && configPath.trim().isNotEmpty) {
      return parentDirectory(configPath);
    }
    return defaultUserDirectory();
  }

  Future<bool> _showCreateSshKeyForm(BuildContext context) async {
    final repository = _keyRepository;
    if (repository == null) return false;
    final name = TextEditingController(text: 'github-mobile-ed25519');
    await _showOnboardingForm(
      context: context,
      title: context.l10n.generateSshKey,
      fields: <Widget>[_CreateSshKeyFields(name: name)],
      submitLabel: context.l10n.generateSshKey,
      onSubmit: () async {
        await repository.generateSshKey(name.text);
        if (mounted) setState(() {});
      },
    );
    return _sshKeys.isNotEmpty;
  }

  Future<bool> _showImportSshKeyForm(BuildContext context) async {
    final repository = _keyRepository;
    if (repository == null) return false;
    final name = TextEditingController();
    final privateKey = TextEditingController();
    await _showOnboardingForm(
      context: context,
      title: context.l10n.importSshKey,
      fields: <Widget>[_ImportSshKeyFields(name: name, privateKey: privateKey)],
      submitLabel: context.l10n.importAction,
      onSubmit: () async {
        try {
          await repository.importSshPrivateKeyText(
            name: name.text,
            privateKey: privateKey.text,
          );
          if (mounted) setState(() {});
        } finally {
          privateKey.clear();
        }
      },
    );
    return _sshKeys.isNotEmpty;
  }

  Future<void> _showOnboardingForm({
    required BuildContext context,
    required String title,
    required List<Widget> fields,
    required String submitLabel,
    required Future<void> Function() onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _OnboardingFormSheet(
            title: title,
            fields: fields,
            submitLabel: submitLabel,
            onSubmit: onSubmit,
          ),
    );
  }

  Future<void> _runOnboardingAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _finishOnboarding() async {
    if (_finishing) return;
    if (_needsStoreSetup || _needsStoreRepair) {
      _showError(StateError(context.l10n.requiredPrivatePgpKey));
      return;
    }
    _finishing = true;
    if (mounted) setState(() {});
    await widget.securityRepository.setOnboardingComplete(true);
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (!mounted) return;
    widget.onComplete();
  }

  String _stepTitle(AppLocalizations l10n, _OnboardingStep step) =>
      switch (step) {
        _OnboardingStep.gesture => l10n.setGestureLock,
        _OnboardingStep.biometrics => l10n.enableBiometricUnlock,
        _OnboardingStep.store => l10n.setupPasswordStore,
        _OnboardingStep.createRecipients => l10n.choosePgpKey,
        _OnboardingStep.repair => l10n.repairPasswordStore,
      };

  String _stepSubtitle(AppLocalizations l10n, _OnboardingStep step) =>
      switch (step) {
        _OnboardingStep.gesture => l10n.gestureStepSubtitle,
        _OnboardingStep.biometrics => l10n.biometricsStepSubtitle,
        _OnboardingStep.store => l10n.storeFirstSetupSubtitle,
        _OnboardingStep.createRecipients => l10n.createStoreRecipientSubtitle,
        _OnboardingStep.repair => l10n.contextualRepairSubtitle,
      };
}

class _DeleteStoreConfirmationDialog extends StatefulWidget {
  const _DeleteStoreConfirmationDialog({
    required this.root,
    required this.storeName,
  });

  final String root;
  final String storeName;

  @override
  State<_DeleteStoreConfirmationDialog> createState() =>
      _DeleteStoreConfirmationDialogState();
}

class _DeleteStoreConfirmationDialogState
    extends State<_DeleteStoreConfirmationDialog> {
  final TextEditingController _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(context.l10n.deleteAppCopy),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.l10n.pathValue(widget.root)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('repair-delete-confirmation'),
            controller: _confirmation,
            decoration: InputDecoration(
              labelText: context.l10n.typeToConfirm(widget.storeName),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed:
              _confirmation.text == widget.storeName
                  ? () => Navigator.of(context).pop(true)
                  : null,
          child: Text(context.l10n.delete),
        ),
      ],
    );
  }
}
