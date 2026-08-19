import 'package:flutter/material.dart';

import '../models/password_entry.dart';

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onCopy,
  });

  final PasswordEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          child: Text(entry.initials),
        ),
        title: Text(
          entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          entry.isDirectory ? '${entry.childCount} entries' : entry.parentPath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing:
            entry.isDirectory
                ? const Icon(Icons.chevron_right)
                : TextButton(onPressed: onCopy, child: const Text('Copy')),
      ),
    );
  }
}
