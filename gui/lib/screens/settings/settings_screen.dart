import 'package:flutter/material.dart';

import '../../models/key_record.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
    required this.securityRepository,
    this.onSecuritySettingsChanged,
  });

  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final VoidCallback? onSecuritySettingsChanged;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: <Widget>[
              _SettingsSection(
                title: 'Security',
                children: <Widget>[
                  _SettingsTile(
                    title: 'Gesture lock and biometrics',
                    subtitle:
                        securityRepository.lockOnResume
                            ? 'Lock on app resume'
                            : 'Gesture unlock configured',
                    icon: Icons.pattern,
                    onTap: () => _showSecuritySheet(context),
                  ),
                  _SettingsTile(
                    title: 'PGP session timeout',
                    subtitle: '15 min',
                    icon: Icons.timer_outlined,
                    onTap: () => _showTextSheet(context, 'PGP session timeout'),
                  ),
                  _SettingsTile(
                    title: 'KMS / Keychain passphrase',
                    subtitle: 'Optional one-step unlock',
                    icon: Icons.key_outlined,
                    onTap:
                        () => _showTextSheet(
                          context,
                          'KMS / Keychain passphrase',
                        ),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Key management',
                children: <Widget>[
                  _SettingsTile(
                    title: 'PGP keys',
                    subtitle: 'Create, import, export, delete',
                    icon: Icons.enhanced_encryption_outlined,
                    onTap: () => _showKeys(context, KeyRecordType.pgp),
                  ),
                  _SettingsTile(
                    title: 'SSH keys',
                    subtitle: 'GitHub access keys',
                    icon: Icons.vpn_key_outlined,
                    onTap: () => _showKeys(context, KeyRecordType.ssh),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Password stores and Git',
                children: <Widget>[
                  _SettingsTile(
                    title: 'Password stores',
                    subtitle: settingsRepository.currentRepoName,
                    icon: Icons.folder_outlined,
                    onTap: () => _showPasswordStores(context),
                  ),
                  _SettingsTile(
                    title: 'Git sync and remotes',
                    subtitle: 'Pull, push, status, remotes',
                    icon: Icons.sync,
                    onTap:
                        () => _showTextSheet(context, 'Git sync and remotes'),
                  ),
                  _SettingsTile(
                    title: 'Advanced git args',
                    subtitle: 'Arguments after git only',
                    icon: Icons.terminal,
                    onTap: () => _showGitArgs(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTextSheet(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                  const Text(
                    'This configuration surface is mocked in phase 1 and will be wired to platform services later.',
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showSecuritySheet(BuildContext context) {
    final timeoutOptions = <Duration>[
      const Duration(minutes: 1),
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(hours: 1),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Gesture lock and biometrics',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Require unlock on app resume'),
                          subtitle: const Text(
                            'Gesture unlock is used as fallback',
                          ),
                          value: securityRepository.lockOnResume,
                          onChanged: (value) async {
                            await securityRepository.setLockOnResume(value);
                            onSecuritySettingsChanged?.call();
                            setSheetState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Auto-lock timeout',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final timeout in timeoutOptions)
                              ChoiceChip(
                                label: Text(_timeoutLabel(timeout)),
                                selected:
                                    securityRepository.autoLockTimeout ==
                                    timeout,
                                onSelected: (_) async {
                                  await securityRepository.setAutoLockTimeout(
                                    timeout,
                                  );
                                  onSecuritySettingsChanged?.call();
                                  setSheetState(() {});
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.fingerprint_outlined),
                          title: const Text('Biometric unlock'),
                          subtitle: const Text(
                            'Unavailable until platform integration',
                          ),
                          trailing: const Icon(Icons.lock_outline),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  String _timeoutLabel(Duration timeout) {
    if (timeout.inMinutes < 60) {
      return '${timeout.inMinutes} min';
    }
    return '${timeout.inHours} hour';
  }

  void _showKeys(BuildContext context, KeyRecordType type) {
    final keys = keyRepository.keys.where((key) => key.type == type).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      type == KeyRecordType.pgp ? 'PGP keys' : 'SSH keys',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final key in keys)
                      Card(
                        child: ListTile(
                          title: Text(key.name),
                          subtitle: Text('${key.fingerprint}\n${key.source}'),
                          isThreeLine: true,
                          trailing: Text(
                            key.hasPrivateKey ? 'Private' : 'Public',
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton(
                          onPressed: () => _showCreateKeyForm(context, type),
                          child: const Text('Create'),
                        ),
                        OutlinedButton(
                          onPressed: () => _showImportKeyForm(context, type),
                          child: const Text('Import'),
                        ),
                        OutlinedButton(
                          onPressed:
                              () => _showImportKeyFileForm(context, type),
                          child: const Text('Import file'),
                        ),
                        OutlinedButton(
                          onPressed:
                              keys.isEmpty
                                  ? null
                                  : () => _exportPublicKey(context, keys.first),
                          child: const Text('Export public'),
                        ),
                        OutlinedButton(
                          onPressed:
                              keys.isEmpty
                                  ? null
                                  : () => _showPrivateExportForm(
                                    context,
                                    keys.first,
                                  ),
                          child: const Text('Export private'),
                        ),
                        if (type == KeyRecordType.pgp && keys.isNotEmpty)
                          OutlinedButton(
                            onPressed:
                                () => _addPgpKeyToStore(context, keys.first),
                            child: const Text('Add to .gpg-id'),
                          ),
                        if (type == KeyRecordType.ssh)
                          OutlinedButton(
                            onPressed: () => _showGithubSettingsUrl(context),
                            child: const Text('GitHub settings'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _showCreateKeyForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final email = TextEditingController();
    final passphrase = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              type == KeyRecordType.pgp ? 'Create PGP key' : 'Create SSH key',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: passphrase,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _runKeyAction(
                      context,
                      () =>
                          type == KeyRecordType.pgp
                              ? keyRepository.generatePgpKey(
                                name: name.text,
                                email: email.text,
                                passphrase:
                                    passphrase.text.trim().isEmpty
                                        ? null
                                        : passphrase.text,
                              )
                              : keyRepository.generateSshKey(name.text),
                    ),
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  void _showImportKeyForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final keyText = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              type == KeyRecordType.pgp ? 'Import PGP key' : 'Import SSH key',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (type == KeyRecordType.ssh)
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                TextField(
                  controller: keyText,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Key text'),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _runKeyAction(context, () {
                      if (type == KeyRecordType.ssh) {
                        return keyRepository.importSshPrivateKeyText(
                          name: name.text,
                          privateKey: keyText.text,
                        );
                      }
                      if (keyText.text.contains('PGP PRIVATE KEY BLOCK')) {
                        return keyRepository.importPgpPrivateKeyText(
                          keyText.text,
                        );
                      }
                      return keyRepository.importPgpPublicKeyText(keyText.text);
                    }),
                child: const Text('Import'),
              ),
            ],
          ),
    );
  }

  void _showImportKeyFileForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final path = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              type == KeyRecordType.pgp
                  ? 'Import PGP key file'
                  : 'Import SSH key file',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (type == KeyRecordType.ssh)
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                TextField(
                  controller: path,
                  decoration: const InputDecoration(labelText: 'Path'),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _runKeyAction(
                      context,
                      () =>
                          type == KeyRecordType.pgp
                              ? keyRepository.importPgpPrivateKeyFile(path.text)
                              : keyRepository.importSshPrivateKeyFile(
                                name: name.text,
                                path: path.text,
                              ),
                    ),
                child: const Text('Import'),
              ),
            ],
          ),
    );
  }

  void _showPrivateExportForm(BuildContext context, KeyRecord key) {
    final confirmation = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Export private key'),
            content: TextField(
              controller: confirmation,
              decoration: const InputDecoration(labelText: 'Confirmation'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _showExportedText(
                      context,
                      () =>
                          key.type == KeyRecordType.pgp
                              ? keyRepository.exportPgpPrivateKey(
                                fingerprint: key.fingerprint,
                                confirmation: confirmation.text,
                              )
                              : keyRepository.exportSshPrivateKey(
                                name: key.name,
                                confirmation: confirmation.text,
                              ),
                    ),
                child: const Text('Export'),
              ),
            ],
          ),
    );
  }

  Future<void> _runKeyAction(
    BuildContext context,
    Future<KeyRecord> Function() action,
  ) async {
    try {
      final key = await action();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(key.name)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _exportPublicKey(BuildContext context, KeyRecord key) {
    _showExportedText(
      context,
      () =>
          key.type == KeyRecordType.pgp
              ? keyRepository.exportPgpPublicKey(key.fingerprint)
              : keyRepository.exportSshPublicKey(key.name),
    );
  }

  Future<void> _showExportedText(
    BuildContext context,
    Future<String> Function() action,
  ) async {
    try {
      final text = await action();
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Exported key'),
              content: SelectableText(text),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addPgpKeyToStore(BuildContext context, KeyRecord key) async {
    try {
      await keyRepository.addPgpKeyToSelectedStore(key.fingerprint);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(key.fingerprint)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showGithubSettingsUrl(BuildContext context) async {
    final url = await keyRepository.githubSshSettingsUri();
    if (!context.mounted) return;
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

  void _showPasswordStores(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Password stores',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(settingsRepository.lifecycle.onboardingState.label),
                    const SizedBox(height: 12),
                    for (final store in settingsRepository.stores)
                      Card(
                        child: ListTile(
                          title: Text(store.name),
                          subtitle: Text(
                            '${store.root}\n${store.issues.isEmpty ? 'Ready' : store.issues.join(', ')}',
                          ),
                          isThreeLine: true,
                          leading: Icon(
                            store.isDefault
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected:
                                (value) => _handleStoreMenu(
                                  context,
                                  action: value,
                                  root: store.root,
                                ),
                            itemBuilder:
                                (context) => const <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'select',
                                    child: Text('Select'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Text('Remove from app'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('Delete local store'),
                                  ),
                                ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: () => _showCreateStoreForm(context),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Create'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showImportStoreForm(context),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Import'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showCloneStoreForm(context),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Clone'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _handleStoreMenu(
    BuildContext context, {
    required String action,
    required String root,
  }) {
    switch (action) {
      case 'select':
        _runStoreAction(context, () => settingsRepository.selectStore(root));
        break;
      case 'remove':
        _runStoreAction(
          context,
          () => settingsRepository.removeStore(root: root),
        );
        break;
      case 'delete':
        _showDeleteStoreForm(context, root);
        break;
    }
  }

  void _showCreateStoreForm(BuildContext context) {
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
          () => settingsRepository.createLocalStore(
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

  void _showImportStoreForm(BuildContext context) {
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
          () => settingsRepository.importLocalStore(
            root: root.text,
            setDefault: true,
          ),
    );
  }

  void _showCloneStoreForm(BuildContext context) {
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
          () => settingsRepository.cloneStore(
            remoteUrl: remote.text,
            root: root.text,
            setDefault: true,
          ),
    );
  }

  void _showDeleteStoreForm(BuildContext context, String root) {
    final confirmation = TextEditingController();
    _showStoreForm(
      context: context,
      title: 'Delete local store',
      fields: <Widget>[
        Text(root),
        TextField(
          controller: confirmation,
          decoration: const InputDecoration(
            labelText: 'Type full path to confirm',
          ),
        ),
      ],
      submitLabel: 'Delete',
      onSubmit:
          () => settingsRepository.deleteLocalStore(
            root: root,
            confirmation: confirmation.text,
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
                      await _runStoreAction(context, onSubmit);
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

  Future<void> _runStoreAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
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
  }

  void _showGitArgs(BuildContext context) {
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
                    'Advanced git args',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only enter arguments after git. Shell syntax is not accepted.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Text(
                        'git',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(hintText: 'status'),
                          controller: TextEditingController(text: 'status'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {},
                    child: const SizedBox(
                      width: double.infinity,
                      child: Center(child: Text('Run selected command')),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF64748B),
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
