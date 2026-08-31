part of '../vault_operations.dart';

class _GenerateEntrySheet extends StatefulWidget {
  const _GenerateEntrySheet({required this.canCommit, required this.onSubmit});

  final bool canCommit;
  final _GenerateEntrySubmit onSubmit;

  @override
  State<_GenerateEntrySheet> createState() => _GenerateEntrySheetState();
}

class _GenerateEntrySheetState extends State<_GenerateEntrySheet> {
  var _path = '';
  var _noSymbols = false;
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
        _path,
        _noSymbols,
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
      title: context.l10n.generateAndSave,
      children: <Widget>[
        TextFormField(
          decoration: InputDecoration(
            labelText: context.l10n.entryPath,
            hintText: 'work/example',
          ),
          onChanged: (value) => _path = value,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _noSymbols,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _noSymbols = value ?? false),
          title: Text(context.l10n.noSymbols),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _overwrite,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _overwrite = value ?? false),
          title: Text(context.l10n.overwriteEntry),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: context.l10n.saveGeneratedPassword,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _SaveExistingEntrySheet extends StatefulWidget {
  const _SaveExistingEntrySheet({
    required this.canCommit,
    required this.onSubmit,
  });

  final bool canCommit;
  final _SaveExistingEntrySubmit onSubmit;

  @override
  State<_SaveExistingEntrySheet> createState() =>
      _SaveExistingEntrySheetState();
}

class _SaveExistingEntrySheetState extends State<_SaveExistingEntrySheet> {
  var _path = '';
  var _password = '';
  var _notes = '';
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
        _path,
        _password,
        _notes,
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
      title: context.l10n.saveExistingPassword,
      children: <Widget>[
        TextFormField(
          decoration: InputDecoration(
            labelText: context.l10n.entryPath,
            hintText: 'work/example',
          ),
          onChanged: (value) => _path = value,
        ),
        const SizedBox(height: 12),
        TextFormField(
          obscureText: true,
          decoration: InputDecoration(labelText: context.l10n.password),
          onChanged: (value) => _password = value,
        ),
        const SizedBox(height: 12),
        TextFormField(
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.l10n.rawNotes,
            hintText: 'username: alice',
          ),
          onChanged: (value) => _notes = value,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _overwrite,
          onChanged:
              _saving
                  ? null
                  : (value) => setState(() => _overwrite = value ?? false),
          title: Text(context.l10n.overwriteEntry),
        ),
        _CommitCheckbox(
          enabled: widget.canCommit && !_saving,
          value: _commit,
          onChanged: (value) => setState(() => _commit = value ?? false),
        ),
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: context.l10n.savePassword,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _MoveOrRenameEntrySheet extends StatefulWidget {
  const _MoveOrRenameEntrySheet({
    required this.entry,
    required this.rename,
    required this.canCommit,
    required this.onSubmit,
  });

  final PasswordEntry entry;
  final bool rename;
  final bool canCommit;
  final _MoveOrRenameEntrySubmit onSubmit;

  @override
  State<_MoveOrRenameEntrySheet> createState() =>
      _MoveOrRenameEntrySheetState();
}

class _MoveOrRenameEntrySheetState extends State<_MoveOrRenameEntrySheet> {
  var _target = '';
  var _overwrite = false;
  var _commit = false;
  var _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _target = widget.rename ? widget.entry.path : '';
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(
        widget.entry,
        _target,
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
    final rename = widget.rename;
    return _operationSheet(
      context: context,
      title: rename ? context.l10n.renameEntry : context.l10n.moveEntry,
      children: <Widget>[
        Text(context.l10n.pathValue(widget.entry.path)),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('${rename ? 'rename' : 'move'}-${widget.entry.path}'),
          initialValue: _target,
          decoration: InputDecoration(
            labelText:
                rename
                    ? context.l10n.newEntryPath
                    : context.l10n.destinationFolder,
            hintText: rename ? 'work/example-new' : 'archive/work',
          ),
          onChanged: (value) => _target = value,
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
          label: rename ? context.l10n.renameEntry : context.l10n.moveEntry,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _DeleteEntrySheet extends StatefulWidget {
  const _DeleteEntrySheet({
    required this.entry,
    required this.canCommit,
    required this.onSubmit,
  });

  final PasswordEntry entry;
  final bool canCommit;
  final _DeleteEntrySubmit onSubmit;

  @override
  State<_DeleteEntrySheet> createState() => _DeleteEntrySheetState();
}

class _DeleteEntrySheetState extends State<_DeleteEntrySheet> {
  var _confirmation = '';
  var _commit = false;
  var _saving = false;
  String? _errorText;

  Future<void> _submit() async {
    final requiredText = _deleteConfirmationLabel(widget.entry);
    if (_confirmation.trim() != requiredText) {
      setState(() => _errorText = context.l10n.typeToConfirm(requiredText));
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(widget.entry, _commit);
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
      title: context.l10n.deleteEntry,
      children: <Widget>[
        Text(context.l10n.pathValue(widget.entry.path)),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('delete-${widget.entry.path}'),
          decoration: InputDecoration(
            labelText: context.l10n.typeToConfirm(
              _deleteConfirmationLabel(widget.entry),
            ),
          ),
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
          label: context.l10n.deleteEntry,
          onPressed: _submit,
          danger: true,
        ),
      ],
    );
  }
}

String _deleteConfirmationLabel(PasswordEntry entry) {
  final displayName = entry.displayName.trim();
  return displayName.isEmpty ? entry.path : displayName;
}
