import '../models/password_entry.dart';
import 'app_localizations.dart';

String localizedEntryOperationSummary(
  AppLocalizations localizations,
  EntryOperationResult result,
) {
  return localizations.entryOperationSummary(
    _localizedAction(localizations, result.action),
    result.path,
    result.overwroteExisting ? localizations.entryOverwroteExisting : '',
    result.committed ? localizations.entryCommitted : '',
  );
}

String localizedBatchOperationSummary(
  AppLocalizations localizations,
  BatchOperationResult result,
) {
  final summary = localizations.batchOperationSummary(
    _localizedAction(localizations, result.action),
    result.affectedPaths.length,
    result.committed ? localizations.entryCommitted : '',
  );
  if (result.failures.isEmpty) return summary;
  return '$summary${localizations.batchFailureSuffix(result.failures.length)}';
}

String _localizedAction(AppLocalizations localizations, String action) {
  final normalized = action.trim().toLowerCase();
  if (normalized.startsWith('sav')) {
    return localizations.actionSaved;
  }
  if (normalized.startsWith('edit')) {
    return localizations.actionEdited;
  }
  if (normalized.startsWith('delet')) {
    return localizations.actionDeleted;
  }
  if (normalized.startsWith('mov')) {
    return localizations.actionMoved;
  }
  if (normalized.startsWith('renam')) {
    return localizations.actionRenamed;
  }
  if (normalized.startsWith('regenerat')) {
    return localizations.actionRegenerated;
  }
  if (normalized.startsWith('replac') || normalized.startsWith('updat')) {
    return localizations.actionUpdated;
  }
  return localizations.actionUpdated;
}
