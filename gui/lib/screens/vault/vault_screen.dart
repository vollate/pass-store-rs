import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/security_repository.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';
import '../../widgets/app_section.dart';
import '../../widgets/entry_tile.dart';
import '../manage/manage_screen.dart';
import 'entry_detail_sheet.dart';

enum _EntryDetailAction { edit, regenerate, delete }

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    required this.vaultRepository,
    required this.gitRepository,
    this.keyRepository,
    this.securityRepository,
    this.keys = const <KeyRecord>[],
    this.onChooseKey,
    this.onOpenKeyManagement,
  });

  final VaultRepository vaultRepository;
  final GitRepository gitRepository;
  final KeyRepository? keyRepository;
  final SecurityRepository? securityRepository;
  final List<KeyRecord> keys;
  final VoidCallback? onChooseKey;
  final VoidCallback? onOpenKeyManagement;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _directoryPath;
  bool _isLoading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _refreshVault();
  }

  @override
  void didUpdateWidget(covariant VaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vaultRepository != widget.vaultRepository) {
      _refreshVault();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.vaultRepository.search(_query);
    final recent =
        _query.isEmpty
            ? widget.vaultRepository.recentEntries()
            : entries.where((entry) => !entry.isDirectory).toList();
    final browseEntries =
        _query.isEmpty
            ? widget.vaultRepository.browseEntries(_directoryPath)
            : const <PasswordEntry>[];

    return RefreshIndicator(
      onRefresh: _refreshVault,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Vault',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.vaultRepository.currentRepoName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  label: Text(widget.gitRepository.gitStatus.label),
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
                onChanged:
                    (value) => setState(() {
                      _query = value;
                      if (value.isNotEmpty) {
                        _directoryPath = null;
                      }
                    }),
              ),
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_loadError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(_loadError!),
                    trailing: TextButton(
                      onPressed: _refreshVault,
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              ),
            ),
          AppSection(
            title: _query.isEmpty ? 'Recent' : 'Search results',
            emptyLabel:
                _query.isEmpty
                    ? 'No recent entries yet.'
                    : 'No entries match this search.',
            children:
                recent
                    .map(
                      (entry) => EntryTile(
                        entry: entry,
                        onTap: () => _showEntry(entry),
                        onCopy: () => _copyPassword(entry),
                      ),
                    )
                    .toList(),
          ),
          if (_query.isEmpty)
            AppSection(
              title:
                  _directoryPath == null ? 'Browse' : 'Browse: $_directoryPath',
              emptyLabel:
                  _directoryPath == null
                      ? 'No entries in this store.'
                      : 'No entries in this folder.',
              children: <Widget>[
                if (_directoryPath != null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: _openParentDirectory,
                      leading: const Icon(Icons.arrow_upward),
                      title: const Text('Up'),
                      subtitle: Text(_directoryPath!),
                    ),
                  ),
                ...browseEntries.map(
                  (entry) => EntryTile(
                    entry: entry,
                    onTap:
                        entry.isDirectory
                            ? () => _openDirectory(entry)
                            : () => _showEntry(entry),
                    onCopy:
                        entry.isDirectory ? null : () => _copyPassword(entry),
                  ),
                ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Future<void> _refreshVault() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      await widget.vaultRepository.refresh();
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load vault: $error';
      });
    }
  }

  Future<void> _showEntry(PasswordEntry entry) async {
    if (entry.isDirectory) {
      return;
    }
    final manageRepository =
        widget.vaultRepository is ManageRepository
            ? widget.vaultRepository as ManageRepository
            : null;
    final action = await showModalBottomSheet<_EntryDetailAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder:
          (sheetContext) => EntryDetailSheet(
            entry: entry,
            repository: widget.vaultRepository,
            keyRepository: widget.keyRepository,
            securityRepository: widget.securityRepository,
            keys: widget.keys,
            onFavoriteChanged: () => setState(() {}),
            onEdit:
                manageRepository == null
                    ? null
                    : () =>
                        Navigator.of(sheetContext).pop(_EntryDetailAction.edit),
            onRegenerate:
                manageRepository == null
                    ? null
                    : () => Navigator.of(
                      sheetContext,
                    ).pop(_EntryDetailAction.regenerate),
            onDelete:
                manageRepository == null
                    ? null
                    : () => Navigator.of(
                      sheetContext,
                    ).pop(_EntryDetailAction.delete),
            onChooseKey: widget.onChooseKey,
            onOpenKeyManagement: widget.onOpenKeyManagement,
          ),
    );
    if (!mounted || action == null || manageRepository == null) {
      return;
    }

    switch (action) {
      case _EntryDetailAction.edit:
        final result = await showFocusedEditEntrySheet(
          context: context,
          entry: entry,
          repository: manageRepository,
        );
        _showEntryOperationResult(result);
        break;
      case _EntryDetailAction.regenerate:
        final result = await showFocusedRegenerateEntrySheet(
          context: context,
          entry: entry,
          repository: manageRepository,
        );
        _showBatchOperationResult(result);
        break;
      case _EntryDetailAction.delete:
        final result = await showFocusedDeleteEntrySheet(
          context: context,
          entry: entry,
          repository: manageRepository,
        );
        _showEntryOperationResult(result);
        break;
    }
  }

  void _showEntryOperationResult(EntryOperationResult? result) {
    if (!mounted || result == null) {
      return;
    }
    setState(() {});
    AppNotification.show(context, result.summary);
  }

  void _showBatchOperationResult(BatchOperationResult? result) {
    if (!mounted || result == null) {
      return;
    }
    setState(() {});
    final failure =
        result.failures.isEmpty
            ? ''
            : ': ${result.failures.first.path}: '
                '${result.failures.first.message}';
    AppNotification.show(context, '${result.summary}$failure');
  }

  void _openDirectory(PasswordEntry entry) {
    setState(() => _directoryPath = entry.path);
  }

  void _openParentDirectory() {
    final path = _directoryPath;
    if (path == null) {
      return;
    }
    final index = path.lastIndexOf('/');
    setState(() {
      _directoryPath = index == -1 ? null : path.substring(0, index);
    });
  }

  Future<void> _copyPassword(PasswordEntry entry) async {
    try {
      final password = await widget.vaultRepository.copyEntryPassword(entry);
      await Clipboard.setData(ClipboardData(text: password));
      if (!mounted) {
        return;
      }
      AppNotification.show(context, 'Copied ${entry.displayName} password');
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotification.show(context, 'Could not copy password: $error');
    }
  }
}
