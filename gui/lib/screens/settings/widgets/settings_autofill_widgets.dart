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
      AutofillStatusKind.needsRebuild => localizations.autofillNeedsRebuild,
      AutofillStatusKind.busy => localizations.autofillBusy,
      AutofillStatusKind.disabled => localizations.autofillDisabled,
      AutofillStatusKind.unavailable => localizations.autofillUnavailableState,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (kind) {
                AutofillStatusKind.ready => Icons.check_circle_outline,
                AutofillStatusKind.needsRebuild => Icons.refresh,
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
                  const SizedBox(height: 12),
                ],
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _run(
                            () => repository.rebuildIndex(widget.entries),
                            localizations.autofillRebuiltSuccess,
                          ),
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.rebuildPaths),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _confirmAndEnrich(repository),
                  icon: const Icon(Icons.link_outlined),
                  label: Text(context.l10n.readUrlFields),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _run(
                            repository.clearWebsiteEnrichment,
                            localizations.autofillAliasesCleared,
                          ),
                  icon: const Icon(Icons.link_off_outlined),
                  label: Text(context.l10n.clearUrlAliases),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _confirmClear(repository),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(context.l10n.clearAll),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _run(
                            repository.openPlatformSettings,
                            localizations.openSystemPasswordSettings,
                          ),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(context.l10n.setup),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(AutofillRepository repository) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(context.l10n.clearAll),
            content: Text(context.l10n.clearAutofillConfirmation),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: Text(context.l10n.clearAll),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(repository.clearIndex, context.l10n.autofillDataCleared);
  }

  Future<void> _confirmAndEnrich(AutofillRepository repository) async {
    final entries = widget.entries
        .where((entry) => !entry.isDirectory)
        .toList(growable: false);
    if (entries.isEmpty) {
      AppNotification.show(context, context.l10n.noEntriesToEnrich);
      return;
    }
    final selected = <String>{};
    final selectedPaths = await showDialog<Set<String>>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: Text(dialogContext.l10n.readEncryptedUrlFieldsTitle),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          dialogContext.l10n.readEncryptedUrlFieldsDescription(
                            selected.length,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: <Widget>[
                              for (final entry in entries)
                                CheckboxListTile(
                                  value: selected.contains(entry.path),
                                  title: Text(entry.displayName),
                                  subtitle: Text(entry.path),
                                  onChanged:
                                      (value) => setDialogState(() {
                                        if (value ?? false) {
                                          selected.add(entry.path);
                                        } else {
                                          selected.remove(entry.path);
                                        }
                                      }),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(dialogContext.l10n.cancel),
                    ),
                    FilledButton(
                      onPressed:
                          selected.isEmpty
                              ? null
                              : () => Navigator.of(
                                dialogContext,
                              ).pop(Set<String>.of(selected)),
                      child: Text(dialogContext.l10n.readSelectedEntries),
                    ),
                  ],
                ),
          ),
    );
    if (selectedPaths == null || selectedPaths.isEmpty || !mounted) return;
    await _run(
      () => repository.enrichWebsites(selectedPaths.toList(growable: false)),
      context.l10n.autofillAliasesUpdated,
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
