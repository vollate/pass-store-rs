part of '../settings_screen.dart';

extension _SettingsScreenAutofillSheets on SettingsScreen {
  void _showAutofill(BuildContext context) {
    final repository = autofillRepository;
    showParsAdaptiveDetail<void>(
      context: context,
      builder:
          (context) => _AutofillSettingsSheetBody(
            repository: repository,
            entries: vaultRepository?.entries ?? const <PasswordEntry>[],
          ),
    );
  }
}

class _AutofillSettingsSheetBody extends StatefulWidget {
  const _AutofillSettingsSheetBody({
    required this.repository,
    required this.entries,
  });

  final AutofillRepository? repository;
  final List<PasswordEntry> entries;

  @override
  State<_AutofillSettingsSheetBody> createState() =>
      _AutofillSettingsSheetBodyState();
}

class _AutofillSettingsSheetBodyState
    extends State<_AutofillSettingsSheetBody> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final status = repository?.status;
    final kind =
        _busy
            ? AutofillStatusKind.busy
            : status?.kind ?? AutofillStatusKind.unavailable;
    final available = kind == AutofillStatusKind.ready;
    final indexedEntries = status?.indexedEntries ?? 0;
    final localizations = context.l10n;
    final summary = switch (kind) {
      AutofillStatusKind.ready => localizations.autofillReady,
      AutofillStatusKind.syncFailed => localizations.autofillSyncFailed,
      AutofillStatusKind.busy => localizations.autofillBusy,
      AutofillStatusKind.disabled => localizations.autofillDisabled,
      AutofillStatusKind.unavailable => localizations.autofillUnavailableState,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ParsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.systemAutofillTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ParsSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (kind) {
                AutofillStatusKind.ready => Icons.check_circle_outline,
                AutofillStatusKind.syncFailed => Icons.sync_problem_outlined,
                AutofillStatusKind.busy => Icons.sync,
                AutofillStatusKind.disabled => Icons.block_outlined,
                AutofillStatusKind.unavailable => Icons.info_outline,
              }),
              title: Text(summary),
              subtitle:
                  available
                      ? Text(
                        localizations.autofillIndexedEntries(indexedEntries),
                      )
                      : null,
            ),
            if (status?.message case final diagnostics?)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(localizations.diagnosticDetails),
                children: <Widget>[
                  SelectableText(diagnostics),
                  const SizedBox(height: ParsSpacing.sm),
                ],
              ),
            const SizedBox(height: ParsSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(localizations.useLoginAndUrlFieldsHint),
                const SizedBox(height: ParsSpacing.xs),
                FilledButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _confirmUseEncryptedFields(repository),
                  icon: const Icon(Icons.link_outlined),
                  label: Text(localizations.useLoginAndUrlFields),
                ),
                const SizedBox(height: ParsSpacing.md),
                Text(localizations.forgetLoginAndUrlFieldsHint),
                const SizedBox(height: ParsSpacing.xs),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _run(
                            repository.forgetEncryptedLoginAndUrls,
                            localizations.loginAndUrlFieldsForgotten,
                          ),
                  icon: const Icon(Icons.link_off_outlined),
                  label: Text(localizations.forgetLoginAndUrlFields),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUseEncryptedFields(AutofillRepository repository) async {
    final entries = widget.entries
        .where((entry) => !entry.isDirectory)
        .toList(growable: false);
    if (entries.isEmpty) {
      AppNotification.show(context, context.l10n.noEntriesToEnrich);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => ParsDialog(
            title: dialogContext.l10n.useLoginAndUrlFields,
            content: Text(
              dialogContext.l10n.confirmUseLoginAndUrlFields(entries.length),
            ),
            secondary: ParsDialogAction(
              label: dialogContext.l10n.cancel,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            primary: ParsDialogAction(
              label: dialogContext.l10n.useFields,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => repository.useEncryptedLoginAndUrls(entries),
      context.l10n.loginAndUrlFieldsUpdated,
    );
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      AppNotification.show(
        context,
        message,
        severity: AppNotificationSeverity.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
    }
  }
}
