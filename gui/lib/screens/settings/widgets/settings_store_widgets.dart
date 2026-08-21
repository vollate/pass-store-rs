part of '../settings_screen.dart';

extension _SettingsScreenStoreSheets on SettingsScreen {
  AppManagedPathRepository? get _managedPaths {
    final repository = settingsRepository;
    if (repository is AppManagedPathRepository) {
      final managed = repository as AppManagedPathRepository;
      if (managed.usesAppManagedPaths) return managed;
    }
    return null;
  }

  void _showPasswordStore(BuildContext context) {
    showParsAdaptiveDetail<void>(
      context: context,
      builder:
          (surfaceContext) => _PasswordStoreSheetBody(
            store: settingsRepository.store,
            isAppManaged:
                (root) => _managedPaths?.isAppManagedStoreRoot(root) ?? false,
            onRemove: (store) {
              if (_managedPaths?.isAppManagedStoreRoot(store.root) ?? false) {
                _showDeleteStoreForm(surfaceContext, store.root);
              } else {
                _showDisconnectStoreDialog(surfaceContext, store.root);
              }
            },
          ),
    );
  }

  void _showDisconnectStoreDialog(BuildContext context, String root) {
    final confirmation = TextEditingController();
    final storeName = _storeNameFromRoot(root);
    _showStoreForm(
      context: context,
      title: context.l10n.disconnectStore,
      fields: <Widget>[
        SelectableText(root),
        TextField(
          controller: confirmation,
          decoration: InputDecoration(
            labelText: context.l10n.typeToConfirm(storeName),
          ),
        ),
      ],
      submitLabel: context.l10n.disconnectStore,
      canSubmit: () => confirmation.text == storeName,
      listenable: confirmation,
      onSubmit: () => settingsRepository.removeStore(root: root),
    );
  }

  void _showDeleteStoreForm(BuildContext context, String root) {
    final confirmation = TextEditingController();
    final storeName = _storeNameFromRoot(root);
    _showStoreForm(
      context: context,
      title: context.l10n.deleteLocalStore,
      fields: <Widget>[
        SelectableText(root),
        TextField(
          controller: confirmation,
          decoration: InputDecoration(
            labelText: context.l10n.typeToConfirm(storeName),
          ),
        ),
      ],
      submitLabel: context.l10n.delete,
      canSubmit: () => confirmation.text == storeName,
      listenable: confirmation,
      onSubmit:
          () => settingsRepository.deleteLocalStore(
            root: root,
            confirmation: confirmation.text,
          ),
    );
  }

  void _showStoreForm({
    required BuildContext context,
    required String title,
    required List<Widget> fields,
    required String submitLabel,
    required bool Function() canSubmit,
    required Listenable listenable,
    required Future<void> Function() onSubmit,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _StoreFormSheetBody(
            title: title,
            fields: fields,
            submitLabel: submitLabel,
            canSubmit: canSubmit,
            listenable: listenable,
            onSubmit: () => _runStoreAction(context, onSubmit),
          ),
    );
  }

  Future<void> _runStoreAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      await onStoreLifecycleChanged?.call();
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (context.mounted) {
        AppNotification.show(
          context,
          UiProblem.fromError(context.l10n, error).summary,
        );
      }
    }
  }
}

String _storeNameFromRoot(String root) {
  final normalized = root.trim().replaceAll(RegExp(r'[/\\]+$'), '');
  if (normalized.isEmpty) return root.trim();
  return normalized.split(RegExp(r'[/\\]')).last;
}

class _PasswordStoreSheetBody extends StatelessWidget {
  const _PasswordStoreSheetBody({
    required this.store,
    required this.isAppManaged,
    required this.onRemove,
  });

  final StoreStatus? store;
  final bool Function(String root) isAppManaged;
  final ValueChanged<StoreStatus> onRemove;

  @override
  Widget build(BuildContext context) {
    final current = store;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.passwordStore,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (current == null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_off_outlined),
                  title: Text(context.l10n.noPasswordStoreConfigured),
                  subtitle: Text(context.l10n.storeFirstSetupSubtitle),
                )
              else ...<Widget>[
                Card(
                  child: ListTile(
                    leading: Icon(
                      current.exists
                          ? Icons.folder_outlined
                          : Icons.folder_off_outlined,
                    ),
                    title: Text(current.name),
                    subtitle: Text(_storeState(context, current)),
                    trailing: Icon(
                      current.exists && !current.issues.contains('git_invalid')
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                    ),
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(context.l10n.details),
                  children: <Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.storeFolder),
                      subtitle: SelectableText(current.root),
                    ),
                    if (current.issues.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.storeIssues),
                        subtitle: Text(_repairSummary(context, current)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => onRemove(current),
                  icon: Icon(
                    isAppManaged(current.root)
                        ? Icons.delete_outline
                        : Icons.link_off,
                  ),
                  label: Text(
                    isAppManaged(current.root)
                        ? context.l10n.deleteAppCopy
                        : context.l10n.disconnectStore,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _storeState(BuildContext context, StoreStatus store) {
    if (!store.exists) return context.l10n.passwordStoreFolderNotFound;
    if (!store.hasGpgId) return context.l10n.missingGpgIdTitle;
    if (store.pgpKeyMissing) return context.l10n.requiredPgpKeyMissingTitle;
    if (store.gitMode == StoreGitMode.invalid) {
      return context.l10n.invalidGitMetadataTitle;
    }
    return context.l10n.configured;
  }

  String _repairSummary(BuildContext context, StoreStatus store) {
    if (!store.exists) return context.l10n.passwordStoreFolderNotFound;
    if (!store.hasGpgId) return context.l10n.missingGpgIdMessage;
    if (store.pgpKeyMissing) {
      return context.l10n.requiredPgpKeyMissingMessage(
        store.pgpRecipients.join(', '),
      );
    }
    if (store.gitMode == StoreGitMode.invalid) {
      return context.l10n.invalidGitMetadataMessage;
    }
    return context.l10n.configured;
  }
}

class _StoreFormSheetBody extends StatefulWidget {
  const _StoreFormSheetBody({
    required this.title,
    required this.fields,
    required this.submitLabel,
    required this.canSubmit,
    required this.listenable,
    required this.onSubmit,
  });

  final String title;
  final List<Widget> fields;
  final String submitLabel;
  final bool Function() canSubmit;
  final Listenable listenable;
  final Future<void> Function() onSubmit;

  @override
  State<_StoreFormSheetBody> createState() => _StoreFormSheetBodyState();
}

class _StoreFormSheetBodyState extends State<_StoreFormSheetBody> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...widget.fields,
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: widget.listenable,
                builder:
                    (context, _) => FilledButton(
                      onPressed:
                          _submitting || !widget.canSubmit()
                              ? null
                              : () async {
                                setState(() => _submitting = true);
                                try {
                                  await widget.onSubmit();
                                } finally {
                                  if (mounted) {
                                    setState(() => _submitting = false);
                                  }
                                }
                              },
                      child: SizedBox(
                        width: double.infinity,
                        child: Center(child: Text(widget.submitLabel)),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
