part of '../vault_operations.dart';

class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({
    required this.entry,
    required this.canCommit,
    required this.onReadEntry,
    required this.onSaveRawNotes,
    required this.onReplacePassword,
    this.title,
  });

  final PasswordEntry entry;
  final bool canCommit;
  final String? title;
  final _ReadEntryForEdit onReadEntry;
  final _SaveEditedEntrySubmit onSaveRawNotes;
  final _ReplaceEntryPasswordSubmit onReplacePassword;

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
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
    _loadEntry(widget.entry);
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
    final entry = widget.entry;
    await _submit(() async {
      return widget.onSaveRawNotes(entry, _password, _fields, _notes, _commit);
    });
  }

  Future<void> _replacePasswordLine() async {
    final entry = widget.entry;
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
    final entry = widget.entry;
    return _operationSheet(
      context: context,
      title: widget.title ?? context.l10n.editEntries,
      children: <Widget>[
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
