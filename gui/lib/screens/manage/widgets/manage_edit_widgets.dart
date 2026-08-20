part of '../manage_screen.dart';

class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({
    required this.entries,
    required this.canCommit,
    required this.onReadEntry,
    required this.onSaveRawNotes,
    required this.onReplacePassword,
    this.title,
    this.showEntryPicker = true,
  });

  final List<PasswordEntry> entries;
  final bool canCommit;
  final String? title;
  final bool showEntryPicker;
  final _ReadEntryForEdit onReadEntry;
  final _SaveEditedEntrySubmit onSaveRawNotes;
  final _ReplaceEntryPasswordSubmit onReplacePassword;

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
      final secret = await widget.onReadEntry(entry);
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
          _error = _manageErrorMessage(context, error);
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
      return widget.onSaveRawNotes(entry, _password, _fields, _notes, _commit);
    });
  }

  Future<void> _replacePasswordLine() async {
    final entry = _entry;
    if (entry == null) {
      return;
    }
    await _submit(() async {
      return widget.onReplacePassword(entry, _password, _commit);
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
          _error = _manageErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return _operationSheet(
        context: context,
        title: widget.title ?? context.l10n.editEntries,
        children: <Widget>[Text(context.l10n.noEntriesToEdit)],
      );
    }
    final entry = _entry ?? widget.entries.first;
    return _operationSheet(
      context: context,
      title: widget.title ?? context.l10n.editEntries,
      children: <Widget>[
        if (widget.showEntryPicker)
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
          )
        else
          Text(context.l10n.pathValue(entry.path)),
        if (_loading) ...const <Widget>[
          SizedBox(height: 16),
          LinearProgressIndicator(),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('password-${entry.path}-$_password'),
            initialValue: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: context.l10n.password),
            onChanged: (value) => _password = value,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('notes-${entry.path}-$_notes'),
            initialValue: _notes,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: context.l10n.rawNotes),
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
                  label: context.l10n.saveEditedEntry,
                  onPressed: _saveRawNotes,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SubmitButton(
                  saving: _saving,
                  label: context.l10n.replaceFirstLine,
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
