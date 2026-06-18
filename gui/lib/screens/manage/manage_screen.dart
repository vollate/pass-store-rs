import 'package:flutter/material.dart';

import '../../services/demo_vault_repository.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key, required this.repository});

  final DemoVaultRepository repository;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(
            'Manage',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: <Widget>[
              Text(
                'Maintain passwords in batches or one at a time.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _ManageActionCard(
                title: 'Generate and save',
                subtitle: 'Create one or many entries with generated passwords.',
                icon: Icons.auto_fix_high,
                onTap: () => _showPreview(context, 'Generate and save'),
              ),
              _ManageActionCard(
                title: 'Save existing password',
                subtitle: 'Manual entry for credentials you already have.',
                icon: Icons.add_circle_outline,
                onTap: () => _showPreview(context, 'Save existing password'),
              ),
              _ManageActionCard(
                title: 'Edit entries',
                subtitle:
                    'Rename paths, move folders, replace password lines, and edit raw notes.',
                icon: Icons.edit_outlined,
                onTap: () => _showPreview(context, 'Edit entries'),
              ),
              _ManageActionCard(
                title: 'Batch delete',
                subtitle: 'Preview full paths before removing selected entries.',
                icon: Icons.delete_outline,
                isDanger: true,
                onTap: () => _showPreview(context, 'Batch delete'),
              ),
              _ManageActionCard(
                title: 'Regenerate selected',
                subtitle:
                    'Replace password lines while preserving parsed fields and raw notes.',
                icon: Icons.refresh,
                onTap: () => _showPreview(context, 'Regenerate selected'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPreview(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Preview affected paths before execution. Real password-store operations will be connected in a later phase.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(child: Text('Close preview')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ManageActionCard extends StatelessWidget {
  const _ManageActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDanger = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = isDanger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
