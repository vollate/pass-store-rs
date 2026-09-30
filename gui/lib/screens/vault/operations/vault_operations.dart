import 'package:flutter/material.dart';

import '../../../app/pars_design_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/operation_localizations.dart';
import '../../../models/password_entry.dart';
import '../../../services/git_repository.dart';
import '../../../services/ui_problem.dart';
import '../../../services/vault_repository.dart';
import '../../../widgets/git_flows.dart';
import '../../../widgets/pars_adaptive_surface.dart';

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
          entry: entry,
          title: context.l10n.editEntries,
          onReadEntry: repository.readEntry,
          onSaveRawNotes: (entry, password, fields, notes) async {
            final localizations = context.l10n;
            final result = await repository.editEntry(
              path: entry.path,
              content: _entryContent(password, fields, notes),
            );
            if (!context.mounted) return result;
            return _commitEntryOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              message: 'Edit password ${entry.path}',
            );
          },
          onReplacePassword: (entry, password) async {
            final localizations = context.l10n;
            final result = await repository.replaceEntryPassword(
              entry: entry,
              password: password,
            );
            if (!context.mounted) return result;
            return _commitEntryOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          onSubmit: (noSymbols) async {
            final localizations = context.l10n;
            final result = await repository.batchRegenerateEntries(
              entries: <PasswordEntry>[entry],
              length: 24,
              noSymbols: noSymbols,
            );
            if (!context.mounted) return result;
            return _commitBatchOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          entry: entry,
          onSubmit: (entry) async {
            final localizations = context.l10n;
            final result = await repository.deleteEntry(
              path: entry.path,
              recursive: entry.isDirectory,
            );
            if (!context.mounted) return result;
            return _commitEntryOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          onSubmit: (path, noSymbols, overwrite) async {
            final trimmedPath = path.trim();
            final localizations = context.l10n;
            final result = await repository.generateEntry(
              path: trimmedPath,
              length: 24,
              noSymbols: noSymbols,
              overwrite: overwrite,
            );
            if (!context.mounted) return result;
            return _commitEntryOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          onSubmit: (path, password, notes, overwrite) async {
            final trimmedPath = path.trim();
            final localizations = context.l10n;
            final result = await repository.saveEntry(
              path: trimmedPath,
              content: _manualEntryContent(password, notes),
              overwrite: overwrite,
            );
            if (!context.mounted) return result;
            return _commitEntryOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          entry: entry,
          rename: rename,
          onSubmit: (selected, target, overwrite) async {
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
            if (!context.mounted) return mutationResult;
            return _commitEntryOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedEntryOperationSummary(localizations, mutationResult),
              ),
              repository: repository,
              result: mutationResult,
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
          onSubmit: (destination, overwrite) async {
            final localizations = context.l10n;
            final result = await repository.batchMoveEntries(
              entries: entries,
              destinationDirectory: destination,
              overwrite: overwrite,
            );
            if (!context.mounted) return result;
            return _commitBatchOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          onSubmit: (prefix, suffix, overwrite) async {
            final localizations = context.l10n;
            final result = await repository.batchRenameEntries(
              entries: entries,
              prefix: prefix,
              suffix: suffix,
              overwrite: overwrite,
            );
            if (!context.mounted) return result;
            return _commitBatchOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          onSubmit: () async {
            final localizations = context.l10n;
            final result = await repository.batchDeleteEntries(
              entries: entries,
            );
            if (!context.mounted) return result;
            return _commitBatchOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
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
          onSubmit: (noSymbols) async {
            final localizations = context.l10n;
            final result = await repository.batchRegenerateEntries(
              entries: entries,
              length: 24,
              noSymbols: noSymbols,
            );
            if (!context.mounted) return result;
            return _commitBatchOperation(
              context: context,
              failureMessage: localizations.postMutationCommitFailed(
                localizedBatchOperationSummary(localizations, result),
              ),
              repository: repository,
              result: result,
              message: 'Regenerate ${entries.length} passwords',
            );
          },
        ),
  );
}

Future<EntryOperationResult> _commitEntryOperation({
  required BuildContext context,
  required String failureMessage,
  required ManageRepository repository,
  required EntryOperationResult result,
  required String message,
}) async {
  final committed = await _commitAfterMutation(
    context: context,
    failureMessage: failureMessage,
    repository: repository,
    message: message,
  );
  return committed ? result.copyWith(committed: true) : result;
}

Future<BatchOperationResult> _commitBatchOperation({
  required BuildContext context,
  required String failureMessage,
  required ManageRepository repository,
  required BatchOperationResult result,
  required String message,
}) async {
  final committed = await _commitAfterMutation(
    context: context,
    failureMessage: failureMessage,
    repository: repository,
    message: message,
  );
  return committed ? result.copyWith(committed: true) : result;
}

/// Commits when the "Commit every change" setting is on. Returns `false` when
/// nothing was committed, including when the user dismissed the identity
/// prompt; the mutation itself is never rolled back.
Future<bool> _commitAfterMutation({
  required BuildContext context,
  required String failureMessage,
  required ManageRepository repository,
  required String message,
}) async {
  if (!repository.commitsEveryChange) return false;
  final git =
      repository is GitOperationsRepository
          ? repository as GitOperationsRepository
          : null;
  try {
    final commitResult = await runGitWithPrompts(
      context,
      git,
      () => repository.commitChanges(message),
    );
    if (commitResult == null) return false;
    if (!commitResult.success) {
      throw _PostMutationCommitException(failureMessage);
    }
  } on _PostMutationCommitException {
    rethrow;
  } catch (_) {
    throw _PostMutationCommitException(failureMessage);
  }
  return true;
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
