part of '../manage_screen.dart';

class _BatchMoveSheet extends StatefulWidget {
  const _BatchMoveSheet({
    required this.entries,
    required this.canCommit,
    required this.onSubmit,
  });

  final List<PasswordEntry> entries;
  final bool canCommit;
  final _BatchMoveSubmit onSubmit;

  @override
  State<_BatchMoveSheet> createState() => _BatchMoveSheetState();
}

class _BatchMoveSheetState extends State<_BatchMoveSheet> {
  var _destination = '';
  var _overwrite = false;
  var _commit = false;
  var _saving = false;
  String? _errorText;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(_destination, _overwrite, _commit);
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: 'Batch move',
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        const SizedBox(height: 12),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Destination folder',
            hintText: 'archive/work',
          ),
          onChanged: (value) => _destination = value,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _overwrite,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _overwrite = value ?? false),
          title: const Text('Overwrite if target exists'),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: 'Move selected',
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _BatchRenameSheet extends StatefulWidget {
  const _BatchRenameSheet({
    required this.entries,
    required this.canCommit,
    required this.onSubmit,
  });

  final List<PasswordEntry> entries;
  final bool canCommit;
  final _BatchRenameSubmit onSubmit;

  @override
  State<_BatchRenameSheet> createState() => _BatchRenameSheetState();
}

class _BatchRenameSheetState extends State<_BatchRenameSheet> {
  var _prefix = '';
  var _suffix = '';
  var _overwrite = false;
  var _commit = false;
  var _saving = false;
  String? _errorText;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(
        _prefix,
        _suffix,
        _overwrite,
        _commit,
      );
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: 'Batch rename',
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        const SizedBox(height: 12),
        TextFormField(
          decoration: const InputDecoration(labelText: 'Prefix'),
          onChanged: (value) => _prefix = value,
        ),
        const SizedBox(height: 12),
        TextFormField(
          decoration: const InputDecoration(labelText: 'Suffix'),
          onChanged: (value) => _suffix = value,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _overwrite,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _overwrite = value ?? false),
          title: const Text('Overwrite if target exists'),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: 'Rename selected',
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _BatchDeleteSheet extends StatefulWidget {
  const _BatchDeleteSheet({
    required this.entries,
    required this.canCommit,
    required this.onSubmit,
  });

  final List<PasswordEntry> entries;
  final bool canCommit;
  final _BatchDeleteSubmit onSubmit;

  @override
  State<_BatchDeleteSheet> createState() => _BatchDeleteSheetState();
}

class _BatchDeleteSheetState extends State<_BatchDeleteSheet> {
  var _confirmation = '';
  var _commit = false;
  var _saving = false;
  String? _errorText;

  Future<void> _submit() async {
    if (_confirmation != 'DELETE') {
      setState(() => _errorText = 'Type DELETE to confirm.');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(_commit);
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: 'Batch delete',
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        const SizedBox(height: 12),
        TextFormField(
          decoration: const InputDecoration(labelText: 'Confirmation'),
          onChanged: (value) => _confirmation = value,
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: 'Delete selected',
          onPressed: _submit,
          danger: true,
        ),
      ],
    );
  }
}

class _BatchRegenerateSheet extends StatefulWidget {
  const _BatchRegenerateSheet({
    required this.entries,
    required this.canCommit,
    required this.onSubmit,
  });

  final List<PasswordEntry> entries;
  final bool canCommit;
  final _BatchRegenerateSubmit onSubmit;

  @override
  State<_BatchRegenerateSheet> createState() => _BatchRegenerateSheetState();
}

class _BatchRegenerateSheetState extends State<_BatchRegenerateSheet> {
  var _noSymbols = false;
  var _commit = false;
  var _saving = false;
  String? _errorText;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(_noSymbols, _commit);
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: 'Regenerate selected',
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _noSymbols,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _noSymbols = value ?? false),
          title: const Text('No symbols'),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: 'Regenerate batch',
          onPressed: _submit,
        ),
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
