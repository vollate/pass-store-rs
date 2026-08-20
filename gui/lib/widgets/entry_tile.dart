import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/l10n.dart';
import '../models/password_entry.dart';

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onCopy,
    this.onFavorite,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final PasswordEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onCopy;
  final VoidCallback? onFavorite;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle =
        entry.isDirectory
            ? context.l10n.entryCount(entry.childCount)
            : entry.parentPath;
    return Semantics(
      button: true,
      selected: selected,
      label: '${entry.displayName}, $subtitle',
      child: Material(
        color:
            selected
                ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
                : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(ParsRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              selectionMode && !entry.isDirectory
                  ? () => onSelectedChanged?.call(!selected)
                  : onTap,
          onLongPress: entry.isDirectory ? null : onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ParsSizes.minimumTouchTarget + ParsSpacing.md,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ParsSpacing.sm,
                vertical: ParsSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  _EntryLeading(entry: entry),
                  const SizedBox(width: ParsSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: ParsSpacing.xxs),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ParsSpacing.xs),
                  if (selectionMode && !entry.isDirectory)
                    Checkbox(
                      value: selected,
                      onChanged:
                          (value) => onSelectedChanged?.call(value ?? false),
                    )
                  else ...<Widget>[
                    if (!entry.isDirectory && onFavorite != null)
                      IconButton(
                        tooltip:
                            entry.isFavorite
                                ? context.l10n.unfavorite
                                : context.l10n.favorite,
                        isSelected: entry.isFavorite,
                        onPressed: onFavorite,
                        icon: const Icon(Icons.star_border_outlined),
                        selectedIcon: const Icon(Icons.star),
                      ),
                    if (entry.isDirectory)
                      const Icon(Icons.chevron_right)
                    else
                      IconButton(
                        tooltip: context.l10n.copyPassword,
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy_outlined),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryLeading extends StatelessWidget {
  const _EntryLeading({required this.entry});

  final PasswordEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (entry.isDirectory) {
      return SizedBox.square(
        dimension: ParsSizes.compactAvatar,
        child: Icon(Icons.folder_outlined, color: colorScheme.primary),
      );
    }
    return CircleAvatar(
      radius: ParsSizes.compactAvatar / 2,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      child: Text(entry.initials),
    );
  }
}
