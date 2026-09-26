part of '../onboarding_screen.dart';

typedef _CreateLocalStoreSubmit =
    Future<void> Function({
      required String name,
      required String root,
      required List<String> pgpKeys,
      required bool initializeGit,
    });

typedef _ImportLocalStoreSubmit = Future<void> Function(String root);

typedef _CloneStoreSubmit =
    Future<void> Function({
      required String remoteUrl,
      required String root,
      bool overwrite,
    });

class CloneOverwriteDeclined implements Exception {
  const CloneOverwriteDeclined();
}

class _StoreSetupActions extends StatelessWidget {
  const _StoreSetupActions({
    required this.lifecycle,
    required this.managedPaths,
    required this.selectedPgpFingerprint,
    required this.readSshKeys,
    required this.pathPickerService,
    required this.onCreateNeedsRecipient,
    required this.onGenerateSshKey,
    required this.onImportSshKey,
    required this.onCreateLocalStore,
    required this.onImportLocalStore,
    required this.onCloneStore,
    required this.onStoreChanged,
  });

  final StoreLifecycleSnapshot lifecycle;
  final AppManagedPathRepository? managedPaths;
  final String? selectedPgpFingerprint;
  final List<KeyRecord> Function() readSshKeys;
  final PathPickerService pathPickerService;
  final VoidCallback onCreateNeedsRecipient;
  final Future<bool> Function() onGenerateSshKey;
  final Future<bool> Function() onImportSshKey;
  final _CreateLocalStoreSubmit onCreateLocalStore;
  final _ImportLocalStoreSubmit onImportLocalStore;
  final _CloneStoreSubmit onCloneStore;
  final Future<void> Function() onStoreChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final store = lifecycle.store;
    return ListView(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.folder_open_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            store == null
                ? localizations.noPasswordStoreConfigured
                : localizations.passwordStoreFolderNotFound,
          ),
          subtitle: Text(
            store == null
                ? localizations.storeFirstSetupSubtitle
                : localizations.passwordStoreFolderNotFound,
          ),
        ),
        const SizedBox(height: ParsSpacing.sm),
        Semantics(
          button: true,
          label: localizations.importLocalStore,
          child: FilledButton.icon(
            onPressed: () => _showImportLocalStore(context),
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(localizations.importLocalStore),
          ),
        ),
        const SizedBox(height: ParsSpacing.xs),
        Semantics(
          button: true,
          label: localizations.cloneGitStore,
          child: FilledButton.tonalIcon(
            onPressed: () => _showCloneStore(context),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(localizations.cloneGitStore),
          ),
        ),
        const SizedBox(height: ParsSpacing.md),
        const Divider(),
        const SizedBox(height: ParsSpacing.xs),
        OutlinedButton.icon(
          onPressed:
              selectedPgpFingerprint == null
                  ? onCreateNeedsRecipient
                  : () => _showCreateLocalStore(context),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(localizations.createLocalStore),
        ),
        if (selectedPgpFingerprint == null)
          Padding(
            padding: const EdgeInsets.only(top: ParsSpacing.xs),
            child: Text(localizations.createStoreNeedsPgpKey),
          ),
      ],
    );
  }

  void _showCreateLocalStore(BuildContext context) {
    final name = TextEditingController(text: 'Personal');
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    var initializeGit = true;
    _showPickerStoreForm(
      context: context,
      title: context.l10n.createLocalStore,
      submitLabel: context.l10n.create,
      canSubmit: () => managedPaths != null || selectedBase != null,
      onSubmit:
          () => onCreateLocalStore(
            name: name.text,
            root:
                managedPaths?.storeRootForName(name.text) ??
                joinFilesystemPath(selectedBase!, slugPathSegment(name.text)),
            pgpKeys:
                selectedPgpFingerprint == null
                    ? const <String>[]
                    : <String>[selectedPgpFingerprint!],
            initializeGit: initializeGit,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            _CreateLocalStoreFields(
              name: name,
              managedPaths: managedPaths,
              defaultBase: defaultBase,
              selectedBase: selectedBase,
              onNameChanged: () => setSheetState(() {}),
              onChooseBase:
                  managedPaths == null
                      ? () => _chooseFolder(
                        sheetContext,
                        initialDirectory: defaultBase,
                        onSelected:
                            (path) => setSheetState(() {
                              selectedBase = path;
                            }),
                      )
                      : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: initializeGit,
              onChanged: (value) => setSheetState(() => initializeGit = value),
              title: Text(context.l10n.initializeGit),
              subtitle: Text(context.l10n.gitOptionalForLocalStore),
            ),
          ],
    );
  }

  void _showImportLocalStore(BuildContext context) {
    final managed = managedPaths;
    if (managed != null) {
      _showManagedImportLocalStore(context, managed);
      return;
    }
    final defaultBase = _defaultStoreBasePath();
    String? selectedRoot;
    _showPickerStoreForm(
      context: context,
      title: context.l10n.importLocalStore,
      submitLabel: context.l10n.importAction,
      canSubmit: () => selectedRoot != null,
      onSubmit: () => onImportLocalStore(selectedRoot!),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            _ImportLocalStoreFields(
              defaultBase: defaultBase,
              selectedRoot: selectedRoot,
              onChooseRoot:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedRoot = path;
                        }),
                  ),
            ),
          ],
    );
  }

  void _showManagedImportLocalStore(
    BuildContext context,
    AppManagedPathRepository managed,
  ) {
    final localizations = context.l10n;
    final destinationBase = parentDirectory(managed.storeRootForName('store'));
    _showPickerStoreForm(
      context: context,
      title: localizations.importLocalStore,
      submitLabel: localizations.chooseFolderAndImport,
      canSubmit: () => true,
      onSubmit: () async {
        final transaction = await pathPickerService
            .importFolderToManagedStorage(
              destinationBaseDirectory: destinationBase,
              resolveConflict:
                  (conflict) =>
                      showManagedStoreConflictSheet(context, conflict),
              resolveMissingGit: (_) => _resolveMissingGitDecision(context),
              resolveProviderFault: () => _resolveStoreProviderFault(context),
            );
        if (transaction == null) {
          throw PathPickerException(localizations.storeImportCancelled);
        }
        await completeManagedStoreImport(
          transaction: transaction,
          register: onImportLocalStore,
          refresh: onStoreChanged,
        );
      },
      refreshHandledBySubmit: true,
      builder:
          (_, _) => <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(localizations.copyIntoAppStorage),
              subtitle: Text(localizations.copyIntoAppStorageDescription),
            ),
          ],
    );
  }

  Future<bool> _resolveStoreProviderFault(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => ParsDialog(
                title: dialogContext.l10n.storeImportDirectAccessTitle,
                content: Text(
                  dialogContext.l10n.storeImportDirectAccessMessage,
                ),
                secondary: ParsDialogAction(
                  label: dialogContext.l10n.cancel,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                primary: ParsDialogAction(
                  label: dialogContext.l10n.storeImportDirectAccessAction,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ),
        ) ??
        false;
  }

  Future<ManagedStoreGitDecision> _resolveMissingGitDecision(
    BuildContext context,
  ) async {
    return await showDialog<ManagedStoreGitDecision>(
          context: context,
          builder:
              (dialogContext) => ParsDialog(
                title: dialogContext.l10n.gitMetadataNotFoundTitle,
                content: Text(dialogContext.l10n.gitMetadataNotFoundMessage),
                showClose: true,
                secondary: ParsDialogAction(
                  label: dialogContext.l10n.continueWithoutGit,
                  onPressed:
                      () => Navigator.of(
                        dialogContext,
                      ).pop(ManagedStoreGitDecision.continueWithoutGit),
                ),
                primary: ParsDialogAction(
                  label: dialogContext.l10n.initializeGit,
                  onPressed:
                      () => Navigator.of(
                        dialogContext,
                      ).pop(ManagedStoreGitDecision.initialize),
                ),
              ),
        ) ??
        ManagedStoreGitDecision.cancel;
  }

  Future<bool> _confirmCloneOverwrite(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return ParsDialog(
          title: dialogContext.l10n.cloneTargetExistsTitle,
          content: Text(dialogContext.l10n.cloneTargetExistsMessage),
          destructive: true,
          secondary: ParsDialogAction(
            label: dialogContext.l10n.cancel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          primary: ParsDialogAction(
            label: dialogContext.l10n.replaceCloneTarget,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        );
      },
    ).then((value) => value ?? false);
  }

  Future<void> _showCloneStore(BuildContext context) async {
    final remote = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    var sshReady = _importedSshKeys(readSshKeys()).isNotEmpty;
    var selectedSshKey = await _initialSshKeyName();
    if (!context.mounted) return;
    _showPickerStoreForm(
      context: context,
      title: context.l10n.cloneGitStore,
      submitLabel: context.l10n.cloneAction,
      canSubmit:
          () =>
              (!remoteUrlUsesSsh(remote.text) ||
                  (sshReady && selectedSshKey != null)) &&
              (managedPaths != null || selectedBase != null),
      onSubmit: () async {
        final keyName = selectedSshKey;
        if (remoteUrlUsesSsh(remote.text) && keyName != null) {
          await saveSelectedSshKey(lifecycle.configPath, keyName);
        }
        final root =
            managedPaths?.storeRootForRemote(remote.text) ??
            joinFilesystemPath(selectedBase!, slugFromRemoteUrl(remote.text));
        try {
          await onCloneStore(remoteUrl: remote.text, root: root);
        } on StoreCloneTargetExists {
          if (!context.mounted) return;
          final replace = await _confirmCloneOverwrite(context);
          if (!replace) throw const CloneOverwriteDeclined();
          await onCloneStore(
            remoteUrl: remote.text,
            root: root,
            overwrite: true,
          );
        }
      },
      builder:
          (sheetContext, setSheetState) => <Widget>[
            _CloneStoreFields(
              remote: remote,
              managedPaths: managedPaths,
              defaultBase: defaultBase,
              selectedBase: selectedBase,
              onRemoteChanged: () => setSheetState(() {}),
              onChooseBase:
                  managedPaths == null
                      ? () => _chooseFolder(
                        sheetContext,
                        initialDirectory: defaultBase,
                        onSelected:
                            (path) => setSheetState(() {
                              selectedBase = path;
                            }),
                      )
                      : null,
              sshKeys: _importedSshKeys(readSshKeys()),
              selectedSshKey: selectedSshKey,
              onSelectSshKey:
                  (name) => setSheetState(() {
                    selectedSshKey = name;
                  }),
            ),
            if (remoteUrlUsesSsh(remote.text) && !sshReady) ...<Widget>[
              const SizedBox(height: ParsSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(context.l10n.sshKeyRequiredForRemote),
                subtitle: Text(context.l10n.sshRequiredForThisClone),
              ),
              ParsButtonGrid(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final ready = await onGenerateSshKey();
                      setSheetState(() {
                        sshReady = ready;
                        selectedSshKey = _selectedSshKeyAfterRefresh(
                          selectedSshKey,
                        );
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.generateAction),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ready = await onImportSshKey();
                      setSheetState(() {
                        sshReady = ready;
                        selectedSshKey = _selectedSshKeyAfterRefresh(
                          selectedSshKey,
                        );
                      });
                    },
                    icon: const Icon(Icons.file_upload_outlined),
                    label: Text(context.l10n.importAction),
                  ),
                ],
              ),
            ],
          ],
    );
  }

  List<KeyRecord> _importedSshKeys(List<KeyRecord> keys) => <KeyRecord>[
    for (final key in keys)
      if (key.type == KeyRecordType.ssh && key.hasPrivateKey) key,
  ];

  Future<String?> _initialSshKeyName() async {
    final keys = _importedSshKeys(readSshKeys());
    if (keys.isEmpty) return null;
    if (keys.length == 1) return keys.single.name;
    final saved = await loadSelectedSshKey(lifecycle.configPath);
    if (saved != null && keys.any((key) => key.name == saved)) return saved;
    return null;
  }

  String? _selectedSshKeyAfterRefresh(String? current) {
    final keys = _importedSshKeys(readSshKeys());
    if (keys.isEmpty) return null;
    if (current != null && keys.any((key) => key.name == current)) {
      return current;
    }
    if (keys.length == 1) return keys.single.name;
    return null;
  }

  Future<void> _chooseFolder(
    BuildContext context, {
    required String initialDirectory,
    required ValueChanged<String> onSelected,
  }) async {
    try {
      final path = await pathPickerService.pickFolder(
        initialDirectory: initialDirectory,
      );
      if (path == null) {
        return;
      }
      onSelected(path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(UiProblem.fromError(context.l10n, error).summary),
        ),
      );
    }
  }

  String _defaultStoreBasePath() {
    final selectedRoot = lifecycle.store?.root;
    if (selectedRoot != null && selectedRoot.trim().isNotEmpty) {
      return parentDirectory(selectedRoot);
    }
    if (lifecycle.store != null) {
      return parentDirectory(lifecycle.store!.root);
    }
    return parentDirectory(lifecycle.configPath);
  }

  void _showPickerStoreForm({
    required BuildContext context,
    required String title,
    required String submitLabel,
    required bool Function() canSubmit,
    required List<Widget> Function(BuildContext, StateSetter) builder,
    required Future<void> Function()? onSubmit,
    bool refreshHandledBySubmit = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _StorePickerFormSheet(
            title: title,
            submitLabel: submitLabel,
            canSubmit: canSubmit,
            builder: builder,
            onSubmit: onSubmit,
            onStoreChanged: onStoreChanged,
            refreshHandledBySubmit: refreshHandledBySubmit,
          ),
    );
  }
}

