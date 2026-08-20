import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../l10n/operation_localizations.dart';
import '../../models/password_entry.dart';
import '../../services/ui_problem.dart';
import '../../services/vault_repository.dart';
import '../../widgets/pars_adaptive_surface.dart';

part 'widgets/manage_operation_typedefs.dart';
part 'widgets/manage_single_entry_widgets.dart';
part 'widgets/manage_batch_widgets.dart';
part 'widgets/manage_edit_widgets.dart';
part 'widgets/manage_shared_widgets.dart';

Future<EntryOperationResult?> showFocusedEditEntrySheet({
  required BuildContext context,
  required PasswordEntry entry,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<EntryOperationResult>(
    context: context,
    builder:
        (context) => _EditEntrySheet(
          entries: <PasswordEntry>[entry],
          title: context.l10n.editEntries,
          showEntryPicker: false,
          canCommit: true,
          onReadEntry: repository.readEntry,
          onSaveRawNotes: (entry, password, fields, notes, commit) async {
            final localizations = context.l10n;
            final result = await repository.editEntry(
              path: entry.path,
              content: _entryContent(password, fields, notes),
            );
            return _commitEntryOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Edit password ${entry.path}',
            );
          },
          onReplacePassword: (entry, password, commit) async {
            final localizations = context.l10n;
            final result = await repository.replaceEntryPassword(
              entry: entry,
              password: password,
            );
            return _commitEntryOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Replace password ${entry.path}',
            );
          },
        ),
  );
}

Future<BatchOperationResult?> showFocusedRegenerateEntrySheet({
  required BuildContext context,
  required PasswordEntry entry,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<BatchOperationResult>(
    context: context,
    builder:
        (context) => _BatchRegenerateSheet(
          entries: <PasswordEntry>[entry],
          title: context.l10n.regenerate,
          submitLabel: context.l10n.regenerate,
          canCommit: true,
          onSubmit: (noSymbols, commit) async {
            final localizations = context.l10n;
            final result = await repository.batchRegenerateEntries(
              entries: <PasswordEntry>[entry],
              length: 24,
              noSymbols: noSymbols,
            );
            return _commitBatchOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Regenerate password ${entry.path}',
            );
          },
        ),
  );
}

Future<EntryOperationResult?> showFocusedDeleteEntrySheet({
  required BuildContext context,
  required PasswordEntry entry,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<EntryOperationResult>(
    context: context,
    builder:
        (context) => _DeleteEntrySheet(
          entries: <PasswordEntry>[entry],
          showEntryPicker: false,
          canCommit: true,
          onSubmit: (entry, commit) async {
            final localizations = context.l10n;
            final result = await repository.deleteEntry(
              path: entry.path,
              recursive: entry.isDirectory,
            );
            return _commitEntryOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Delete password ${entry.path}',
            );
          },
        ),
  );
}

Future<EntryOperationResult?> showCreateGeneratedEntrySurface({
  required BuildContext context,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<EntryOperationResult>(
    context: context,
    builder:
        (context) => _GenerateEntrySheet(
          canCommit: true,
          onSubmit: (path, noSymbols, overwrite, commit) async {
            final trimmedPath = path.trim();
            final localizations = context.l10n;
            final result = await repository.generateEntry(
              path: trimmedPath,
              length: 24,
              noSymbols: noSymbols,
              overwrite: overwrite,
            );
            return _commitEntryOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Generate password $trimmedPath',
            );
          },
        ),
  );
}

Future<EntryOperationResult?> showSaveExistingEntrySurface({
  required BuildContext context,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<EntryOperationResult>(
    context: context,
    builder:
        (context) => _SaveExistingEntrySheet(
          canCommit: true,
          onSubmit: (path, password, notes, overwrite, commit) async {
            final trimmedPath = path.trim();
            final localizations = context.l10n;
            final result = await repository.saveEntry(
              path: trimmedPath,
              content: _manualEntryContent(password, notes),
              overwrite: overwrite,
            );
            return _commitEntryOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Save password $trimmedPath',
            );
          },
        ),
  );
}

