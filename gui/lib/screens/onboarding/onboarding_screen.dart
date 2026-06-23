import 'package:flutter/material.dart';

import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../widgets/gesture_lock_input.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.securityRepository,
    this.settingsRepository,
  });

  final VoidCallback onComplete;
  final SecurityRepository securityRepository;
  final SettingsRepository? settingsRepository;

  @override
  Widget build(BuildContext context) {
    final lifecycle = settingsRepository?.lifecycle;
    final needsStoreSetup = lifecycle?.onboardingState.requiresSetup ?? false;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              Text(
                needsStoreSetup ? 'Set up password store' : 'Set gesture lock',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                needsStoreSetup
                    ? lifecycle!.onboardingState.label
                    : 'Use a 9-dot gesture as the local Pars unlock method. Biometrics can be enabled after setup.',
              ),
              const SizedBox(height: 24),
              Expanded(
                child:
                    needsStoreSetup
                        ? _StoreSetupActions(
                          repository: settingsRepository!,
                          lifecycle: lifecycle!,
                        )
                        : _GestureSetup(
                          securityRepository: securityRepository,
                          onComplete: onComplete,
                        ),
              ),
              if (needsStoreSetup)
                FilledButton(
                  onPressed: onComplete,
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(child: Text('Continue')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GestureSetup extends StatefulWidget {
  const _GestureSetup({
    required this.securityRepository,
    required this.onComplete,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onComplete;

  @override
  State<_GestureSetup> createState() => _GestureSetupState();
}

class _GestureSetupState extends State<_GestureSetup> {
  List<int>? _initialPattern;
  String? _message;
  bool _isSaving = false;

  bool get _isConfirming => _initialPattern != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: GestureLockInput(
              enabled: !_isSaving,
              onCompleted: (pattern) => _handlePattern(context, pattern),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text(
            _message ??
                (_isConfirming
                    ? 'Draw the same gesture again.'
                    : 'Draw at least 4 dots.'),
            key: ValueKey<String>(_message ?? 'default-$_isConfirming'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  _message == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed:
              _initialPattern == null || _isSaving
                  ? null
                  : () => setState(() {
                    _initialPattern = null;
                    _message = 'Start again with a new gesture.';
                  }),
          child: const SizedBox(
            width: double.infinity,
            child: Center(child: Text('Reset gesture')),
          ),
        ),
      ],
    );
  }

  Future<void> _handlePattern(BuildContext context, List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() => _message = 'Use at least 4 dots.');
      return;
    }
    final first = _initialPattern;
    if (first == null) {
      setState(() {
        _initialPattern = pattern;
        _message = 'Gesture captured. Confirm it once more.';
      });
      return;
    }
    if (!_samePattern(first, pattern)) {
      setState(() {
        _initialPattern = null;
        _message = 'Gestures did not match. Start again.';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _message = 'Gesture confirmed.';
    });
    await widget.securityRepository.saveGestureVerifier(
      GestureVerifier.fromPattern(pattern),
    );
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (context.mounted) {
      widget.onComplete();
    }
  }

  bool _samePattern(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}

class _StoreSetupActions extends StatelessWidget {
  const _StoreSetupActions({required this.repository, required this.lifecycle});

  final SettingsRepository repository;
  final StoreLifecycleSnapshot lifecycle;

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
          onPressed: () => _showCloneStore(context),
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('Clone Git store'),
        ),
      ],
    );
  }

  void _showCreateLocalStore(BuildContext context) {
    final name = TextEditingController(text: 'Personal');
    final root = TextEditingController();
    final keys = TextEditingController();
    _showStoreForm(
      context: context,
      title: 'Create local store',
      fields: <Widget>[
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: root,
          decoration: const InputDecoration(labelText: 'Local path'),
        ),
        TextField(
          controller: keys,
          decoration: const InputDecoration(labelText: 'PGP keys'),
        ),
      ],
      submitLabel: 'Create',
      onSubmit:
          () => repository.createLocalStore(
            name: name.text,
            root: root.text,
            pgpKeys: keys.text
                .split(',')
                .map((key) => key.trim())
                .where((key) => key.isNotEmpty)
                .toList(growable: false),
            setDefault: true,
            initializeGit: true,
          ),
    );
  }

  void _showImportLocalStore(BuildContext context) {
    final root = TextEditingController();
    _showStoreForm(
      context: context,
      title: 'Import local store',
      fields: <Widget>[
        TextField(
          controller: root,
          decoration: const InputDecoration(labelText: 'Local path'),
        ),
      ],
      submitLabel: 'Import',
      onSubmit:
          () => repository.importLocalStore(root: root.text, setDefault: true),
    );
  }

  void _showCloneStore(BuildContext context) {
    final remote = TextEditingController();
    final root = TextEditingController();
    _showStoreForm(
      context: context,
      title: 'Clone Git store',
      fields: <Widget>[
        TextField(
          controller: remote,
          decoration: const InputDecoration(labelText: 'Remote URL'),
        ),
        TextField(
          controller: root,
          decoration: const InputDecoration(labelText: 'Local path'),
        ),
      ],
      submitLabel: 'Clone',
      onSubmit:
          () => repository.cloneStore(
            remoteUrl: remote.text,
            root: root.text,
            setDefault: true,
          ),
    );
  }

  void _showStoreForm({
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
          (context) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...fields,
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await onSubmit();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
                        }
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
    );
  }
}
