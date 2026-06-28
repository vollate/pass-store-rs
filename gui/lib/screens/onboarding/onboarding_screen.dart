import 'package:flutter/material.dart';

import '../../models/key_record.dart';
import '../../services/key_repository.dart';
import '../../services/path_picker_service.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../widgets/gesture_setup_panel.dart';
import '../../widgets/path_picker_row.dart';

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

  bool get _needsStoreSetup =>
      _lifecycle?.onboardingState.requiresSetup ?? false;

  List<KeyRecord> get _pgpKeys =>
      _keyRepository?.keys
          .where((key) => key.type == KeyRecordType.pgp)
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
                        tooltip: 'Back',
                        onPressed: _goBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: Text(
                        _stepTitle(_step),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_stepSubtitle(_step)),
                const SizedBox(height: 16),
                _StepRail(currentStep: _step),
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
    if (_needsStoreSetup) {
      return _OnboardingStep.pgp;
    }
    if (!widget.securityRepository.biometricUnlockEnabled) {
      return _OnboardingStep.biometrics;
    }
    return _OnboardingStep.pgp;
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
        title: 'No store repository available',
        buttonLabel: 'Continue',
        onPressed: () => _setStep(_OnboardingStep.review),
      );
    }

    if (!lifecycle.onboardingState.requiresSetup) {
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
            child: const SizedBox(
              width: double.infinity,
              child: Center(child: Text('Continue')),
            ),
          ),
        ],
      );
    }

    return _StoreSetupActions(
      repository: repository,
      lifecycle: lifecycle,
      selectedPgpFingerprint: _effectivePgpFingerprint,
      hasSshKey: _sshKeys.isNotEmpty,
      pathPickerService: widget.pathPickerService,
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
        title: 'No key repository available',
        buttonLabel: 'Continue',
        onPressed: () => _setStep(_OnboardingStep.ssh),
      );
    }

    return ListView(
      children: <Widget>[
        if (_pgpKeys.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.key_off_outlined),
            title: Text('No PGP keys found'),
            subtitle: Text('Create or import a key to encrypt entries.'),
          )
        else
          for (final key in _pgpKeys)
            Card(
              child: ListTile(
                title: Text(key.name),
                subtitle: Text('${key.fingerprint}\n${key.source}'),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: () => _usePgpKey(repository, key),
                  child: const Text('Use PGP key'),
                ),
              ),
            ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => _showCreatePgpKeyForm(context, repository),
              icon: const Icon(Icons.add),
              label: const Text('Create PGP key'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showImportPgpKeyForm(context, repository),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import PGP key'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSshStep(BuildContext context) {
    final repository = _keyRepository;
    if (repository == null) {
      return _EmptyOnboardingStep(
        icon: Icons.vpn_key_off_outlined,
        title: 'No SSH repository available',
        buttonLabel: 'Continue',
        onPressed: () => _setStep(_OnboardingStep.review),
      );
    }

    return ListView(
      children: <Widget>[
        if (_sshKeys.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vpn_key_outlined),
            title: Text('No SSH keys configured'),
            subtitle: Text('SSH is optional and can be added later.'),
          )
        else
          for (final key in _sshKeys)
            Card(
              child: ListTile(
                title: Text(key.name),
                subtitle: Text('${key.fingerprint}\n${key.source}'),
                isThreeLine: true,
              ),
            ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => _showCreateSshKeyForm(context, repository),
              icon: const Icon(Icons.add),
              label: const Text('Generate SSH key'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showImportSshKeyForm(context, repository),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import SSH key'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showGithubSettings(context, repository),
              icon: const Icon(Icons.open_in_new),
              label: const Text('GitHub settings'),
            ),
            TextButton(
              onPressed:
                  () => _setStep(
                    _needsStoreSetup
                        ? _OnboardingStep.store
                        : _OnboardingStep.review,
                  ),
              child: const Text('Skip SSH'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final lifecycle = _lifecycle;
    return ListView(
      children: <Widget>[
        _ReviewTile(
          label: 'Gesture lock',
          value:
              widget.securityRepository.hasGestureVerifier
                  ? 'Configured'
                  : 'Required',
          complete: widget.securityRepository.hasGestureVerifier,
        ),
        _ReviewTile(
          label: 'Biometrics',
          value:
              widget.securityRepository.biometricUnlockEnabled
                  ? 'Enabled'
                  : 'Skipped',
          complete: true,
        ),
        _ReviewTile(
          label: 'Password store',
          value: lifecycle?.onboardingState.label ?? 'Unavailable',
          complete: !_needsStoreSetup,
        ),
        _ReviewTile(
          label: 'PGP key',
          value: _pgpKeys.isEmpty ? 'Not found' : '${_pgpKeys.length} key(s)',
          complete: _pgpKeys.isNotEmpty,
        ),
        _ReviewTile(
          label: 'SSH key',
          value: _sshKeys.isEmpty ? 'Skipped' : '${_sshKeys.length} key(s)',
          complete: true,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _needsStoreSetup ? null : _finishOnboarding,
          child: const SizedBox(
            width: double.infinity,
            child: Center(child: Text('Finish setup')),
          ),
        ),
      ],
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
    final message = error is StateError ? error.message : error.toString();
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
    }
    _setStep(_OnboardingStep.ssh);
  }

  Future<void> _attachSelectedPgpKeyToCurrentStore() async {
    final fingerprint = _effectivePgpFingerprint;
    final repository = _keyRepository;
    if (fingerprint == null ||
        repository == null ||
        _lifecycle?.selectedStore == null ||
        !_needsStoreSetup) {
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
      title: 'Create PGP key',
      fields: <Widget>[
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        TextField(
          controller: passphrase,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
      ],
      submitLabel: 'Create',
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

  void _showImportPgpKeyForm(BuildContext context, KeyRepository repository) {
    final keyText = TextEditingController();
    _showOnboardingForm(
      context: context,
      title: 'Import PGP key',
      fields: <Widget>[
        TextField(
          controller: keyText,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Key text'),
        ),
      ],
      submitLabel: 'Import',
      onSubmit: () async {
        try {
          final key =
              keyText.text.contains('PGP PRIVATE KEY BLOCK')
                  ? await repository.importPgpPrivateKeyText(keyText.text)
                  : await repository.importPgpPublicKeyText(keyText.text);
          await _finishPgpStep(repository, key);
        } finally {
          keyText.clear();
        }
      },
    );
  }

  void _showCreateSshKeyForm(BuildContext context, KeyRepository repository) {
    final name = TextEditingController(text: 'github-mobile-ed25519');
    _showOnboardingForm(
      context: context,
      title: 'Generate SSH key',
      fields: <Widget>[
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
      ],
      submitLabel: 'Generate',
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
      title: 'Import SSH key',
      fields: <Widget>[
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: privateKey,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Private key'),
        ),
      ],
      submitLabel: 'Import',
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
            title: const Text('GitHub SSH settings'),
            content: SelectableText(url.toString()),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
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
    await widget.securityRepository.setOnboardingComplete(true);
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (!mounted) {
      return;
    }
    widget.onComplete();
  }

  String _stepTitle(_OnboardingStep step) {
    switch (step) {
      case _OnboardingStep.gesture:
        return 'Set gesture lock';
      case _OnboardingStep.biometrics:
        return 'Enable biometric unlock';
      case _OnboardingStep.pgp:
        return 'Choose PGP key';
      case _OnboardingStep.ssh:
        return 'Set up SSH for GitHub';
      case _OnboardingStep.store:
        return 'Set up password store';
      case _OnboardingStep.review:
        return 'Review setup';
    }
  }

  String _stepSubtitle(_OnboardingStep step) {
    switch (step) {
      case _OnboardingStep.gesture:
        return 'Use a 9-dot gesture as the local Pars unlock method.';
      case _OnboardingStep.biometrics:
        return 'Biometrics are optional and keep the gesture as fallback.';
      case _OnboardingStep.pgp:
        return 'Select, create, or import the key used by pass entries.';
      case _OnboardingStep.ssh:
        return 'SSH is optional and helps Git sync with GitHub.';
      case _OnboardingStep.store:
        return _lifecycle?.onboardingState.label ??
            'Create, import, or clone a password store.';
      case _OnboardingStep.review:
        return 'Confirm the setup before entering Pars.';
    }
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.currentStep});

  final _OnboardingStep currentStep;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final step in _OnboardingStep.values)
          ChoiceChip(
            label: Text(_shortLabel(step)),
            selected: step == currentStep,
            onSelected: null,
          ),
      ],
    );
  }

  String _shortLabel(_OnboardingStep step) {
    switch (step) {
      case _OnboardingStep.gesture:
        return 'Gesture';
      case _OnboardingStep.biometrics:
        return 'Biometrics';
      case _OnboardingStep.pgp:
        return 'PGP';
      case _OnboardingStep.ssh:
        return 'SSH';
      case _OnboardingStep.store:
        return 'Store';
      case _OnboardingStep.review:
        return 'Review';
    }
  }
}

class _BiometricSetupStep extends StatelessWidget {
  const _BiometricSetupStep({
    required this.securityRepository,
    required this.onEnable,
    required this.onSkip,
    required this.onError,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onEnable;
  final VoidCallback onSkip;
  final void Function(Object error) onError;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BiometricUnlockStatus>(
      future: securityRepository.biometricUnlockStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? BiometricUnlockStatus.unavailable;
        return ListView(
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                status == BiometricUnlockStatus.unavailable
                    ? Icons.fingerprint_outlined
                    : Icons.fingerprint,
              ),
              title: const Text('Biometric unlock'),
              subtitle: Text(_biometricSubtitle(status)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  status == BiometricUnlockStatus.unavailable
                      ? null
                      : () async {
                        try {
                          await securityRepository.setBiometricUnlockEnabled(
                            true,
                          );
                          onEnable();
                        } catch (error) {
                          onError(error);
                        }
                      },
              icon: const Icon(Icons.fingerprint),
              label: const Text('Enable biometric unlock'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onSkip,
              child: const SizedBox(
                width: double.infinity,
                child: Center(child: Text('Skip biometrics')),
              ),
            ),
          ],
        );
      },
    );
  }

  String _biometricSubtitle(BiometricUnlockStatus status) {
    switch (status) {
      case BiometricUnlockStatus.available:
        return 'Enabled on this device';
      case BiometricUnlockStatus.disabled:
        return 'Available on this device';
      case BiometricUnlockStatus.unavailable:
        return 'Unavailable on this device';
    }
  }
}

class _OnboardingFormSheet extends StatefulWidget {
  const _OnboardingFormSheet({
    required this.title,
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final List<Widget> fields;
  final String submitLabel;
  final Future<void> Function() onSubmit;

  @override
  State<_OnboardingFormSheet> createState() => _OnboardingFormSheetState();
}

class _OnboardingFormSheetState extends State<_OnboardingFormSheet> {
  bool _isSubmitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...widget.fields,
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(
                    child:
                        _isSubmitting
                            ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(widget.submitLabel),
                              ],
                            )
                            : Text(widget.submitLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isSubmitting = false;
        });
      }
    }
  }
}

