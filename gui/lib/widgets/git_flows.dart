import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/git_sync.dart';
import '../models/password_entry.dart';
import '../services/git_repository.dart';
import '../services/ui_problem.dart';
import 'app_notification.dart';
import 'pars_adaptive_surface.dart';
import 'pars_dialog.dart';

/// Runs [action], asking for a commit identity, HTTPS credentials, or an SSH
/// key passphrase when Git needs one, then retrying. Returns `null` when the
/// user dismisses a prompt.
Future<T?> runGitWithPrompts<T>(
  BuildContext context,
  GitOperationsRepository? git,
  Future<T> Function() action,
) async {
  const maxAttempts = 4;
  for (var attempt = 1; ; attempt += 1) {
    try {
      return await action();
    } on GitIdentityRequiredException {
      if (git == null || attempt >= maxAttempts || !context.mounted) rethrow;
      final saved = await showGitIdentitySheet(context, git);
      if (!saved) return null;
    } on GitAuthenticationRequiredException {
      if (git == null || attempt >= maxAttempts || !context.mounted) rethrow;
      final credentials = await showHttpsCredentialsSheet(context);
      if (credentials == null) return null;
      await git.rememberHttpsCredentials(credentials);
    } on GitSshPassphraseRequiredException {
      if (git == null || attempt >= maxAttempts || !context.mounted) rethrow;
      final passphrase = await showSshPassphraseSheet(context);
      if (passphrase == null) return null;
      await git.rememberSshPassphrase(
        passphrase.passphrase,
        persist: passphrase.remember,
      );
    }
    if (!context.mounted) return null;
  }
}

/// Pull-to-refresh and the Sync button share this: decide whether to commit,
/// sync, and report the outcome in one notification.
Future<GitSyncOutcome?> runGitSyncFlow(
  BuildContext context,
  GitOperationsRepository git,
) async {
  final bool commitPending;
  final changed = git.statusSummary?.changed ?? 0;
  if (git.preferences.commitEveryChange) {
    commitPending = true;
  } else if (changed > 0) {
    final choice = await showSyncCommitChoice(context, changed);
    if (choice == null) return null;
    commitPending = choice;
  } else {
    commitPending = false;
  }
  if (!context.mounted) return null;
  final outcome = await runGitWithPrompts(
    context,
    git,
    () => git.sync(commitPending: commitPending),
  );
  if (outcome == null || !context.mounted) return outcome;
  final l10n = context.l10n;
  AppNotification.show(
    context,
    gitSyncOutcomeMessage(l10n, outcome),
    severity:
        outcome.conflict != null || outcome.blockedByChanges
            ? AppNotificationSeverity.warning
            : AppNotificationSeverity.success,
  );
  return outcome;
}

/// The short word shown on the Vault badge and the Git settings status row.
String gitStatusLabel(AppLocalizations l10n, RepoGitStatus status) {
  return switch (status) {
    RepoGitStatus.disabled => l10n.gitOff,
    RepoGitStatus.clean => l10n.gitClean,
    RepoGitStatus.needPull => l10n.gitNeedPull,
    RepoGitStatus.uncommitted => l10n.gitUncommitted,
    RepoGitStatus.invalid => l10n.gitInvalid,
    RepoGitStatus.syncFailed => l10n.gitSyncFailed,
    RepoGitStatus.needPush => l10n.gitPushNeeded,
    RepoGitStatus.diverged => l10n.gitDiverged,
    RepoGitStatus.conflicted => l10n.gitConflicted,
  };
}

String gitSyncOutcomeMessage(AppLocalizations l10n, GitSyncOutcome outcome) {
  final conflict = outcome.conflict;
  if (conflict != null) {
    final branch = conflict.backupBranch;
    return branch == null
        ? l10n.gitConflictInProgressMessage
        : l10n.gitSyncConflictNotice(branch);
  }
  if (outcome.blockedByChanges) return l10n.gitSyncBlocked;
  if (outcome.pulled > 0 && outcome.pushed) {
    return l10n.gitSyncPulledAndPushed(outcome.pulled);
  }
  if (outcome.pulled > 0) return l10n.gitSyncPulled(outcome.pulled);
  if (outcome.pushed) return l10n.gitSyncPushed;
  return l10n.gitSyncUpToDate;
}

