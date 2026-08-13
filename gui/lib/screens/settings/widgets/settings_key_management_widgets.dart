part of '../settings_screen.dart';

extension _SettingsScreenKeyManagementSheets on SettingsScreen {
  void _showKeys(BuildContext context, KeyRecordType type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSheetState) {
              final localizations = AppLocalizations.of(context);
              final keys = keyRepository.keys
                  .where((key) => key.type == type)
                  .toList(growable: false);
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          type == KeyRecordType.pgp ? 'PGP keys' : 'SSH keys',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        if (keys.isEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.key_off_outlined),
                            title: Text(
                              type == KeyRecordType.pgp
                                  ? 'No PGP keys'
                                  : 'No SSH keys',
                            ),
                            subtitle: const Text('Create or import a key.'),
                          ),
                        for (final key in keys)
                          Card(
                            child: ListTile(
                              title: Text(key.name),
                              subtitle: Text(
                                key.hasLocalKeyMaterial
                                    ? '${key.fingerprint}\n'
                                        '${key.source}\n'
                                        '${key.hasPrivateKey ? localizations.privateKeyMaterial : localizations.publicKeyMaterial}'
                                    : '${localizations.passwordStoreKeyReference(key.referencedByStores.join(', '))}\n'
                                        '${localizations.localKeyMaterialMissing}',
                              ),
                              isThreeLine: true,
                              trailing:
                                  key.hasLocalKeyMaterial
                                      ? PopupMenuButton<String>(
                                        tooltip:
                                            'Actions for ${key.typeLabel} key ${key.name}',
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'export_public':
                                              _exportPublicKey(context, key);
                                              break;
                                            case 'export_private':
                                              _showPrivateExportForm(
                                                context,
                                                key,
                                              );
                                              break;
                                            case 'add_to_store':
                                              _addPgpKeyToStore(context, key);
                                              break;
                                            case 'delete':
                                              _showDeleteKeyDialog(
                                                context,
                                                key,
                                                setSheetState,
                                              );
                                              break;
                                          }
                                        },
                                        itemBuilder:
                                            (context) => _keyActionMenuItems(
                                              context,
                                              key.type,
                                            ),
                                      )
                                      : null,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton(
                              onPressed:
                                  () => _showCreateKeyForm(context, type),
                              child: const Text('Create'),
                            ),
                            OutlinedButton(
                              onPressed:
                                  () => _showImportKeyOptions(context, type),
                              child: const Text('Import'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  List<PopupMenuEntry<String>> _keyActionMenuItems(
    BuildContext context,
    KeyRecordType type,
  ) {
    final localizations = AppLocalizations.of(context);
    return <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'export_public',
        child: Text('Export public'),
      ),
      const PopupMenuItem<String>(
        value: 'export_private',
        child: Text('Export private'),
      ),
      if (type == KeyRecordType.pgp)
        const PopupMenuItem<String>(
          value: 'add_to_store',
          child: Text('Add to .gpg-id'),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete',
        child: Text(localizations.deleteKeyAction),
      ),
    ];
  }

