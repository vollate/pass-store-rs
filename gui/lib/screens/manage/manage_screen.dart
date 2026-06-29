import 'package:flutter/material.dart';

import '../../models/password_entry.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';

part 'widgets/manage_operation_typedefs.dart';
part 'widgets/manage_single_entry_widgets.dart';
part 'widgets/manage_batch_widgets.dart';
part 'widgets/manage_edit_widgets.dart';
part 'widgets/manage_shared_widgets.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({
    super.key,
    required this.repository,
    this.manageRepository,
  });

  final VaultRepository repository;
  final ManageRepository? manageRepository;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  final Set<String> _selectedPaths = <String>{};

  List<PasswordEntry> get _entries => widget.repository.entries
      .where((entry) => !entry.isDirectory)
      .toList(growable: false);

  List<PasswordEntry> get _selectedEntries => _entries
      .where((entry) => _selectedPaths.contains(entry.path))
      .toList(growable: false);

  ManageRepository? get _manageRepository =>
      widget.manageRepository ??
      (widget.repository is ManageRepository
          ? widget.repository as ManageRepository
          : null);

  bool get _canCommit => _manageRepository != null;

  @override
  Widget build(BuildContext context) {
    final manageRepository = _manageRepository;
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
                subtitle:
                    'Create one or many entries with generated passwords.',
                icon: Icons.auto_fix_high,
                onTap: _showGenerateSheet,
              ),
              _ManageActionCard(
                title: 'Save existing password',
                subtitle: 'Manual entry for credentials you already have.',
                icon: Icons.add_circle_outline,
                onTap: _showSaveExistingSheet,
              ),
              _ManageActionCard(
                title: 'Batch delete',
                subtitle:
                    'Preview full paths before removing selected entries.',
                icon: Icons.delete_outline,
                isDanger: true,
                onTap:
                    manageRepository == null
                        ? _showManageUnavailable
                        : _showBatchDeleteSheet,
              ),
              _ManageActionCard(
                title: 'Regenerate selected',
                subtitle:
                    'Replace password lines while preserving parsed fields and raw notes.',
                icon: Icons.refresh,
                onTap:
                    manageRepository == null
                        ? _showManageUnavailable
                        : _showBatchRegenerateSheet,
              ),
              _ManageActionCard(
                title: 'Edit entries',
                subtitle:
                    'Update password lines and raw notes without changing the path.',
                icon: Icons.edit_outlined,
                onTap:
                    manageRepository == null
                        ? _showManageUnavailable
                        : _showEditSheet,
              ),
              _ManageActionCard(
                title: 'Move entry',
                subtitle: 'Move one entry into another folder.',
                icon: Icons.drive_file_move_outlined,
                onTap:
                    manageRepository == null
                        ? _showManageUnavailable
                        : () => _showMoveOrRenameSheet(rename: false),
              ),
              _ManageActionCard(
                title: 'Rename entry',
                subtitle: 'Change one entry path with overwrite handling.',
                icon: Icons.drive_file_rename_outline,
                onTap:
                    manageRepository == null
                        ? _showManageUnavailable
                        : () => _showMoveOrRenameSheet(rename: true),
              ),
              _ManageActionCard(
                title: 'Delete entry',
                subtitle: 'Remove one entry after name confirmation.',
                icon: Icons.delete_forever_outlined,
                isDanger: true,
                onTap:
                    manageRepository == null
                        ? _showManageUnavailable
                        : _showDeleteSheet,
              ),
              const SizedBox(height: 8),
              _BatchSelectionPanel(
                entries: _entries,
                selectedPaths: _selectedPaths,
                onChanged: (path, selected) {
                  setState(() {
                    if (selected) {
                      _selectedPaths.add(path);
                    } else {
                      _selectedPaths.remove(path);
                    }
                  });
                },
                onMove: _showBatchMoveSheet,
                onRename: _showBatchRenameSheet,
                onDelete: _showBatchDeleteSheet,
                onRegenerate: _showBatchRegenerateSheet,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showGenerateSheet() async {
    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _GenerateEntrySheet(
            canCommit: _canCommit,
            onSubmit: (path, noSymbols, overwrite, commit) async {
              final trimmedPath = path.trim();
              final result = await widget.repository.generateEntry(
                path: trimmedPath,
                length: 24,
                noSymbols: noSymbols,
                overwrite: overwrite,
              );
              return _commitEntryResult(
                result,
                commit,
                'Generate password $trimmedPath',
              );
            },
          ),
    );
    _showEntryResult(result);
  }

  Future<void> _showSaveExistingSheet() async {
    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _SaveExistingEntrySheet(
            canCommit: _canCommit,
            onSubmit: (path, password, notes, overwrite, commit) async {
              final trimmedPath = path.trim();
              final result = await widget.repository.saveEntry(
                path: trimmedPath,
                content: _manualEntryContent(password, notes),
                overwrite: overwrite,
              );
              return _commitEntryResult(
                result,
                commit,
                'Save password $trimmedPath',
              );
            },
          ),
    );
    _showEntryResult(result);
  }

  Future<void> _showEditSheet() async {
    final manageRepository = _manageRepository;
    if (manageRepository == null) {
      _showManageUnavailable();
      return;
    }
    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _EditEntrySheet(
            entries: _entries,
            canCommit: _canCommit,
            onReadEntry: manageRepository.readEntry,
            onSaveRawNotes: (entry, password, fields, notes, commit) async {
              final result = await manageRepository.editEntry(
                path: entry.path,
                content: _entryContent(password, fields, notes),
              );
              return _commitEntryResult(
                result,
                commit,
                'Edit password ${entry.path}',
              );
            },
            onReplacePassword: (entry, password, commit) async {
              final result = await manageRepository.replaceEntryPassword(
                entry: entry,
                password: password,
              );
              return _commitEntryResult(
                result,
                commit,
                'Replace password ${entry.path}',
              );
            },
          ),
    );
    _showEntryResult(result);
  }

  Future<void> _showMoveOrRenameSheet({required bool rename}) async {
    final manageRepository = _manageRepository;
    if (manageRepository == null) {
      _showManageUnavailable();
      return;
    }
    if (_entries.isEmpty) {
      _showError('No entries to manage.');
      return;
    }

    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _MoveOrRenameEntrySheet(
            entries: _entries,
            rename: rename,
            canCommit: _canCommit,
            onSubmit: (entry, target, overwrite, commit) async {
              final toPath =
                  rename
                      ? target.trim()
                      : _joinEntryPath(target, _basename(entry.path));
              final result = await manageRepository.moveEntry(
                fromPath: entry.path,
                toPath: toPath,
                overwrite: overwrite,
              );
              return _commitEntryResult(
                result.copyWith(action: rename ? 'Renamed' : 'Moved'),
                commit,
                '${rename ? 'Rename' : 'Move'} password ${entry.path}',
              );
            },
          ),
    );
    _showEntryResult(result);
  }

  Future<void> _showDeleteSheet() async {
    final manageRepository = _manageRepository;
    if (manageRepository == null) {
      _showManageUnavailable();
      return;
    }
    if (_entries.isEmpty) {
      _showError('No entries to manage.');
      return;
    }

    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _DeleteEntrySheet(
            entries: _entries,
            canCommit: _canCommit,
            onSubmit: (entry, commit) async {
              final result = await manageRepository.deleteEntry(
                path: entry.path,
                recursive: entry.isDirectory,
              );
              return _commitEntryResult(
                result,
                commit,
                'Delete password ${entry.path}',
              );
            },
          ),
    );
    _showEntryResult(result);
  }

  Future<void> _showBatchMoveSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _BatchMoveSheet(
            entries: selected,
            canCommit: _canCommit,
            onSubmit: (destination, overwrite, commit) async {
              final result = await manageRepository!.batchMoveEntries(
                entries: selected,
                destinationDirectory: destination,
                overwrite: overwrite,
              );
              return _commitBatchResult(
                result,
                commit,
                'Move ${selected.length} passwords',
              );
            },
          ),
    );
    _showBatchResult(result);
  }

  Future<void> _showBatchRenameSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _BatchRenameSheet(
            entries: selected,
            canCommit: _canCommit,
            onSubmit: (prefix, suffix, overwrite, commit) async {
              final result = await manageRepository!.batchRenameEntries(
                entries: selected,
                prefix: prefix,
                suffix: suffix,
                overwrite: overwrite,
              );
              return _commitBatchResult(
                result,
                commit,
                'Rename ${selected.length} passwords',
              );
            },
          ),
    );
    _showBatchResult(result);
  }

  Future<void> _showBatchDeleteSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _BatchDeleteSheet(
            entries: selected,
            canCommit: _canCommit,
            onSubmit: (commit) async {
              final result = await manageRepository!.batchDeleteEntries(
                entries: selected,
              );
              return _commitBatchResult(
                result,
                commit,
                'Delete ${selected.length} passwords',
              );
            },
          ),
    );
    _showBatchResult(result);
  }

  Future<void> _showBatchRegenerateSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _BatchRegenerateSheet(
            entries: selected,
            canCommit: _canCommit,
            onSubmit: (noSymbols, commit) async {
              final result = await manageRepository!.batchRegenerateEntries(
                entries: selected,
                length: 24,
                noSymbols: noSymbols,
              );
              return _commitBatchResult(
                result,
                commit,
                'Regenerate ${selected.length} passwords',
              );
            },
          ),
    );
    _showBatchResult(result);
  }

  bool _ensureBatchReady(
    ManageRepository? manageRepository,
    List<PasswordEntry> selected,
  ) {
    if (manageRepository == null) {
      _showManageUnavailable();
      return false;
    }
    if (selected.isEmpty) {
      _showError('Select at least one entry.');
      return false;
    }
    return true;
  }

  Future<EntryOperationResult> _commitEntryResult(
    EntryOperationResult result,
    bool commit,
    String message,
  ) async {
    final manageRepository = _manageRepository;
    if (!commit || manageRepository == null) {
      return result;
    }
    await manageRepository.commitChanges(message);
    return result.copyWith(committed: true);
  }

  Future<BatchOperationResult> _commitBatchResult(
    BatchOperationResult result,
    bool commit,
    String message,
  ) async {
    final manageRepository = _manageRepository;
    if (!commit || manageRepository == null) {
      return result;
    }
    await manageRepository.commitChanges(message);
    return result.copyWith(committed: true);
  }

  void _showEntryResult(EntryOperationResult? result) {
    if (result == null || !mounted) {
      return;
    }
    _setSummary(result.summary);
  }

  void _showBatchResult(BatchOperationResult? result) {
    if (result == null || !mounted) {
      return;
    }
    final failure =
        result.failures.isEmpty
            ? ''
            : ': ${result.failures.first.path}: ${result.failures.first.message}';
    _setSummary('${result.summary}$failure');
  }

  void _setSummary(String summary) {
    AppNotification.show(context, summary);
  }

  void _showError(String message) {
    AppNotification.show(context, message);
  }

  void _showManageUnavailable() {
    _showError('Manage operations are not available.');
  }
}