/// `true` to commit first, `false` to sync existing commits, `null` to cancel.
Future<bool?> showSyncCommitChoice(BuildContext context, int changed) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return ParsDialog(
        title: l10n.syncCommitQuestionTitle,
        content: Text(l10n.syncCommitQuestionMessage(changed)),
        showClose: true,
        secondary: ParsDialogAction(
          label: l10n.syncWithoutCommitting,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        primary: ParsDialogAction(
          label: l10n.commitAndSync,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      );
    },
  );
}

/// Opens the recovery dialog that matches the badge: conflict or divergence.
Future<void> showGitRecoveryDialog(
  BuildContext context,
  GitOperationsRepository git, {
  Future<void> Function()? onSync,
}) async {
  final conflict = git.lastConflict;
  if (git.gitStatus == RepoGitStatus.diverged && conflict == null) {
    final action = await showDialog<_RecoveryAction>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return ParsDialog(
          title: l10n.gitDivergedTitle,
          content: Text(l10n.gitDivergedMessage),
          showClose: true,
          secondary: ParsDialogAction(
            label: l10n.useRemote,
            onPressed:
                () => Navigator.of(dialogContext).pop(_RecoveryAction.reset),
          ),
          primary: ParsDialogAction(
            label: l10n.syncNow,
            onPressed:
                () => Navigator.of(dialogContext).pop(_RecoveryAction.sync),
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    if (action == _RecoveryAction.sync) {
      if (onSync != null) {
        await onSync();
      } else {
        await _reportingErrors(context, () => runGitSyncFlow(context, git));
      }
    } else {
      await runGitResetFlow(context, git);
    }
    return;
  }

  final backup = conflict?.backupBranch;
  final action = await showDialog<_RecoveryAction>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      final paths = conflict?.paths ?? const <String>[];
      final shown = paths.take(3).join(', ');
      final pathsLabel = paths.length > 3 ? '$shown…' : shown;
      return ParsDialog(
        title: l10n.gitConflictTitle,
        content: Text(
          backup == null
              ? l10n.gitConflictInProgressMessage
              : l10n.gitConflictMessage(pathsLabel, backup),
        ),
        showClose: true,
        destructive: true,
        secondary:
            backup == null
                ? null
                : ParsDialogAction(
                  label: l10n.pushBackup,
                  onPressed:
                      () => Navigator.of(
                        dialogContext,
                      ).pop(_RecoveryAction.pushBackup),
                ),
        primary: ParsDialogAction(
          label: l10n.useRemote,
          onPressed:
              () => Navigator.of(dialogContext).pop(_RecoveryAction.reset),
        ),
      );
    },
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _RecoveryAction.pushBackup:
      await _reportingErrors(context, () async {
        final result = await runGitWithPrompts(
          context,
          git,
          () => git.pushBackupBranch(backup!),
        );
        if (result != null && context.mounted) {
          AppNotification.show(
            context,
            context.l10n.backupPushed(backup!),
            severity: AppNotificationSeverity.success,
          );
        }
      });
    case _RecoveryAction.reset:
      await runGitResetFlow(context, git, confirm: false);
    case _RecoveryAction.sync:
      break;
  }
}

enum _RecoveryAction { sync, reset, pushBackup }

/// Asks a plain yes/no question, then resets to the upstream. Local work is
/// saved to a backup branch by the bridge before anything is discarded.
Future<void> runGitResetFlow(
  BuildContext context,
  GitOperationsRepository git, {
  bool confirm = true,
}) async {
  if (confirm) {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return ParsDialog(
          title: l10n.resetToRemoteTitle,
          content: Text(l10n.resetToRemoteMessage),
          destructive: true,
          secondary: ParsDialogAction(
            label: l10n.cancel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          primary: ParsDialogAction(
            label: l10n.resetToRemote,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        );
      },
    );
    if (approved != true || !context.mounted) return;
  }
  await _reportingErrors(context, () async {
    final outcome = await runGitWithPrompts(context, git, git.resetToUpstream);
    if (outcome == null || !context.mounted) return;
    final branch = outcome.backupBranch;
    AppNotification.show(
      context,
      branch == null
          ? context.l10n.resetToRemoteDone
          : context.l10n.resetToRemoteDoneWithBackup(branch),
      severity: AppNotificationSeverity.success,
    );
  });
}

Future<void> _reportingErrors(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    AppNotification.show(
      context,
      UiProblem.fromError(context.l10n, error).summary,
      severity: AppNotificationSeverity.error,
    );
  }
}

