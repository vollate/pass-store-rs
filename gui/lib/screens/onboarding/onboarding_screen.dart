import 'package:flutter/material.dart';

import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../widgets/gesture_setup_panel.dart';

class OnboardingScreen extends StatefulWidget {
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
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late bool _gestureConfigured;

  @override
  void initState() {
    super.initState();
    _gestureConfigured = widget.securityRepository.hasGestureVerifier;
  }

  @override
  Widget build(BuildContext context) {
    final lifecycle = widget.settingsRepository?.lifecycle;
    final needsStoreSetup = lifecycle?.onboardingState.requiresSetup ?? false;
    final needsGestureSetup = !_gestureConfigured;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              Text(
                needsGestureSetup
                    ? 'Set gesture lock'
                    : 'Set up password store',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                needsGestureSetup
                    ? 'Use a 9-dot gesture as the local Pars unlock method. Biometrics can be enabled after setup.'
                    : needsStoreSetup
                    ? lifecycle!.onboardingState.label
                    : 'Your local unlock method is configured.',
              ),
              const SizedBox(height: 24),
              Expanded(
                child:
                    needsGestureSetup
                        ? GestureSetupPanel(
                          securityRepository: widget.securityRepository,
                          onSaved: () {
                            if (needsStoreSetup) {
                              setState(() => _gestureConfigured = true);
                            } else {
                              widget.onComplete();
                            }
                          },
                        )
                        : needsStoreSetup
                        ? _StoreSetupActions(
                          repository: widget.settingsRepository!,
                          lifecycle: lifecycle!,
                        )
                        : const SizedBox.shrink(),
              ),
              if (!needsGestureSetup && needsStoreSetup)
                FilledButton(
                  onPressed: widget.onComplete,
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
