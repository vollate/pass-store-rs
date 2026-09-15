import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/l10n.dart';
import '../services/path_picker_service.dart';

Future<ManagedStoreConflictPolicy?> showManagedStoreConflictSheet(
  BuildContext context,
  ManagedStoreConflict conflict,
) {
  return showModalBottomSheet<ManagedStoreConflictPolicy>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ParsSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                localizations.managedStoreConflictTitle,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: ParsSpacing.xs),
              Text(
                localizations.managedStoreConflictDescription(storeName),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ParsSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      () => Navigator.of(
                        context,
                      ).pop(ManagedStoreConflictPolicy.replace),
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: Text(localizations.managedStoreReplaceLabel),
                ),
              ),
              const SizedBox(height: ParsSpacing.xs),
              Text(
                localizations.managedStoreReplaceDescription,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ParsSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(localizations.cancel),
                ),
              ),
            ],
          ),
        ),
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