/// Returns whether an identity was saved.
Future<bool> showGitIdentitySheet(
  BuildContext context,
  GitOperationsRepository git,
) async {
  GitIdentity? current;
  try {
    current = await git.identity();
  } catch (_) {
    current = null;
  }
  if (!context.mounted) return false;
  final initial = current ?? git.suggestedIdentity();
  final saved = await showParsAdaptiveSurface<bool>(
    context: context,
    title: context.l10n.gitIdentityTitle,
    builder: (surfaceContext) => _GitIdentityForm(git: git, initial: initial),
  );
  return saved == true;
}

class _GitIdentityForm extends StatefulWidget {
  const _GitIdentityForm({required this.git, required this.initial});

  final GitOperationsRepository git;
  final GitIdentity? initial;

  @override
  State<_GitIdentityForm> createState() => _GitIdentityFormState();
}

class _GitIdentityFormState extends State<_GitIdentityForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.initial?.email ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || !email.contains('@') || email.contains(' ')) {
      setState(() => _error = context.l10n.gitIdentityInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.git.setIdentity(name: name, email: email);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = UiProblem.fromError(context.l10n, error).summary;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CredentialForm(
      fields: <Widget>[
        TextField(
          controller: _name,
          enabled: !_saving,
          autofocus: widget.initial == null,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l10n.gitIdentityName),
        ),
        TextField(
          controller: _email,
          enabled: !_saving,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: l10n.gitIdentityEmail),
        ),
      ],
      error: _error,
      saving: _saving,
      submitLabel: l10n.save,
      onSubmit: _save,
    );
  }
}

Future<HttpsCredentials?> showHttpsCredentialsSheet(BuildContext context) {
  return showParsAdaptiveSurface<HttpsCredentials>(
    context: context,
    title: context.l10n.httpsCredentialsTitle,
    builder: (surfaceContext) => const _HttpsCredentialsForm(),
  );
}

class _HttpsCredentialsForm extends StatefulWidget {
  const _HttpsCredentialsForm();

  @override
  State<_HttpsCredentialsForm> createState() => _HttpsCredentialsFormState();
}

class _HttpsCredentialsFormState extends State<_HttpsCredentialsForm> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _token = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final token = _token.text;
    if (username.isEmpty || token.isEmpty) return;
    Navigator.of(
      context,
    ).pop(HttpsCredentials(username: username, token: token));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CredentialForm(
      fields: <Widget>[
        TextField(
          controller: _username,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l10n.httpsUsername),
        ),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: l10n.httpsToken),
        ),
      ],
      saving: false,
      submitLabel: l10n.save,
      onSubmit: _submit,
    );
  }
}

Future<({String passphrase, bool remember})?> showSshPassphraseSheet(
  BuildContext context,
) {
  return showParsAdaptiveSurface<({String passphrase, bool remember})>(
    context: context,
    title: context.l10n.sshPassphraseTitle,
    builder: (surfaceContext) => const _SshPassphraseForm(),
  );
}

class _SshPassphraseForm extends StatefulWidget {
  const _SshPassphraseForm();

  @override
  State<_SshPassphraseForm> createState() => _SshPassphraseFormState();
}

class _SshPassphraseFormState extends State<_SshPassphraseForm> {
  final TextEditingController _passphrase = TextEditingController();
  bool _remember = false;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  void _submit() {
    final passphrase = _passphrase.text;
    if (passphrase.isEmpty) return;
    Navigator.of(context).pop((passphrase: passphrase, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CredentialForm(
      fields: <Widget>[
        TextField(
          controller: _passphrase,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: l10n.sshPassphraseField),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _remember,
          onChanged: (value) => setState(() => _remember = value ?? false),
          title: Text(l10n.rememberOnThisDevice),
        ),
      ],
      saving: false,
      submitLabel: l10n.continueAction,
      onSubmit: _submit,
    );
  }
}

/// Fields stacked with the standard gutter and one full-width submit button.
class _CredentialForm extends StatelessWidget {
  const _CredentialForm({
    required this.fields,
    required this.saving,
    required this.submitLabel,
    required this.onSubmit,
    this.error,
  });

  final List<Widget> fields;
  final bool saving;
  final String submitLabel;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final field in fields) ...<Widget>[
          field,
          const SizedBox(height: ParsSpacing.sm),
        ],
        if (error != null) ...<Widget>[
          Text(
            error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: ParsSpacing.sm),
        ],
        FilledButton(
          onPressed: saving ? null : onSubmit,
          child: Text(submitLabel),
        ),
      ],
    );
  }
}
