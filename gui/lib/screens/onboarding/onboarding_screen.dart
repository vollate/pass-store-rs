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

enum _OnboardingStep { gesture, biometrics, pgp, ssh, store, review }

class _OnboardingScreenState extends State<OnboardingScreen> {
  late _OnboardingStep _step;
  final List<_OnboardingStep> _stepHistory = <_OnboardingStep>[];
  String? _error;
  String? _selectedPgpFingerprint;

  StoreLifecycleSnapshot? get _lifecycle =>
      widget.settingsRepository?.lifecycle;

  KeyRepository? get _keyRepository => widget.keyRepository;

  bool get _needsStoreSetup => _lifecycle?.requiresStoreSetup ?? false;
  bool get _needsKeyRepair => _lifecycle?.requiresKeyRepair ?? false;

  List<KeyRecord> get _pgpKeys =>
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
          .where((key) => key.type == KeyRecordType.ssh)
          .toList(growable: false) ??
      const <KeyRecord>[];

  String? get _effectivePgpFingerprint =>
      _selectedPgpFingerprint ??
      (_pgpKeys.length == 1 ? _pgpKeys.single.fingerprint : null);

  @override
  void initState() {
    super.initState();
    _step = _initialStep();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _stepHistory.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _goBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
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
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_stepSubtitle(context.l10n, _step)),
                const SizedBox(height: 16),
                _OnboardingProgress(currentStep: _step, steps: _progressSteps),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Expanded(child: _buildStep(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _OnboardingStep _initialStep() {
    if (!widget.securityRepository.hasGestureVerifier) {
      return _OnboardingStep.gesture;
    }
    if (_needsStoreSetup || _needsKeyRepair) {
      return _OnboardingStep.pgp;
    }
    if (!widget.securityRepository.biometricUnlockEnabled) {
      return _OnboardingStep.biometrics;
    }
    return _OnboardingStep.pgp;
  }

  List<_OnboardingStep> get _progressSteps => <_OnboardingStep>[
    _OnboardingStep.gesture,
    _OnboardingStep.biometrics,
    _OnboardingStep.pgp,
    _OnboardingStep.ssh,
    if (_needsStoreSetup) _OnboardingStep.store,
    _OnboardingStep.review,
  ];

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
          onEnable: () => _setStep(_OnboardingStep.pgp),
          onSkip: () => _setStep(_OnboardingStep.pgp),
          onError: _showError,
        );
      case _OnboardingStep.pgp:
        return _buildPgpStep(context);
      case _OnboardingStep.ssh:
        return _buildSshStep(context);
      case _OnboardingStep.store:
        return _buildStoreStep(context);
      case _OnboardingStep.review:
        return _buildReviewStep(context);
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
        onPressed: () => _setStep(_OnboardingStep.review),
      );
    }

    if (!lifecycle.requiresStoreSetup) {
      final store = lifecycle.selectedStore;
      return ListView(
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(store?.name ?? repository.currentRepoName),
              subtitle: Text(store?.root ?? lifecycle.configPath),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _setStep(_OnboardingStep.review),
            child: SizedBox(
              width: double.infinity,
              child: Center(child: Text(context.l10n.continueAction)),
            ),
          ),
        ],
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
      selectedPgpFingerprint: _effectivePgpFingerprint,
      hasSshKey: _sshKeys.isNotEmpty,
      pathPickerService: widget.pathPickerService,
      onCreateLocalStore: ({
        required String name,
        required String root,
        required List<String> pgpKeys,
        required bool initializeGit,
      }) {
        return repository.createLocalStore(
          name: name,
          root: root,
          pgpKeys: pgpKeys,
          setDefault: true,
          initializeGit: initializeGit,
        );
      },
      onImportLocalStore: (String root) {
        return repository.importLocalStore(root: root, setDefault: true);
      },
      onCloneStore: ({required String remoteUrl, required String root}) {
        return repository.cloneStore(
          remoteUrl: remoteUrl,
          root: root,
          setDefault: true,
        );
      },
      onStoreChanged: () async {
        await repository.refresh();
        await _attachSelectedPgpKeyToCurrentStore();
        await repository.refresh();
        if (!mounted) {
          return;
        }
        if (!_needsStoreSetup) {
          _setStep(_OnboardingStep.review);
          return;
        }
        setState(() {});
      },
    );
  }

  Widget _buildPgpStep(BuildContext context) {
    final repository = _keyRepository;
    if (repository == null) {
      return _EmptyOnboardingStep(
        icon: Icons.enhanced_encryption_outlined,
        title: context.l10n.noKeyRepository,
        buttonLabel: context.l10n.continueAction,
        onPressed: () => _setStep(_OnboardingStep.ssh),
      );
    }

    return _PgpSetupStep(
      keys: _pgpKeys,
      onUseKey: (key) => _usePgpKey(repository, key),
      onCreateKey: () => _showCreatePgpKeyForm(context, repository),
      onImportKey: () => _showImportPgpKeyForm(context, repository),
    );
  }

  Widget _buildSshStep(BuildContext context) {
    final repository = _keyRepository;
    if (repository == null) {
      return _EmptyOnboardingStep(
        icon: Icons.vpn_key_off_outlined,
        title: context.l10n.noSshRepository,
        buttonLabel: context.l10n.continueAction,
        onPressed: () => _setStep(_OnboardingStep.review),
      );
    }

    return _SshSetupStep(
      keys: _sshKeys,
      onCreateKey: () => _showCreateSshKeyForm(context, repository),
      onImportKey: () => _showImportSshKeyForm(context, repository),
      onOpenGithubSettings: () => _showGithubSettings(context, repository),
      onSkip:
          () => _setStep(
            _needsStoreSetup ? _OnboardingStep.store : _OnboardingStep.review,
          ),
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final lifecycle = _lifecycle;
    final selectedStore = lifecycle?.selectedStore;
    return _ReviewStep(
      hasGestureVerifier: widget.securityRepository.hasGestureVerifier,
      biometricUnlockEnabled: widget.securityRepository.biometricUnlockEnabled,
      storeStatusLabel:
          selectedStore != null && selectedStore.exists
              ? context.l10n.configured
              : lifecycle?.onboardingState.label ?? context.l10n.unavailable,
      storeSetupComplete: !_needsStoreSetup && !_needsKeyRepair,
      pgpKeyCount: _pgpKeys.length,
      sshKeyCount: _sshKeys.length,
      onFinish: _finishOnboarding,
    );
  }

  void _setStep(_OnboardingStep step, {bool recordHistory = true}) {
    setState(() {
      if (recordHistory && step != _step) {
        _stepHistory.add(_step);
      }
      _step = step;
      _error = null;
    });
  }

  void _goBack() {
    if (_stepHistory.isEmpty) {
      return;
    }
    final previous = _stepHistory.removeLast();
    _setStep(previous, recordHistory: false);
  }

  void _showError(Object error) {
    final message = UiProblem.fromError(context.l10n, error).summary;
    setState(() => _error = message);
  }

  Future<void> _usePgpKey(KeyRepository repository, KeyRecord key) async {
    await _runOnboardingAction(() async {
      await _finishPgpStep(repository, key);
    });
  }

  Future<void> _finishPgpStep(KeyRepository repository, KeyRecord key) async {
    _selectedPgpFingerprint = key.fingerprint;
    if (!_needsStoreSetup) {
      await repository.addPgpKeyToSelectedStore(key.fingerprint);
      await widget.settingsRepository?.refresh();
    }
    _setStep(_OnboardingStep.ssh);
  }

  Future<void> _attachSelectedPgpKeyToCurrentStore() async {
    final fingerprint = _effectivePgpFingerprint;
    final repository = _keyRepository;
    if (fingerprint == null ||
        repository == null ||
        _lifecycle?.selectedStore == null) {
      return;
    }
    await repository.addPgpKeyToSelectedStore(fingerprint);
  }

  void _showCreatePgpKeyForm(BuildContext context, KeyRepository repository) {
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
          await _finishPgpStep(repository, key);
        } finally {
          passphrase.clear();
        }
      },
    );
  }

  /// Opens the shared PGP import flow, the same one Settings uses.
  ///
  /// Onboarding only advances to SSH once the key is imported and, for a protected private key, its
  /// passphrase has been validated.
  void _showImportPgpKeyForm(BuildContext context, KeyRepository repository) {
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
                      onCancel: () => Navigator.of(sheet).pop(),
                      onCompleted: (completion) async {
                        if (sheet.mounted) {
                          Navigator.of(sheet).pop();
                        }
                        if (completion.rememberFailed && mounted) {
                          setState(
                            () =>
                                _error = context.l10n.importedKeyRememberFailed(
                                  completion.key.name,
                                ),
                          );
                        }
                        // Selects the returned fingerprint and advances to SSH.
                        await _finishPgpStep(repository, completion.key);
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
    final selectedRoot = _lifecycle?.selectedStoreRoot;
    if (selectedRoot != null && selectedRoot.trim().isNotEmpty) {
      return parentDirectory(selectedRoot);
    }
    final configPath = _lifecycle?.configPath;
    if (configPath != null && configPath.trim().isNotEmpty) {
      return parentDirectory(configPath);
    }
    return defaultUserDirectory();
  }

  void _showCreateSshKeyForm(BuildContext context, KeyRepository repository) {
    final name = TextEditingController(text: 'github-mobile-ed25519');
    _showOnboardingForm(
      context: context,
      title: context.l10n.generateSshKey,
      fields: <Widget>[_CreateSshKeyFields(name: name)],
      submitLabel: context.l10n.generateSshKey,
      onSubmit: () async {
        await repository.generateSshKey(name.text);
        _setStep(
          _needsStoreSetup ? _OnboardingStep.store : _OnboardingStep.review,
        );
      },
    );
  }

  void _showImportSshKeyForm(BuildContext context, KeyRepository repository) {
    final name = TextEditingController();
    final privateKey = TextEditingController();
    _showOnboardingForm(
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
          _setStep(
            _needsStoreSetup ? _OnboardingStep.store : _OnboardingStep.review,
          );
        } finally {
          privateKey.clear();
        }
      },
    );
  }

  Future<void> _showGithubSettings(
    BuildContext context,
    KeyRepository repository,
  ) async {
    final url = await repository.githubSshSettingsUri();
    if (!context.mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(context.l10n.githubSshSettings),
            content: SelectableText(url.toString()),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.close),
              ),
            ],
          ),
    );
  }

  void _showOnboardingForm({
    required BuildContext context,
    required String title,
    required List<Widget> fields,
    required String submitLabel,
    required Future<void> Function() onSubmit,
  }) {
    showModalBottomSheet<void>(
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
      if (mounted) {
        _showError(error);
      }
    }
  }

  Future<void> _finishOnboarding() async {
    if (_needsStoreSetup || _needsKeyRepair) {
      setState(() => _error = context.l10n.selectPrivatePgpKey);
      return;
    }
    await widget.securityRepository.setOnboardingComplete(true);
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (!mounted) {
      return;
    }
    widget.onComplete();
  }

  String _stepTitle(AppLocalizations localizations, _OnboardingStep step) {
    return switch (step) {
      _OnboardingStep.gesture => localizations.setGestureLock,
      _OnboardingStep.biometrics => localizations.enableBiometricUnlock,
      _OnboardingStep.pgp => localizations.choosePgpKey,
      _OnboardingStep.ssh => localizations.setupSshGithub,
      _OnboardingStep.store => localizations.setupPasswordStore,
      _OnboardingStep.review => localizations.reviewSetup,
    };
  }

  String _stepSubtitle(AppLocalizations localizations, _OnboardingStep step) {
    return switch (step) {
      _OnboardingStep.gesture => localizations.gestureStepSubtitle,
      _OnboardingStep.biometrics => localizations.biometricsStepSubtitle,
      _OnboardingStep.pgp => localizations.pgpStepSubtitle,
      _OnboardingStep.ssh => localizations.sshStepSubtitle,
      _OnboardingStep.store =>
        _needsStoreSetup
            ? localizations.createImportCloneStore
            : localizations.storeAvailable,
      _OnboardingStep.review => localizations.reviewStepSubtitle,
    };
  }
}