class _CreateLocalStoreFields extends StatelessWidget {
  const _CreateLocalStoreFields({
    required this.name,
    required this.managedPaths,
    required this.defaultBase,
    required this.selectedBase,
    required this.onNameChanged,
    required this.onChooseBase,
  });

  final TextEditingController name;
  final AppManagedPathRepository? managedPaths;
  final String defaultBase;
  final String? selectedBase;
  final VoidCallback onNameChanged;
  final VoidCallback? onChooseBase;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: context.l10n.nameField),
          onChanged: (_) => onNameChanged(),
        ),
        const SizedBox(height: ParsSpacing.sm),
        PathPickerRow(
          title: context.l10n.storeFolder,
          path:
              managedPaths?.storeRootForName(name.text) ??
              joinFilesystemPath(
                selectedBase ?? defaultBase,
                slugPathSegment(name.text),
              ),
          isSelected: selectedBase != null,
          onPressed: onChooseBase,
        ),
      ],
    );
  }
}

class _ImportLocalStoreFields extends StatelessWidget {
  const _ImportLocalStoreFields({
    required this.defaultBase,
    required this.selectedRoot,
    required this.onChooseRoot,
  });

  final String defaultBase;
  final String? selectedRoot;
  final VoidCallback onChooseRoot;

  @override
  Widget build(BuildContext context) {
    return PathPickerRow(
      title: context.l10n.storeFolder,
      path: selectedRoot ?? defaultBase,
      isSelected: selectedRoot != null,
      onPressed: onChooseRoot,
    );
  }
}

