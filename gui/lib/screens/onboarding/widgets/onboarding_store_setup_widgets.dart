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
    Future<void> Function({required String remoteUrl, required String root});

class _StoreSetupActions extends StatelessWidget {
  const _StoreSetupActions({
    required this.lifecycle,
    required this.managedPaths,
    required this.selectedPgpFingerprint,
    required this.hasSshKey,
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
  final bool hasSshKey;
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
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: localizations.importLocalStore,
          child: FilledButton.icon(
            onPressed: () => _showImportLocalStore(context),
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(localizations.importLocalStore),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: localizations.cloneGitStore,
          child: FilledButton.tonalIcon(
            onPressed: () => _showCloneStore(context),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(localizations.cloneGitStore),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
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
            padding: const EdgeInsets.only(top: 8),
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

  Future<ManagedStoreGitDecision> _resolveMissingGitDecision(
    BuildContext context,
  ) async {
    return await showDialog<ManagedStoreGitDecision>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: Text(dialogContext.l10n.gitMetadataNotFoundTitle),
                content: Text(dialogContext.l10n.gitMetadataNotFoundMessage),
                actions: <Widget>[
                  TextButton(
                    onPressed:
                        () => Navigator.of(
                          dialogContext,
                        ).pop(ManagedStoreGitDecision.cancel),
                    child: Text(dialogContext.l10n.cancel),
                  ),
                  TextButton(
                    onPressed:
                        () => Navigator.of(
                          dialogContext,
                        ).pop(ManagedStoreGitDecision.continueWithoutGit),
                    child: Text(dialogContext.l10n.continueWithoutGit),
                  ),
                  FilledButton(
                    onPressed:
                        () => Navigator.of(
                          dialogContext,
                        ).pop(ManagedStoreGitDecision.initialize),
                    child: Text(dialogContext.l10n.initializeGit),
                  ),
                ],
              ),
        ) ??
        ManagedStoreGitDecision.cancel;
  }

  void _showCloneStore(BuildContext context) {
    final remote = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    var sshReady = hasSshKey;
    _showPickerStoreForm(
      context: context,
      title: context.l10n.cloneGitStore,
      submitLabel: context.l10n.cloneAction,
      canSubmit:
          () =>
              (!remoteUrlUsesSsh(remote.text) || sshReady) &&
              (managedPaths != null || selectedBase != null),
      onSubmit:
          () => onCloneStore(
            remoteUrl: remote.text,
            root:
                managedPaths?.storeRootForRemote(remote.text) ??
                joinFilesystemPath(
                  selectedBase!,
                  slugFromRemoteUrl(remote.text),
                ),
          ),
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
            ),
            if (remoteUrlUsesSsh(remote.text) && !sshReady) ...<Widget>[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(context.l10n.sshKeyRequiredForRemote),
                subtitle: Text(context.l10n.sshRequiredForThisClone),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final ready = await onGenerateSshKey();
                      setSheetState(() => sshReady = ready);
                    },
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.generateSshKey),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ready = await onImportSshKey();
                      setSheetState(() => sshReady = ready);
                    },
                    icon: const Icon(Icons.file_upload_outlined),
                    label: Text(context.l10n.importSshKey),
                  ),
                ],
              ),
            ],
          ],
    );
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
        const SizedBox(height: 12),
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
  });

  final TextEditingController remote;
  final AppManagedPathRepository? managedPaths;
  final String defaultBase;
  final String? selectedBase;
  final VoidCallback onRemoteChanged;
  final VoidCallback? onChooseBase;

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
        const SizedBox(height: 12),
        PathPickerRow(
          title: context.l10n.storeFolder,
          path:
              managedPaths?.storeRootForRemote(remote.text) ??
              joinFilesystemPath(
                selectedBase ?? defaultBase,
                slugFromRemoteUrl(remote.text),
              ),
          isSelected: selectedBase != null,
          onPressed: onChooseBase,
        ),
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
  String? _error;

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
              ...widget.builder(context, setState),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
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
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        _error =
            caught is PathPickerException &&
                    caught.code == 'store_import_no_passwords'
                ? context.l10n.storeImportNoPasswords
                : UiProblem.fromError(context.l10n, caught).summary;
        _isSubmitting = false;
      });
    }
  }
}
