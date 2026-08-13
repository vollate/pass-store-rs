part of '../settings_screen.dart';

extension _SettingsScreenStoreSheets on SettingsScreen {
  AppManagedPathRepository? get _managedPaths {
    final repository = settingsRepository;
    if (repository is AppManagedPathRepository) {
      final managedPaths = repository as AppManagedPathRepository;
      if (managedPaths.usesAppManagedPaths) {
        return managedPaths;
      }
    }
    return null;
  }

  void _showPasswordStores(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _PasswordStoresSheetBody(
            stores: settingsRepository.stores,
            isAppManagedStore:
                (root) => _managedPaths?.isAppManagedStoreRoot(root) ?? false,
            onStoreMenu:
                (action, root) =>
                    _handleStoreMenu(context, action: action, root: root),
            onCreate: () => _showCreateStoreForm(context),
            onImport: () => _showImportStoreForm(context),
            onClone: () => _showCloneStoreForm(context),
          ),
    );
  }

  void _handleStoreMenu(
    BuildContext context, {
    required String action,
    required String root,
  }) {
    switch (action) {
      case 'select':
        _runStoreAction(context, () => settingsRepository.selectStore(root));
        break;
      case 'remove':
        if (_managedPaths?.isAppManagedStoreRoot(root) ?? false) {
          _showDeleteStoreForm(context, root);
          break;
        }
        _runStoreAction(
          context,
          () => settingsRepository.removeStore(root: root),
        );
        break;
      case 'delete':
        _showDeleteStoreForm(context, root);
        break;
    }
  }

  void _showCreateStoreForm(BuildContext context) {
    final managedPaths = _managedPaths;
    final name = TextEditingController(text: 'Personal');
    final keys = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Create local store',
      submitLabel: 'Create',
      canSubmit: () => managedPaths != null || selectedBase != null,
      onSubmit:
          () => settingsRepository.createLocalStore(
            name: name.text,
            root:
                managedPaths?.storeRootForName(name.text) ??
                joinFilesystemPath(selectedBase!, slugPathSegment(name.text)),
            pgpKeys: keys.text
                .split(',')
                .map((key) => key.trim())
                .where((key) => key.isNotEmpty)
                .toList(growable: false),
            setDefault: true,
            initializeGit: managedPaths == null,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: 12),
            PathPickerRow(
              title: 'Store folder',
              path:
                  managedPaths?.storeRootForName(name.text) ??
                  joinFilesystemPath(
                    selectedBase ?? defaultBase,
                    slugPathSegment(name.text),
                  ),
              isSelected: selectedBase != null,
              onPressed:
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
            const SizedBox(height: 12),
            TextField(
              controller: keys,
              decoration: const InputDecoration(labelText: 'PGP keys'),
            ),
          ],
    );
  }

  void _showImportStoreForm(BuildContext context) {
    final managedPaths = _managedPaths;
    if (managedPaths != null) {
      _showManagedImportStoreForm(context, managedPaths);
      return;
    }
    final defaultBase = _defaultStoreBasePath();
    String? selectedRoot;
    _showPickerStoreForm(
      context: context,
      title: 'Import local store',
      submitLabel: 'Import',
      canSubmit: () => selectedRoot != null,
      onSubmit:
          () => settingsRepository.importLocalStore(
            root: selectedRoot!,
            setDefault: true,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            PathPickerRow(
              title: 'Store folder',
              path: selectedRoot ?? defaultBase,
              isSelected: selectedRoot != null,
              onPressed:
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

  void _showManagedImportStoreForm(
    BuildContext context,
    AppManagedPathRepository managedPaths,
  ) {
    final localizations = AppLocalizations.of(context);
    final destinationBase = parentDirectory(
      managedPaths.storeRootForName('store'),
    );
    _showPickerStoreForm(
      context: context,
      title: 'Import local store',
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
        await settingsRepository.importLocalStore(
          root: importedRoot,
          setDefault: true,
        );
        final passwordCount =
            vaultRepository?.entries
                .where((entry) => !entry.isDirectory)
                .length ??
            0;
        if (context.mounted) {
          AppNotification.show(
            context,
            localizations.storeImportSucceeded(passwordCount),
          );
        }
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

  void _showCloneStoreForm(BuildContext context) {
    final managedPaths = _managedPaths;
    final remote = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Clone Git store',
      submitLabel: 'Clone',
      canSubmit: () => managedPaths != null || selectedBase != null,
      onSubmit:
          () => settingsRepository.cloneStore(
            remoteUrl: remote.text,
            root:
                managedPaths?.storeRootForRemote(remote.text) ??
                joinFilesystemPath(
                  selectedBase!,
                  slugFromRemoteUrl(remote.text),
                ),
            setDefault: true,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            TextField(
              controller: remote,
              decoration: const InputDecoration(labelText: 'Remote URL'),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: 12),
            PathPickerRow(
              title: 'Store folder',
              path:
                  managedPaths?.storeRootForRemote(remote.text) ??
                  joinFilesystemPath(
                    selectedBase ?? defaultBase,
                    slugFromRemoteUrl(remote.text),
                  ),
              isSelected: selectedBase != null,
              onPressed:
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

  void _showPickerStoreForm({
    required BuildContext context,
    required String title,
    required String submitLabel,
    required bool Function() canSubmit,
    required List<Widget> Function(BuildContext, StateSetter) builder,
    required Future<void> Function() onSubmit,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => _PickerStoreFormSheetBody(
                  title: title,
                  submitLabel: submitLabel,
                  fields: builder(context, setSheetState),
                  canSubmit: canSubmit(),
                  onSubmit: () => _runStoreAction(context, onSubmit),
                ),
          ),
    );
  }

  void _showDeleteStoreForm(BuildContext context, String root) {
    final confirmation = TextEditingController();
    final storeName = _storeNameFromRoot(root);
    _showStoreForm(
      context: context,
      title: 'Delete local store',
      fields: <Widget>[
        Text(root),
        TextField(
          controller: confirmation,
          decoration: InputDecoration(labelText: 'Type $storeName to confirm'),
        ),
      ],
      submitLabel: 'Delete',
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
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (context.mounted) {
        final message =
            error is PathPickerException &&
                    error.code == 'store_import_no_passwords'
                ? AppLocalizations.of(context).storeImportNoPasswords
                : '$error';
        AppNotification.show(context, message);
      }
    }
  }
}

String _storeNameFromRoot(String root) {
  final normalized = root.trim().replaceAll(RegExp(r'[/\\]+$'), '');
  if (normalized.isEmpty) {
    return root.trim();
  }
  return normalized.split(RegExp(r'[/\\]')).last;
}

class _PasswordStoresSheetBody extends StatelessWidget {
  const _PasswordStoresSheetBody({
    required this.stores,
    required this.isAppManagedStore,
    required this.onStoreMenu,
    required this.onCreate,
    required this.onImport,
    required this.onClone,
  });

  final List<StoreStatus> stores;
  final bool Function(String root) isAppManagedStore;
  final void Function(String action, String root) onStoreMenu;
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Password stores',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (stores.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_off_outlined),
                  title: Text('No password stores'),
                  subtitle: Text('Create, import, or clone a store.'),
                ),
              for (final store in stores)
                Card(
                  child: ListTile(
                    title: Text(store.name),
                    subtitle: Text(
                      '${store.root}\n${store.exists ? localizations.storeAvailable : localizations.storeFolderNotFound}',
                    ),
                    isThreeLine: true,
                    leading: Icon(
                      store.isDefault
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => onStoreMenu(value, store.root),
                      itemBuilder:
                          (context) => <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'select',
                              child: Text('Select'),
                            ),
                            if (!isAppManagedStore(store.root))
                              const PopupMenuItem<String>(
                                value: 'remove',
                                child: Text('Remove from app'),
                              ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text(
                                isAppManagedStore(store.root)
                                    ? localizations.deleteAppCopy
                                    : 'Delete local store',
                              ),
                            ),
                          ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Create'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Import'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onClone,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Clone'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerStoreFormSheetBody extends StatefulWidget {
  const _PickerStoreFormSheetBody({
    required this.title,
    required this.submitLabel,
    required this.fields,
    required this.canSubmit,
    required this.onSubmit,
  });

  final String title;
  final String submitLabel;
  final List<Widget> fields;
  final bool canSubmit;
  final Future<void> Function() onSubmit;

  @override
  State<_PickerStoreFormSheetBody> createState() =>
      _PickerStoreFormSheetBodyState();
}

class _PickerStoreFormSheetBodyState extends State<_PickerStoreFormSheetBody> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
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
            FilledButton(
              onPressed: widget.canSubmit && !_isSubmitting ? _submit : null,
              child: SizedBox(
                width: double.infinity,
                child: Center(
                  child:
                      _isSubmitting
                          ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(localizations.storeActionInProgress),
                            ],
                          )
                          : Text(widget.submitLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _StoreFormSheetBody extends StatelessWidget {
  const _StoreFormSheetBody({
    required this.title,
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final List<Widget> fields;
  final String submitLabel;
  final Future<void> Function() onSubmit;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...fields,
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onSubmit,
              child: SizedBox(
                width: double.infinity,
                child: Center(child: Text(submitLabel)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