class _CloneStoreFields extends StatelessWidget {
  const _CloneStoreFields({
    required this.remote,
    required this.managedPaths,
    required this.defaultBase,
    required this.selectedBase,
    required this.onRemoteChanged,
    required this.onChooseBase,
    required this.sshKeys,
    required this.selectedSshKey,
    required this.onSelectSshKey,
  });

  final TextEditingController remote;
  final AppManagedPathRepository? managedPaths;
  final String defaultBase;
  final String? selectedBase;
  final VoidCallback onRemoteChanged;
  final VoidCallback? onChooseBase;
  final List<KeyRecord> sshKeys;
  final String? selectedSshKey;
  final ValueChanged<String> onSelectSshKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: remote,
          decoration: InputDecoration(labelText: context.l10n.remoteUrlField),
          onChanged: (_) => onRemoteChanged(),
        ),
        if (managedPaths == null) ...<Widget>[
          const SizedBox(height: ParsSpacing.sm),
          PathPickerRow(
            title: context.l10n.storeFolder,
            path: joinFilesystemPath(
              selectedBase ?? defaultBase,
              slugFromRemoteUrl(remote.text),
            ),
            isSelected: selectedBase != null,
            onPressed: onChooseBase,
          ),
        ],
        if (remoteUrlUsesSsh(remote.text) && sshKeys.isNotEmpty) ...<Widget>[
          const SizedBox(height: ParsSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.l10n.sshKeysTitle,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final key in sshKeys)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: key.name,
              groupValue: selectedSshKey,
              title: Text(key.name),
              onChanged: (value) {
                if (value != null) onSelectSshKey(value);
              },
            ),
        ],
      ],
    );
  }
}

