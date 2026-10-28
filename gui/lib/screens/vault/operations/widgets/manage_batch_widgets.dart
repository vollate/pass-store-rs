part of '../vault_operations.dart';

class _BatchRegenerateSheet extends StatefulWidget {
  const _BatchRegenerateSheet({
    required this.entries,
    required this.onSubmit,
    this.title,
    this.submitLabel,
  });

  final List<PasswordEntry> entries;
  final _BatchRegenerateSubmit onSubmit;
  final String? title;
  final String? submitLabel;

  @override
  State<_BatchRegenerateSheet> createState() => _BatchRegenerateSheetState();
}

class _BatchRegenerateSheetState extends State<_BatchRegenerateSheet> {
  var _noSymbols = false;
  var _saving = false;
  String? _errorText;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSubmit(_noSymbols);
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
      title: widget.title ?? context.l10n.regenerate,
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
        _ErrorText(_errorText),
        _SubmitButton(
          saving: _saving,
          label: widget.submitLabel ?? context.l10n.regenerate,
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
              padding: const EdgeInsets.only(bottom: ParsSpacing.xs),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.lock_outline, size: ParsSizes.iconTiny),
                  const SizedBox(width: ParsSpacing.xs),
                  Expanded(child: Text(entry.path)),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