class _EmptyOnboardingStep extends StatelessWidget {
  const _EmptyOnboardingStep({
    required this.icon,
    required this.title,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: onPressed,
          child: SizedBox(
            width: double.infinity,
            child: Center(child: Text(buttonLabel)),
          ),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.label,
    required this.value,
    required this.complete,
  });

  final String label;
  final String value;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        complete ? Icons.check_circle_outline : Icons.error_outline,
        color: complete ? null : Theme.of(context).colorScheme.error,
      ),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class _StoreSetupActions extends StatelessWidget {
  const _StoreSetupActions({
    required this.repository,
    required this.lifecycle,
    required this.selectedPgpFingerprint,
    required this.hasSshKey,
    required this.pathPickerService,
    required this.onStoreChanged,
  });

  final SettingsRepository repository;
  final StoreLifecycleSnapshot lifecycle;
  final String? selectedPgpFingerprint;
  final bool hasSshKey;
  final PathPickerService pathPickerService;
  final Future<void> Function() onStoreChanged;

  AppManagedPathRepository? get _managedPaths {
    if (repository is AppManagedPathRepository) {
      final managedPaths = repository as AppManagedPathRepository;
      return managedPaths.usesAppManagedPaths ? managedPaths : null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        for (final issue in lifecycle.issues)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(issue.replaceAll('_', ' ')),
            subtitle: Text(lifecycle.configPath),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _showCreateLocalStore(context),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Create local store'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showImportLocalStore(context),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Import local store'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: hasSshKey ? () => _showCloneStore(context) : null,
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('Clone Git store'),
        ),
        if (!hasSshKey)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('Add an SSH key before cloning a Git store.'),
          ),
      ],
    );
  }

  void _showCreateLocalStore(BuildContext context) {
    final name = TextEditingController(text: 'Personal');
    final managedPaths = _managedPaths;
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Create local store',
      submitLabel: 'Create',
      canSubmit: () => managedPaths != null || selectedBase != null,
      onSubmit:
          () => repository.createLocalStore(
            name: name.text,
            root:
                managedPaths?.storeRootForName(name.text) ??
                joinFilesystemPath(selectedBase!, slugPathSegment(name.text)),
            pgpKeys:
                selectedPgpFingerprint == null
                    ? const <String>[]
                    : <String>[selectedPgpFingerprint!],
            setDefault: true,
            initializeGit: managedPaths == null,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: 12),
            PathPickerRow(
              title: 'Store folder',
              path:
                  managedPaths?.storeRootForName(name.text) ??
                  joinFilesystemPath(
                    selectedBase ?? defaultBase,
                    slugPathSegment(name.text),
                  ),
              isSelected: selectedBase != null,
              onPressed:
                  managedPaths == null
                      ? () => _chooseFolder(
                        sheetContext,
                        initialDirectory: defaultBase,
                        onSelected:
                            (path) => setSheetState(() {
                              selectedBase = path;
                            }),
                      )
                      : null,
            ),
          ],
    );
  }

  void _showImportLocalStore(BuildContext context) {
    final defaultBase = _defaultStoreBasePath();
    String? selectedRoot;
    _showPickerStoreForm(
      context: context,
      title: 'Import local store',
      submitLabel: 'Import',
      canSubmit: () => selectedRoot != null,
      onSubmit:
          () => repository.importLocalStore(
            root: selectedRoot!,
            setDefault: true,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            PathPickerRow(
              title: 'Store folder',
              path: selectedRoot ?? defaultBase,
              isSelected: selectedRoot != null,
              onPressed:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedRoot = path;
                        }),
                  ),
            ),
          ],
    );
  }

  void _showCloneStore(BuildContext context) {
    final remote = TextEditingController();
    final managedPaths = _managedPaths;
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Clone Git store',
      submitLabel: 'Clone',
      canSubmit:
          () => hasSshKey && (managedPaths != null || selectedBase != null),
      onSubmit:
          hasSshKey
              ? () => repository.cloneStore(
                remoteUrl: remote.text,
                root:
                    managedPaths?.storeRootForRemote(remote.text) ??
                    joinFilesystemPath(
                      selectedBase!,
                      slugFromRemoteUrl(remote.text),
                    ),
                setDefault: true,
              )
              : null,
      builder:
          (sheetContext, setSheetState) => <Widget>[
            TextField(
              controller: remote,
              decoration: const InputDecoration(labelText: 'Remote URL'),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: 12),
            PathPickerRow(
              title: 'Store folder',
              path:
                  managedPaths?.storeRootForRemote(remote.text) ??
                  joinFilesystemPath(
                    selectedBase ?? defaultBase,
                    slugFromRemoteUrl(remote.text),
                  ),
              isSelected: selectedBase != null,
              onPressed:
                  managedPaths == null
                      ? () => _chooseFolder(
                        sheetContext,
                        initialDirectory: defaultBase,
                        onSelected:
                            (path) => setSheetState(() {
                              selectedBase = path;
                            }),
                      )
                      : null,
            ),
          ],
    );
  }

  Future<void> _chooseFolder(
    BuildContext context, {
    required String initialDirectory,
    required ValueChanged<String> onSelected,
  }) async {
    try {
      final path = await pathPickerService.pickFolder(
        initialDirectory: initialDirectory,
      );
      if (path == null) {
        return;
      }
      onSelected(path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String _defaultStoreBasePath() {
    final selectedRoot = lifecycle.selectedStoreRoot;
    if (selectedRoot != null && selectedRoot.trim().isNotEmpty) {
      return parentDirectory(selectedRoot);
    }
    if (lifecycle.stores.isNotEmpty) {
      return parentDirectory(lifecycle.stores.first.root);
    }
    return parentDirectory(lifecycle.configPath);
  }

  void _showPickerStoreForm({
    required BuildContext context,
    required String title,
    required String submitLabel,
    required bool Function() canSubmit,
    required List<Widget> Function(BuildContext, StateSetter) builder,
    required Future<void> Function()? onSubmit,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSheetState) {
              var isSubmitting = false;
              String? error;
              return StatefulBuilder(
                builder:
                    (context, setSubmitState) => SafeArea(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 20,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 12),
                              ...builder(context, (callback) {
                                setSheetState(callback);
                              }),
                              if (error != null) ...<Widget>[
                                const SizedBox(height: 12),
                                Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed:
                                    isSubmitting ||
                                            !canSubmit() ||
                                            onSubmit == null
                                        ? null
                                        : () async {
                                          setSubmitState(() {
                                            isSubmitting = true;
                                            error = null;
                                          });
                                          try {
                                            await onSubmit();
                                            await onStoreChanged();
                                            if (context.mounted) {
                                              Navigator.of(context).pop();
                                            }
                                          } catch (caught) {
                                            if (!context.mounted) return;
                                            setSubmitState(() {
                                              error = caught.toString();
                                              isSubmitting = false;
                                            });
                                          }
                                        },
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Center(child: Text(submitLabel)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              );
            },
          ),
    );
  }
}
