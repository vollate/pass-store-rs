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
    showParsAdaptiveSurface<void>(
      context: context,
      title: context.l10n.passwordStore,
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
    showParsAdaptiveSurface<void>(
      context: context,
      title: title,
      builder:
          (context) => _StoreFormSheetBody(
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (current == null)
          AppSectionBox(
            padding: EdgeInsets.zero,
            children: <Widget>[
              ParsSectionRow(
                leading: const ParsSectionRowIcon(
                  icon: Icons.folder_off_outlined,
                ),
                title: context.l10n.noPasswordStoreConfigured,
                subtitle: context.l10n.storeFirstSetupSubtitle,
              ),
            ],
          )
        else ...<Widget>[
          AppSectionBox(
            padding: EdgeInsets.zero,
            children: <Widget>[
              ParsSectionRow(
                leading: ParsSectionRowIcon(
                  icon:
                      current.exists
                          ? Icons.folder_outlined
                          : Icons.folder_off_outlined,
                  color: colorScheme.primary,
                ),
                title: current.name,
                subtitle: _storeState(context, current),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: ParsSpacing.sm),
                  child: Icon(
                    current.exists && !current.issues.contains('git_invalid')
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color:
                        current.exists &&
                                !current.issues.contains('git_invalid')
                            ? context.parsColors.success
                            : context.parsColors.warning,
                  ),
                ),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(context.l10n.details),
            children: <Widget>[
              AppSectionBox(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  ParsSectionRow(
                    leading: const ParsSectionRowIcon(
                      icon: Icons.folder_open_outlined,
                    ),
                    title: context.l10n.storeFolder,
                    subtitle: current.root,
                    subtitleStyle: ParsTheme.mono(
                      Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ) ??
                          const TextStyle(),
                    ),
                  ),
                  if (current.issues.isNotEmpty)
                    ParsSectionRow(
                      leading: ParsSectionRowIcon(
                        icon: Icons.warning_amber_rounded,
                        color: context.parsColors.warning,
                      ),
                      title: context.l10n.storeIssues,
                      subtitle: _repairSummary(context, current),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: ParsSpacing.md),
          ParsButtonGrid(
            children: <Widget>[
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
          ),
        ],
      ],
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
    required this.fields,
    required this.submitLabel,
    required this.canSubmit,
    required this.listenable,
    required this.onSubmit,
  });

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...widget.fields,
        const SizedBox(height: ParsSpacing.md),
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
    );
  }
}
