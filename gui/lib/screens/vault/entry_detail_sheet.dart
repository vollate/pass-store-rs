import 'package:flutter/material.dart';

import '../../models/password_entry.dart';
import '../../services/pass_entry_parser.dart';

class EntryDetailSheet extends StatefulWidget {
  const EntryDetailSheet({
    super.key,
    required this.entry,
    this.onSecretCleared,
  });

  final PasswordEntry entry;
  final VoidCallback? onSecretCleared;

  @override
  State<EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends State<EntryDetailSheet> {
  bool _isRevealed = false;
  SecretContent? _content;

  @override
  void initState() {
    super.initState();
    _content = PassEntryParser.parse(widget.entry.encryptedContent);
  }

  @override
  void didUpdateWidget(covariant EntryDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.encryptedContent != widget.entry.encryptedContent) {
      _clearSecret();
      _content = PassEntryParser.parse(widget.entry.encryptedContent);
    }
  }

  @override
  void dispose() {
    _clearSecret();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    if (content == null) {
      return const SafeArea(child: SizedBox.shrink());
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    child: Text(widget.entry.initials),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.entry.displayName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          widget.entry.path,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _isRevealed ? content.password : '••••••••••••••',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(letterSpacing: _isRevealed ? 0 : 2),
                        ),
                      ),
                      IconButton(
                        tooltip: _isRevealed ? 'Hide' : 'Reveal',
                        onPressed:
                            () => setState(() => _isRevealed = !_isRevealed),
                        icon: Icon(
                          _isRevealed
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy password'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _isRevealed = !_isRevealed),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Reveal'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('QR code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              if (content.fields.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Fields',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final field in content.fields)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(field.label),
                    subtitle: Text(field.value),
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text('Copy'),
                    ),
                  ),
              ],
              if (content.rawNotes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Raw notes',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(content.rawNotes),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _clearSecret() {
    _isRevealed = false;
    _content = null;
    widget.onSecretCleared?.call();
  }
}
