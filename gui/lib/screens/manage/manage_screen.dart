import 'package:flutter/material.dart';

import '../../models/password_entry.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';

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
                subtitle: 'Remove one entry after full-path confirmation.',
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
    var path = '';
    var noSymbols = false;
    var overwrite = false;
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await widget.repository.generateEntry(
                  path: path.trim(),
                  length: 24,
                  noSymbols: noSymbols,
                  overwrite: overwrite,
                );
                final committed = await _commitEntryResult(
                  result,
                  commit,
                  'Generate password ${path.trim()}',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Generate and save',
              children: <Widget>[
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Entry path',
                    hintText: 'work/example',
                  ),
                  onChanged: (value) => path = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: noSymbols,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => noSymbols = value ?? false),
                  title: const Text('No symbols'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: overwrite,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => overwrite = value ?? false),
                  title: const Text('Overwrite if entry exists'),
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Save generated password',
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
    );
    _showEntryResult(result);
  }

  Future<void> _showSaveExistingSheet() async {
    var path = '';
    var password = '';
    var notes = '';
    var overwrite = false;
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await widget.repository.saveEntry(
                  path: path.trim(),
                  content: _manualEntryContent(password, notes),
                  overwrite: overwrite,
                );
                final committed = await _commitEntryResult(
                  result,
                  commit,
                  'Save password ${path.trim()}',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Save existing password',
              children: <Widget>[
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Entry path',
                    hintText: 'work/example',
                  ),
                  onChanged: (value) => path = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onChanged: (value) => password = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Raw notes',
                    hintText: 'username: alice',
                  ),
                  onChanged: (value) => notes = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: overwrite,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => overwrite = value ?? false),
                  title: const Text('Overwrite if entry exists'),
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Save password',
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
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
            repository: manageRepository,
            canCommit: _canCommit,
            commitResult: _commitEntryResult,
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

    var entry = _entries.first;
    var target = rename ? entry.path : '';
    var overwrite = false;
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final toPath =
                    rename
                        ? target.trim()
                        : _joinEntryPath(target, _basename(entry.path));
                final result = await manageRepository.moveEntry(
                  fromPath: entry.path,
                  toPath: toPath,
                  overwrite: overwrite,
                );
                final committed = await _commitEntryResult(
                  result.copyWith(action: rename ? 'Renamed' : 'Moved'),
                  commit,
                  '${rename ? 'Rename' : 'Move'} password ${entry.path}',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: rename ? 'Rename entry' : 'Move entry',
              children: <Widget>[
                _EntryPicker(
                  entries: _entries,
                  value: entry,
                  onChanged:
                      saving
                          ? null
                          : (value) => setSheetState(() {
                            entry = value;
                            if (rename) {
                              target = value.path;
                            }
                          }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('${rename ? 'rename' : 'move'}-${entry.path}'),
                  initialValue: target,
                  decoration: InputDecoration(
                    labelText: rename ? 'New entry path' : 'Destination folder',
                    hintText: rename ? 'work/example-new' : 'archive/work',
                  ),
                  onChanged: (value) => target = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: overwrite,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => overwrite = value ?? false),
                  title: const Text('Overwrite if target exists'),
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: rename ? 'Rename entry' : 'Move entry',
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
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

    var entry = _entries.first;
    var confirmation = '';
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<EntryOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (confirmation.trim() != entry.path) {
                setSheetState(() => errorText = 'Type full path to confirm.');
                return;
              }
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await manageRepository.deleteEntry(
                  path: entry.path,
                  recursive: entry.isDirectory,
                );
                final committed = await _commitEntryResult(
                  result,
                  commit,
                  'Delete password ${entry.path}',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Delete entry',
              children: <Widget>[
                _EntryPicker(
                  entries: _entries,
                  value: entry,
                  onChanged:
                      saving
                          ? null
                          : (value) => setSheetState(() {
                            entry = value;
                            confirmation = '';
                          }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('delete-${entry.path}'),
                  decoration: const InputDecoration(labelText: 'Full path'),
                  onChanged: (value) => confirmation = value,
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Delete entry',
                  onPressed: submit,
                  danger: true,
                ),
              ],
            );
          },
        );
      },
    );
    _showEntryResult(result);
  }

  Future<void> _showBatchMoveSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    var destination = '';
    var overwrite = false;
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await manageRepository!.batchMoveEntries(
                  entries: selected,
                  destinationDirectory: destination,
                  overwrite: overwrite,
                );
                final committed = await _commitBatchResult(
                  result,
                  commit,
                  'Move ${selected.length} passwords',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Batch move',
              children: <Widget>[
                _SelectedPreview(entries: selected),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Destination folder',
                    hintText: 'archive/work',
                  ),
                  onChanged: (value) => destination = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: overwrite,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => overwrite = value ?? false),
                  title: const Text('Overwrite if target exists'),
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Move selected',
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
    );
    _showBatchResult(result);
  }

  Future<void> _showBatchRenameSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    var prefix = '';
    var suffix = '';
    var overwrite = false;
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await manageRepository!.batchRenameEntries(
                  entries: selected,
                  prefix: prefix,
                  suffix: suffix,
                  overwrite: overwrite,
                );
                final committed = await _commitBatchResult(
                  result,
                  commit,
                  'Rename ${selected.length} passwords',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Batch rename',
              children: <Widget>[
                _SelectedPreview(entries: selected),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Prefix'),
                  onChanged: (value) => prefix = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Suffix'),
                  onChanged: (value) => suffix = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: overwrite,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => overwrite = value ?? false),
                  title: const Text('Overwrite if target exists'),
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Rename selected',
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
    );
    _showBatchResult(result);
  }

  Future<void> _showBatchDeleteSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    var confirmation = '';
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (confirmation != 'DELETE') {
                setSheetState(() => errorText = 'Type DELETE to confirm.');
                return;
              }
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await manageRepository!.batchDeleteEntries(
                  entries: selected,
                );
                final committed = await _commitBatchResult(
                  result,
                  commit,
                  'Delete ${selected.length} passwords',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Batch delete',
              children: <Widget>[
                _SelectedPreview(entries: selected),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Confirmation'),
                  onChanged: (value) => confirmation = value,
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Delete selected',
                  onPressed: submit,
                  danger: true,
                ),
              ],
            );
          },
        );
      },
    );
    _showBatchResult(result);
  }

  Future<void> _showBatchRegenerateSheet() async {
    final manageRepository = _manageRepository;
    final selected = _selectedEntries;
    if (!_ensureBatchReady(manageRepository, selected)) {
      return;
    }
    var noSymbols = false;
    var commit = false;
    var saving = false;
    String? errorText;

    final result = await showModalBottomSheet<BatchOperationResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final result = await manageRepository!.batchRegenerateEntries(
                  entries: selected,
                  length: 24,
                  noSymbols: noSymbols,
                );
                final committed = await _commitBatchResult(
                  result,
                  commit,
                  'Regenerate ${selected.length} passwords',
                );
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(committed);
                }
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    saving = false;
                    errorText = error.toString();
                  });
                }
              }
            }

            return _operationSheet(
              context: context,
              title: 'Regenerate selected',
              children: <Widget>[
                _SelectedPreview(entries: selected),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: noSymbols,
                  onChanged:
                      saving
                          ? null
                          : (value) =>
                              setSheetState(() => noSymbols = value ?? false),
                  title: const Text('No symbols'),
                ),
                _CommitCheckbox(
                  enabled: _canCommit && !saving,
                  value: commit,
                  onChanged:
                      (value) => setSheetState(() => commit = value ?? false),
                ),
                _ErrorText(errorText),
                _SubmitButton(
                  saving: saving,
                  label: 'Regenerate batch',
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
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

class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({
    required this.entries,
    required this.repository,
    required this.canCommit,
    required this.commitResult,
  });

  final List<PasswordEntry> entries;
  final ManageRepository repository;
  final bool canCommit;
  final Future<EntryOperationResult> Function(
    EntryOperationResult result,
    bool commit,
    String message,
  )
  commitResult;

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  PasswordEntry? _entry;
  List<ParsedSecretField> _fields = const <ParsedSecretField>[];
  String _password = '';
  String _notes = '';
  var _loading = false;
  var _saving = false;
  var _commit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entry = widget.entries.isEmpty ? null : widget.entries.first;
    if (_entry != null) {
      _loadEntry(_entry!);
    }
  }

  Future<void> _loadEntry(PasswordEntry entry) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final secret = await widget.repository.readEntry(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _fields = secret.fields;
        _password = secret.password;
        _notes = secret.rawNotes;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _saveRawNotes() async {
    final entry = _entry;
    if (entry == null) {
      return;
    }
    await _submit(() async {
      final result = await widget.repository.editEntry(
        path: entry.path,
        content: _entryContent(_password, _fields, _notes),
      );
      return widget.commitResult(
        result,
        _commit,
        'Edit password ${entry.path}',
      );
    });
  }

  Future<void> _replacePasswordLine() async {
    final entry = _entry;
    if (entry == null) {
      return;
    }
    await _submit(() async {
      final result = await widget.repository.replaceEntryPassword(
        entry: entry,
        password: _password,
      );
      return widget.commitResult(
        result,
        _commit,
        'Replace password ${entry.path}',
      );
    });
  }

  Future<void> _submit(Future<EntryOperationResult> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await action();
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return _operationSheet(
        context: context,
        title: 'Edit entries',
        children: const <Widget>[Text('No entries to edit.')],
      );
    }
    final entry = _entry ?? widget.entries.first;
    return _operationSheet(
      context: context,
      title: 'Edit entries',
      children: <Widget>[
        _EntryPicker(
          entries: widget.entries,
          value: entry,
          onChanged:
              _saving
                  ? null
                  : (value) {
                    setState(() => _entry = value);
                    _loadEntry(value);
                  },
        ),
        if (_loading) ...const <Widget>[
          SizedBox(height: 16),
          LinearProgressIndicator(),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('password-${entry.path}-$_password'),
            initialValue: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onChanged: (value) => _password = value,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('notes-${entry.path}-$_notes'),
            initialValue: _notes,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Raw notes'),
            onChanged: (value) => _notes = value,
          ),
          _CommitCheckbox(
            enabled: widget.canCommit && !_saving,
            value: _commit,
            onChanged: (value) => setState(() => _commit = value ?? false),
          ),
          _ErrorText(_error),
          Row(
            children: <Widget>[
              Expanded(
                child: _SubmitButton(
                  saving: _saving,
                  label: 'Save edited entry',
                  onPressed: _saveRawNotes,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SubmitButton(
                  saving: _saving,
                  label: 'Replace first line',
                  onPressed: _replacePasswordLine,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BatchSelectionPanel extends StatelessWidget {
  const _BatchSelectionPanel({
    required this.entries,
    required this.selectedPaths,
    required this.onChanged,
    required this.onMove,
    required this.onRename,
    required this.onDelete,
    required this.onRegenerate,
  });

  final List<PasswordEntry> entries;
  final Set<String> selectedPaths;
  final void Function(String path, bool selected) onChanged;
  final VoidCallback onMove;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'BATCH SELECTION',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onMove,
              icon: const Icon(Icons.drive_file_move_outlined),
              label: const Text('Move selected'),
            ),
            OutlinedButton.icon(
              onPressed: onRename,
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('Rename selected'),
            ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete selected'),
            ),
            OutlinedButton.icon(
              onPressed: onRegenerate,
              icon: const Icon(Icons.refresh),
              label: const Text('Regenerate batch'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const ListTile(title: Text('No entries available'))
        else
          ...entries.map(
            (entry) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selectedPaths.contains(entry.path),
              onChanged: (value) => onChanged(entry.path, value ?? false),
              title: Text(entry.displayName),
              subtitle: Text(entry.path),
            ),
          ),
      ],
    );
  }
}

class _SelectedPreview extends StatelessWidget {
  const _SelectedPreview({required this.entries});

  final List<PasswordEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(entry.path)),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _EntryPicker extends StatelessWidget {
  const _EntryPicker({
    required this.entries,
    required this.value,
    required this.onChanged,
  });

  final List<PasswordEntry> entries;
  final PasswordEntry value;
  final ValueChanged<PasswordEntry>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<PasswordEntry>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Entry'),
      items: entries
          .map(
            (entry) => DropdownMenuItem<PasswordEntry>(
              value: entry,
              child: Text(entry.path),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged == null ? null : (value) => onChanged!(value!),
    );
  }
}

class _CommitCheckbox extends StatelessWidget {
  const _CommitCheckbox({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool enabled;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: enabled && value,
      onChanged: enabled ? onChanged : null,
      title: const Text('Commit after operation'),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.saving,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final bool saving;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: double.infinity,
      child: Center(
        child:
            saving
                ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(label),
      ),
    );
    if (danger) {
      return FilledButton.tonal(
        onPressed: saving ? null : onPressed,
        style: FilledButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
        child: child,
      );
    }
    return FilledButton(onPressed: saving ? null : onPressed, child: child);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) {
      return const SizedBox(height: 12);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
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
    final color =
        isDanger
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

Widget _operationSheet({
  required BuildContext context,
  required String title,
  required List<Widget> children,
}) {
  return SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
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
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

String _manualEntryContent(String password, String notes) {
  final trimmedNotes = notes.trim();
  if (trimmedNotes.isEmpty) {
    return password;
  }
  return '$password\n$trimmedNotes';
}

String _entryContent(
  String password,
  List<ParsedSecretField> fields,
  String rawNotes,
) {
  final lines = <String>[password];
  for (final field in fields) {
    lines.add('${field.key}: ${field.value}');
  }
  final notes = rawNotes.trim();
  if (notes.isNotEmpty) {
    lines.add(notes);
  }
  return lines.join('\n');
}

String _basename(String path) {
  final index = path.lastIndexOf('/');
  return index == -1 ? path : path.substring(index + 1);
}

String _joinEntryPath(String parent, String child) {
  final trimmedParent = parent.trim();
  final trimmedChild = child.trim();
  if (trimmedParent.isEmpty) {
    return trimmedChild;
  }
  return '$trimmedParent/$trimmedChild';
}