class _StorePickerFormSheet extends StatefulWidget {
  const _StorePickerFormSheet({
    required this.title,
    required this.submitLabel,
    required this.canSubmit,
    required this.builder,
    required this.onSubmit,
    required this.onStoreChanged,
    required this.refreshHandledBySubmit,
  });

  final String title;
  final String submitLabel;
  final bool Function() canSubmit;
  final List<Widget> Function(BuildContext, StateSetter) builder;
  final Future<void> Function()? onSubmit;
  final Future<void> Function() onStoreChanged;
  final bool refreshHandledBySubmit;

  @override
  State<_StorePickerFormSheet> createState() => _StorePickerFormSheetState();
}

class _StorePickerFormSheetState extends State<_StorePickerFormSheet> {
  bool _isSubmitting = false;
  UiProblem? _error;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: ParsSpacing.lg,
          right: ParsSpacing.lg,
          top: ParsSpacing.lg,
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
              const SizedBox(height: ParsSpacing.sm),
              ...widget.builder(context, setState),
              if (_error != null) ...<Widget>[
                const SizedBox(height: ParsSpacing.sm),
                FailureNotice(problem: _error!),
              ],
              const SizedBox(height: ParsSpacing.md),
              FilledButton(
                onPressed:
                    _isSubmitting ||
                            !widget.canSubmit() ||
                            widget.onSubmit == null
                        ? null
                        : _submit,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(child: Text(widget.submitLabel)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit!();
      if (!widget.refreshHandledBySubmit) {
        await widget.onStoreChanged();
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on CloneOverwriteDeclined {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        _error = switch (caught) {
          PathPickerException(:final code)
              when code == 'store_import_no_passwords' =>
            UiProblem(summary: context.l10n.storeImportNoPasswords),
          PathPickerException(:final code)
              when code == 'store_import_provider_unlistable' =>
            UiProblem(summary: context.l10n.storeImportProviderUnlistable),
          _ => UiProblem.fromError(context.l10n, caught),
        };
        _isSubmitting = false;
      });
    }
  }
}
