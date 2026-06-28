part of '../manage_screen.dart';

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