  void _showDeleteKeyDialog(
    BuildContext sheetContext,
    KeyRecord key,
    StateSetter setSheetState,
  ) {
    final confirmation = TextEditingController();
    final requiredText = _keyDeletionConfirmationLabel(key);
    var isDeleting = false;
    showDialog<void>(
      context: sheetContext,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final localizations = AppLocalizations.of(dialogContext);
              return AlertDialog(
                scrollable: true,
                title: Text(localizations.deleteKeyTitle(key.typeLabel)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      key.name,
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(localizations.fingerprintValue(key.fingerprint)),
                    const SizedBox(height: 12),
                    Text(localizations.deleteKeyDescription(requiredText)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      decoration: InputDecoration(
                        labelText: localizations.deleteKeyConfirmation(
                          requiredText,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(localizations.cancel),
                  ),
                  FilledButton(
                    onPressed:
                        confirmation.text == requiredText && !isDeleting
                            ? () async {
                              setDialogState(() => isDeleting = true);
                              try {
                                var notification = localizations.keyDeleted(
                                  key.name,
                                );
                                if (key.type == KeyRecordType.pgp) {
                                  final outcome = await keyRepository
                                      .deletePgpKey(key.fingerprint);
                                  if (outcome.privateKeyAbsent) {
                                    await securityRepository
                                        .clearPgpPassphraseForFingerprint(
                                          key.fingerprint,
                                        );
                                  }
                                  if (outcome.publicCleanupFailed) {
                                    notification =
                                        localizations.pgpKeyDeletePartial;
                                  }
                                } else {
                                  await keyRepository.deleteSshKey(key.name);
                                }
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                setSheetState(() {});
                                if (!sheetContext.mounted) return;
                                AppNotification.show(
                                  sheetContext,
                                  notification,
                                );
                              } catch (error) {
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                setSheetState(() {});
                                if (!sheetContext.mounted) return;
                                AppNotification.show(
                                  sheetContext,
                                  localizations.keyDeleteFailed(
                                    error.toString(),
                                  ),
                                );
                              }
                            }
                            : null,
                    child: Text(localizations.delete),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showCreateKeyForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final email = TextEditingController();
    final passphrase = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              type == KeyRecordType.pgp ? 'Create PGP key' : 'Create SSH key',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: passphrase,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _runKeyAction(context, () async {
                      try {
                        return type == KeyRecordType.pgp
                            ? await keyRepository.generatePgpKey(
                              name: name.text,
                              email: email.text,
                              passphrase:
                                  passphrase.text.trim().isEmpty
                                      ? null
                                      : passphrase.text,
                            )
                            : await keyRepository.generateSshKey(name.text);
                      } finally {
                        passphrase.clear();
                      }
                    }),
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  /// Opens the shared source-independent PGP import flow.
  ///
  /// SSH keeps its own Text/File dialog because it needs a key name and has no
  /// public/private detection.
  void _showImportKeyOptions(BuildContext context, KeyRecordType type) {
    if (type == KeyRecordType.ssh) {
      _showSshImportKeyOptions(context);
      return;
    }

    final sheetContext = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheet).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Import PGP key',
                      style: Theme.of(sheet).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PgpKeyImportBody(
                      keyRepository: keyRepository,
                      securityRepository: securityRepository,
                      pathPickerService: pathPickerService,
                      initialDirectory: _defaultKeyFileBasePath(),
                      onCancel: () => Navigator.of(sheet).pop(),
                      onCompleted: (completion) async {
                        // Refresh so the key list reflects what the backend confirmed.
                        await settingsRepository.refresh();
                        if (sheet.mounted) {
                          Navigator.of(sheet).pop();
                        }
                        if (!sheetContext.mounted) return;
                        AppNotification.show(
                          sheetContext,
                          _importNotification(completion),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _showSshImportKeyOptions(BuildContext context) {
    final sheetContext = context;
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Import SSH key'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportKeyForm(sheetContext, KeyRecordType.ssh);
                },
                child: const Text('Text'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportKeyFileForm(sheetContext, KeyRecordType.ssh);
                },
                child: const Text('File'),
              ),
            ],
          ),
    );
  }

  /// SSH-only text import. PGP uses [PgpKeyImportBody], which detects the key kind.
  void _showImportKeyForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final keyText = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Import SSH key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: keyText,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Key text'),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _runKeyAction(context, () async {
                      try {
                        return await keyRepository.importSshPrivateKeyText(
                          name: name.text,
                          privateKey: keyText.text,
                        );
                      } finally {
                        keyText.clear();
                      }
                    }),
                child: const Text('Import'),
              ),
            ],
          ),
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
      AppNotification.show(context, '$error');
    }
  }

  Future<void> _chooseFile(
    BuildContext context, {
    required String initialDirectory,
    required ValueChanged<String> onSelected,
  }) async {
    try {
      final path = await pathPickerService.pickFile(
        initialDirectory: initialDirectory,
      );
      if (path == null) {
        return;
      }
      onSelected(path);
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(context, '$error');
    }
  }

  String _defaultStoreBasePath() {
    final selectedRoot = settingsRepository.lifecycle.selectedStoreRoot;
    if (selectedRoot != null && selectedRoot.trim().isNotEmpty) {
      return parentDirectory(selectedRoot);
    }
    if (settingsRepository.stores.isNotEmpty) {
      return parentDirectory(settingsRepository.stores.first.root);
    }
    return parentDirectory(settingsRepository.lifecycle.configPath);
  }

  String _defaultKeyFileBasePath() {
    final selectedRoot = settingsRepository.lifecycle.selectedStoreRoot;
    if (selectedRoot != null && selectedRoot.trim().isNotEmpty) {
      return parentDirectory(selectedRoot);
    }
    return parentDirectory(settingsRepository.lifecycle.configPath);
  }

  /// SSH-only file import. The old PGP branch here always called the private-key
  /// API, which is exactly why a public key from a file used to fail.
  void _showImportKeyFileForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final defaultPath = _defaultKeyFileBasePath();
    String? selectedPath;
    showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Import SSH key file'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      PathPickerRow(
                        title: 'Key file',
                        path: selectedPath ?? defaultPath,
                        isSelected: selectedPath != null,
                        onPressed:
                            () => _chooseFile(
                              context,
                              initialDirectory: defaultPath,
                              onSelected:
                                  (path) => setDialogState(() {
                                    selectedPath = path;
                                  }),
                            ),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          selectedPath == null
                              ? null
                              : () => _runKeyAction(
                                context,
                                () => keyRepository.importSshPrivateKeyFile(
                                  name: name.text,
                                  path: selectedPath!,
                                ),
                              ),
                      child: const Text('Import'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showPrivateExportForm(BuildContext sheetContext, KeyRecord key) {
    final confirmation = TextEditingController();
    final requiredText = _privateKeyExportPhrase(key);
    showDialog<void>(
      context: sheetContext,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Export private key'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        key.name,
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Fingerprint: ${key.fingerprint}'),
                      const SizedBox(height: 12),
                      Text(
                        'Private key export is sensitive. Type $requiredText to export.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmation,
                        decoration: InputDecoration(
                          labelText: 'Type $requiredText to confirm',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          confirmation.text == requiredText
                              ? () {
                                Navigator.of(dialogContext).pop();
                                _showExportedText(
                                  sheetContext,
                                  () =>
                                      key.type == KeyRecordType.pgp
                                          ? keyRepository.exportPgpPrivateKey(
                                            fingerprint: key.fingerprint,
                                            confirmation: confirmation.text,
                                          )
                                          : keyRepository.exportSshPrivateKey(
                                            name: key.name,
                                            confirmation: confirmation.text,
                                          ),
                                );
                              }
                              : null,
                      child: const Text('Export'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _runKeyAction(
    BuildContext context,
    Future<KeyRecord> Function() action,
  ) async {
    try {
      final key = await action();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppNotification.show(context, key.name);
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(context, error.toString());
    }
  }

  void _exportPublicKey(BuildContext context, KeyRecord key) {
    _showExportedText(
      context,
      () =>
          key.type == KeyRecordType.pgp
              ? keyRepository.exportPgpPublicKey(key.fingerprint)
              : keyRepository.exportSshPublicKey(key.name),
    );
  }

  Future<void> _showExportedText(
    BuildContext context,
    Future<String> Function() action,
  ) async {
    try {
      final text = await action();
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Exported key'),
              content: SelectableText(text),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(context, error.toString());
    }
  }

  Future<void> _addPgpKeyToStore(BuildContext context, KeyRecord key) async {
    try {
      await keyRepository.addPgpKeyToSelectedStore(key.fingerprint);
      if (!context.mounted) return;
      AppNotification.show(context, key.fingerprint);
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(context, error.toString());
    }
  }
}

String _keyConfirmationLabel(KeyRecord key) {
  final name = key.name.trim();
  return name.isEmpty ? key.fingerprint : name;
}

String _keyDeletionConfirmationLabel(KeyRecord key) {
  final label = _keyConfirmationLabel(key);
  if (key.type != KeyRecordType.pgp) return label;

  final trailingEmail = RegExp(r'\s*<[^<>]+>\s*$').firstMatch(label);
  if (trailingEmail == null) return label;

  final displayName = label.substring(0, trailingEmail.start).trim();
  return displayName.isEmpty ? label : displayName;
}

/// Reports the canonical imported key, and any secure-storage failure.
///
/// Never includes the passphrase.
String _importNotification(PgpImportCompletion completion) {
  final label = _keyConfirmationLabel(completion.key);
  if (completion.rememberFailed) {
    return 'Imported $label, but remembering the passphrase failed.';
  }
  return 'Imported $label';
}

String _privateKeyExportPhrase(KeyRecord key) {
  return 'EXPORT PRIVATE KEY ${_keyConfirmationLabel(key)}';
}
