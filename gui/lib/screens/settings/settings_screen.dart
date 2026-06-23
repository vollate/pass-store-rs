import 'package:flutter/material.dart';

import '../../models/key_record.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/settings_repository.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
  });

  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;

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
                    subtitle: 'Gesture fallback, biometric quick unlock',
                    icon: Icons.pattern,
                    onTap:
                        () => _showTextSheet(
                          context,
                          'Gesture lock and biometrics',
                        ),
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
                    onTap: () => _showTextSheet(context, 'Password stores'),
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
                          onPressed: () {},
                          child: const Text('Create'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Import'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Export public'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Export private'),
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