Future<EntryOperationResult?> showFocusedMoveOrRenameEntrySurface({
  required BuildContext context,
  required PasswordEntry entry,
  required ManageRepository repository,
  required bool rename,
}) {
  return showParsAdaptiveDetail<EntryOperationResult>(
    context: context,
    builder:
        (context) => _MoveOrRenameEntrySheet(
          entries: <PasswordEntry>[entry],
          rename: rename,
          canCommit: true,
          onSubmit: (selected, target, overwrite, commit) async {
            final toPath =
                rename
                    ? target.trim()
                    : _joinEntryPath(target, _basename(selected.path));
            final localizations = context.l10n;
            final result = await repository.moveEntry(
              fromPath: selected.path,
              toPath: toPath,
              overwrite: overwrite,
            );
            final mutationResult = result.copyWith(
              action: rename ? 'Renamed' : 'Moved',
            );
            return _commitEntryOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, mutationResult),
              ),
              repository: repository,
              result: mutationResult,
              commit: commit,
              message:
                  '${rename ? 'Rename' : 'Move'} password ${selected.path}',
            );
          },
        ),
  );
}

Future<BatchOperationResult?> showBatchMoveEntriesSurface({
  required BuildContext context,
  required List<PasswordEntry> entries,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<BatchOperationResult>(
    context: context,
    builder:
        (context) => _BatchMoveSheet(
          entries: entries,
          canCommit: true,
          onSubmit: (destination, overwrite, commit) async {
            final localizations = context.l10n;
            final result = await repository.batchMoveEntries(
              entries: entries,
              destinationDirectory: destination,
              overwrite: overwrite,
            );
            return _commitBatchOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Move ${entries.length} passwords',
            );
          },
        ),
  );
}

Future<BatchOperationResult?> showBatchRenameEntriesSurface({
  required BuildContext context,
  required List<PasswordEntry> entries,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<BatchOperationResult>(
    context: context,
    builder:
        (context) => _BatchRenameSheet(
          entries: entries,
          canCommit: true,
          onSubmit: (prefix, suffix, overwrite, commit) async {
            final localizations = context.l10n;
            final result = await repository.batchRenameEntries(
              entries: entries,
              prefix: prefix,
              suffix: suffix,
              overwrite: overwrite,
            );
            return _commitBatchOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Rename ${entries.length} passwords',
            );
          },
        ),
  );
}

Future<BatchOperationResult?> showBatchDeleteEntriesSurface({
  required BuildContext context,
  required List<PasswordEntry> entries,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<BatchOperationResult>(
    context: context,
    builder:
        (context) => _BatchDeleteSheet(
          entries: entries,
          canCommit: true,
          onSubmit: (commit) async {
            final localizations = context.l10n;
            final result = await repository.batchDeleteEntries(
              entries: entries,
            );
            return _commitBatchOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Delete ${entries.length} passwords',
            );
          },
        ),
  );
}

Future<BatchOperationResult?> showBatchRegenerateEntriesSurface({
  required BuildContext context,
  required List<PasswordEntry> entries,
  required ManageRepository repository,
}) {
  return showParsAdaptiveDetail<BatchOperationResult>(
    context: context,
    builder:
        (context) => _BatchRegenerateSheet(
          entries: entries,
          canCommit: true,
          onSubmit: (noSymbols, commit) async {
            final localizations = context.l10n;
            final result = await repository.batchRegenerateEntries(
              entries: entries,
              length: 24,
              noSymbols: noSymbols,
            );
            return _commitBatchOperation(
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              commit: commit,
              message: 'Regenerate ${entries.length} passwords',
            );
          },
        ),
  );
}

Future<EntryOperationResult> _commitEntryOperation({
  required String failureMessage,
  required ManageRepository repository,
  required EntryOperationResult result,
  required bool commit,
  required String message,
}) async {
  if (!commit) {
    return result;
  }
  try {
    final commitResult = await repository.commitChanges(message);
    if (!commitResult.success) {
      throw _PostMutationCommitException(failureMessage);
    }
  } on _PostMutationCommitException {
    rethrow;
  } catch (_) {
    throw _PostMutationCommitException(failureMessage);
  }
  return result.copyWith(committed: true);
}

Future<BatchOperationResult> _commitBatchOperation({
  required String failureMessage,
  required ManageRepository repository,
  required BatchOperationResult result,
  required bool commit,
  required String message,
}) async {
  if (!commit) {
    return result;
  }
  try {
    final commitResult = await repository.commitChanges(message);
    if (!commitResult.success) {
      throw _PostMutationCommitException(failureMessage);
    }
  } on _PostMutationCommitException {
    rethrow;
  } catch (_) {
    throw _PostMutationCommitException(failureMessage);
  }
  return result.copyWith(committed: true);
}

class _PostMutationCommitException implements Exception {
  const _PostMutationCommitException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _manageErrorMessage(BuildContext context, Object error) {
  if (error is _PostMutationCommitException) return error.message;
  return UiProblem.fromError(context.l10n, error).summary;
}
