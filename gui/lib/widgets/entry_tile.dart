import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../app/pars_theme.dart';
import '../l10n/l10n.dart';
import '../models/password_entry.dart';
import 'app_section.dart';

// Rows are designed to sit inside a single grouped container rather than as
// detached cards, so this widget intentionally paints no border or radius of
// its own and lets the surrounding section own the shape and the metrics.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onCopy,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final PasswordEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onCopy;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle =
        entry.isDirectory
            ? context.l10n.entryCount(entry.childCount)
            : entry.parentPath;
    final subtitleStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle();

    return ParsSectionRow(
      leading: _EntryLeading(entry: entry),
      title: entry.displayName,
      subtitle: subtitle,
      // Store paths are machine data and are easier to compare in monospace;
      // the directory child count is ordinary prose and stays in the body face.
      subtitleStyle:
          entry.isDirectory ? subtitleStyle : ParsTheme.mono(subtitleStyle),
      selected: selected,
      onTap:
          selectionMode && !entry.isDirectory
              ? () => onSelectedChanged?.call(!selected)
              : onTap,
      onLongPress: entry.isDirectory ? null : onLongPress,
      trailing:
          selectionMode && !entry.isDirectory
              ? Checkbox(
                value: selected,
                onChanged: (value) => onSelectedChanged?.call(value ?? false),
              )
              : entry.isDirectory
              ? Padding(
                padding: const EdgeInsets.only(right: ParsSpacing.sm),
                child: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
              : IconButton(
                tooltip: context.l10n.copyPassword,
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
              ),
    );
  }
}

class _EntryLeading extends StatelessWidget {
  const _EntryLeading({required this.entry});

  final PasswordEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isDirectory) {
      return const ParsSectionRowIcon(icon: Icons.folder_outlined);
    }

    // A single shared accent turns a long list into undifferentiated noise, so
    // each entry keeps a stable slot derived from its own path.
    final palette = context.parsEntryPalette;
    final seed = entry.path.isEmpty ? entry.displayName : entry.path;
    return Container(
      width: ParsSizes.compactAvatar,
      height: ParsSizes.compactAvatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.fillFor(seed),
        borderRadius: BorderRadius.circular(ParsRadii.control),
      ),
      child: Text(
        entry.initials,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: palette.foregroundFor(seed)),
      ),
    );
  }
}
