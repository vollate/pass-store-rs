part of '../vault_operations.dart';

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
          _errorText = _manageErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: context.l10n.batchMove,
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        const SizedBox(height: 12),
        TextFormField(
          decoration: InputDecoration(
            labelText: context.l10n.destinationFolder,
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
          title: Text(context.l10n.overwriteTarget),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: context.l10n.moveSelected,
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
          _errorText = _manageErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: context.l10n.batchRename,
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        const SizedBox(height: 12),
        TextFormField(
          decoration: InputDecoration(labelText: context.l10n.prefix),
          onChanged: (value) => _prefix = value,
        ),
        const SizedBox(height: 12),
        TextFormField(
          decoration: InputDecoration(labelText: context.l10n.suffix),
          onChanged: (value) => _suffix = value,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _overwrite,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _overwrite = value ?? false),
          title: Text(context.l10n.overwriteTarget),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: context.l10n.renameSelected,
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
      setState(() => _errorText = context.l10n.typeToConfirm('DELETE'));
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
          _errorText = _manageErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: context.l10n.batchDelete,
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        const SizedBox(height: 12),
        TextFormField(
          decoration: InputDecoration(labelText: context.l10n.confirmation),
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
          label: context.l10n.deleteSelected,
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
    this.title,
    this.submitLabel,
  });

  final List<PasswordEntry> entries;
  final bool canCommit;
  final _BatchRegenerateSubmit onSubmit;
  final String? title;
  final String? submitLabel;

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
          _errorText = _manageErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _operationSheet(
      context: context,
      title: widget.title ?? context.l10n.regenerateSelected,
      children: <Widget>[
        _SelectedPreview(entries: widget.entries),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _noSymbols,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _noSymbols = value ?? false),
          title: Text(context.l10n.noSymbols),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: widget.submitLabel ?? context.l10n.regenerateBatch,
          onPressed: _submit,
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
