import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/l10n.dart';
import '../services/path_picker_service.dart';
import 'pars_action_group.dart';
import 'pars_adaptive_surface.dart';

Future<ManagedStoreConflictPolicy?> showManagedStoreConflictSheet(
  BuildContext context,
  ManagedStoreConflict conflict,
) {
  final sheetWidth = MediaQuery.sizeOf(
    context,
  ).width.clamp(0.0, ParsContentWidth.form);
  return showModalBottomSheet<ManagedStoreConflictPolicy>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    constraints: BoxConstraints(
      minWidth: sheetWidth,
      maxWidth: ParsContentWidth.form,
    ),
    builder: (context) => _ManagedStoreConflictSheet(conflict: conflict),
  );
}

class _ManagedStoreConflictSheet extends StatelessWidget {
  const _ManagedStoreConflictSheet({required this.conflict});

  final ManagedStoreConflict conflict;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final storeName = _storeNameFromPath(conflict.destinationPath);

    return ParsAdaptiveSurface(
      title: localizations.managedStoreConflictTitle,
      showClose: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            localizations.managedStoreConflictDescription(storeName),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ParsSpacing.xs),
          Text(
            localizations.managedStoreReplaceDescription,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ParsSpacing.lg),
          ParsButtonGrid(
            children: <Widget>[
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(localizations.cancel),
              ),
              FilledButton.icon(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).pop(ManagedStoreConflictPolicy.replace),
                icon: const Icon(Icons.folder_copy_outlined),
                label: Text(
                  localizations.managedStoreReplaceLabel,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _storeNameFromPath(String path) {
  final normalized = path.trim().replaceAll(RegExp(r'[/\\]+$'), '');
  if (normalized.isEmpty) {
    return path.trim();
  }
  return normalized.split(RegExp(r'[/\\]')).last;
}
