import 'package:flutter/material.dart';

import '../../models/password_entry.dart';
import '../../services/demo_vault_repository.dart';
import '../../widgets/app_section.dart';
import '../../widgets/entry_tile.dart';
import 'entry_detail_sheet.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.repository});

  final DemoVaultRepository repository;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.repository.search(_query);
    final recent = entries.where((entry) => !entry.isDirectory).toList();
    final directories = entries.where((entry) => entry.isDirectory).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      child: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Vault',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  widget.repository.currentRepoName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  label: Text(widget.repository.gitStatus.label),
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by name or path',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          AppSection(
            title: _query.isEmpty ? 'Recent' : 'Search results',
            children: recent
                .map(
                  (entry) => EntryTile(
                    entry: entry,
                    onTap: () => _showEntry(entry),
                    onCopy: () => _showCopied(entry),
                  ),
                )
                .toList(),
          ),
          if (_query.isEmpty)
            AppSection(
              title: 'Browse',
              children: directories
                  .map(
                    (entry) => EntryTile(
                      entry: entry,
                      onTap: () {},
                      onCopy: () {},
                    ),
                  )
                  .toList(),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _showEntry(PasswordEntry entry) {
    if (entry.isDirectory) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => EntryDetailSheet(entry: entry),
    );
  }

  void _showCopied(PasswordEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${entry.displayName} password')),
    );
  }
}
