part of '../settings_screen.dart';

extension _SettingsScreenAutofillSheets on SettingsScreen {
  void _showAutofill(BuildContext context) {
    final repository = autofillRepository;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
    final available = status?.available ?? false;
    final indexedEntries = status?.indexedEntries ?? 0;
    final message = status?.message ?? 'Autofill bridge unavailable';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'System autofill',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                available ? Icons.check_circle_outline : Icons.info_outline,
              ),
              title: Text(available ? 'Ready' : 'Not indexed'),
              subtitle: Text(
                available ? '$indexedEntries entries indexed' : message,
              ),
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
                            'Path-based autofill data rebuilt without decrypting entries',
                          ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rebuild paths'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _confirmAndEnrich(repository),
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('Read URL fields'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _run(
                            repository.clearWebsiteEnrichment,
                            'Encrypted website aliases cleared',
                          ),
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('Clear URL aliases'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      repository == null || _busy
                          ? null
                          : () => _run(
                            repository.clearIndex,
                            'Autofill data cleared',
                          ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear all'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : () => AppNotification.show(
                            context,
                            'Open system password settings',
                          ),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Setup'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndEnrich(AutofillRepository repository) async {
    final paths = widget.entries
        .where((entry) => !entry.isDirectory)
        .map((entry) => entry.path)
        .toList(growable: false);
    if (paths.isEmpty) {
      AppNotification.show(context, 'There are no password entries to enrich.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Read encrypted URL fields?'),
            content: Text(
              'This optional action decrypts all ${paths.length} selected entries once and stores only normalized website aliases. Path-based Autofill does not require it.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Read selected entries'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => repository.enrichWebsites(paths),
      'Encrypted website aliases updated',
    );
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      AppNotification.show(context, message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppNotification.show(context, '$error');
    }
  }
}
