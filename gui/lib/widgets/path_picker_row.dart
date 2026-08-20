import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class PathPickerRow extends StatelessWidget {
  const PathPickerRow({
    super.key,
    required this.title,
    required this.path,
    required this.isSelected,
    required this.onPressed,
  });

  final String title;
  final String path;
  final bool isSelected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pathPrefix =
        isSelected
            ? context.l10n.selectedPathPrefix
            : context.l10n.defaultPathPrefix;
    final actionLabel =
        isSelected ? context.l10n.changeAction : context.l10n.chooseAction;

    return Semantics(
      label: '$title, $pathPrefix: $path',
      button: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$pathPrefix: $path',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onPressed, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
