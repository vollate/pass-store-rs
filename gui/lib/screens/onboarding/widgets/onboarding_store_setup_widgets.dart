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
  final _CreateLocalStoreSubmit onCreateLocalStore;
  final _ImportLocalStoreSubmit onImportLocalStore;
  final _CloneStoreSubmit onCloneStore;
  final Future<void> Function() onStoreChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final selectedStore = lifecycle.selectedStore;
    return ListView(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            selectedStore == null
                ? localizations.noPasswordStoreConfigured
                : localizations.passwordStoreFolderNotFound,
          ),
          subtitle: Text(selectedStore?.root ?? lifecycle.configPath),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _showCreateLocalStore(context),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(context.l10n.createLocalStore),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showImportLocalStore(context),
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(context.l10n.importLocalStore),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: hasSshKey ? () => _showCloneStore(context) : null,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(context.l10n.cloneGitStore),
        ),
        if (!hasSshKey)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(context.l10n.addSshBeforeClone),
          ),
      ],
    );
  }

  void _showCreateLocalStore(BuildContext context) {
    final name = TextEditingController(text: 'Personal');
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
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
            initializeGit: managedPaths == null,
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
        final importedRoot = await pathPickerService
            .importFolderToManagedStorage(
              destinationBaseDirectory: destinationBase,
              resolveConflict:
                  (conflict) =>
                      showManagedStoreConflictSheet(context, conflict),
            );
        if (importedRoot == null) {
          throw PathPickerException(localizations.storeImportCancelled);
        }
        await onImportLocalStore(importedRoot);
      },
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

  void _showCloneStore(BuildContext context) {
    final remote = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: context.l10n.cloneGitStore,
      submitLabel: context.l10n.cloneAction,
      canSubmit:
          () => hasSshKey && (managedPaths != null || selectedBase != null),
      onSubmit:
          hasSshKey
              ? () => onCloneStore(
                remoteUrl: remote.text,
                root:
                    managedPaths?.storeRootForRemote(remote.text) ??
                    joinFilesystemPath(
                      selectedBase!,
                      slugFromRemoteUrl(remote.text),
                    ),
              )
              : null,
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
    final selectedRoot = lifecycle.selectedStoreRoot;
    if (selectedRoot != null && selectedRoot.trim().isNotEmpty) {
      return parentDirectory(selectedRoot);
    }
    if (lifecycle.stores.isNotEmpty) {
      return parentDirectory(lifecycle.stores.first.root);
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
  });

  final String title;
  final String submitLabel;
  final bool Function() canSubmit;
  final List<Widget> Function(BuildContext, StateSetter) builder;
  final Future<void> Function()? onSubmit;
  final Future<void> Function() onStoreChanged;

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
      await widget.onStoreChanged();
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
