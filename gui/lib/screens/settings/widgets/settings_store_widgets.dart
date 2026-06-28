part of '../settings_screen.dart';

extension _SettingsScreenStoreSheets on SettingsScreen {
  void _showPasswordStores(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _PasswordStoresSheetBody(
            lifecycle: settingsRepository.lifecycle,
            stores: settingsRepository.stores,
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
    final name = TextEditingController(text: 'Personal');
    final keys = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Create local store',
      submitLabel: 'Create',
      canSubmit: () => selectedBase != null,
      onSubmit:
          () => settingsRepository.createLocalStore(
            name: name.text,
            root: joinFilesystemPath(selectedBase!, slugPathSegment(name.text)),
            pgpKeys: keys.text
                .split(',')
                .map((key) => key.trim())
                .where((key) => key.isNotEmpty)
                .toList(growable: false),
            setDefault: true,
            initializeGit: true,
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
              path: joinFilesystemPath(
                selectedBase ?? defaultBase,
                slugPathSegment(name.text),
              ),
              isSelected: selectedBase != null,
              onPressed:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedBase = path;
                        }),
                  ),
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

  void _showCloneStoreForm(BuildContext context) {
    final remote = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Clone Git store',
      submitLabel: 'Clone',
      canSubmit: () => selectedBase != null,
      onSubmit:
          () => settingsRepository.cloneStore(
            remoteUrl: remote.text,
            root: joinFilesystemPath(
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
              path: joinFilesystemPath(
                selectedBase ?? defaultBase,
                slugFromRemoteUrl(remote.text),
              ),
              isSelected: selectedBase != null,
              onPressed:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedBase = path;
                        }),
                  ),
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
    _showStoreForm(
      context: context,
      title: 'Delete local store',
      fields: <Widget>[
        Text(root),
        TextField(
          controller: confirmation,
          decoration: const InputDecoration(
            labelText: 'Type full path to confirm',
          ),
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
        AppNotification.show(context, '$error');
      }
    }
  }
}

class _PasswordStoresSheetBody extends StatelessWidget {
  const _PasswordStoresSheetBody({
    required this.lifecycle,
    required this.stores,
    required this.onStoreMenu,
    required this.onCreate,
    required this.onImport,
    required this.onClone,
  });

  final StoreLifecycleSnapshot lifecycle;
  final List<StoreStatus> stores;
  final void Function(String action, String root) onStoreMenu;
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 8),
              Text(lifecycle.onboardingState.label),
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
                      '${store.root}\n${store.issues.isEmpty ? 'Ready' : store.issues.join(', ')}',
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
                          (context) => const <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'select',
                              child: Text('Select'),
                            ),
                            PopupMenuItem<String>(
                              value: 'remove',
                              child: Text('Remove from app'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Delete local store'),
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

class _PickerStoreFormSheetBody extends StatelessWidget {
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
              onPressed: canSubmit ? onSubmit : null,
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
