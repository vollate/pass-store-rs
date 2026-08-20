part of '../settings_screen.dart';

extension _SettingsScreenKeyManagementSheets on SettingsScreen {
  void _showKeys(BuildContext context, KeyRecordType type) {
    showParsAdaptiveDetail<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSheetState) {
              final localizations = context.l10n;
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
                          type == KeyRecordType.pgp
                              ? localizations.pgpKeysTitle
                              : localizations.sshKeysTitle,
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
                                  ? localizations.noPgpKeys
                                  : localizations.noSshKeys,
                            ),
                            subtitle: Text(localizations.createOrImportKey),
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
                                        tooltip: localizations
                                            .keyActionsTooltip(
                                              key.type == KeyRecordType.pgp
                                                  ? localizations.pgpStep
                                                  : localizations.sshStep,
                                              key.name,
                                            ),
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
                              child: Text(localizations.create),
                            ),
                            OutlinedButton(
                              onPressed:
                                  () => _showImportKeyOptions(context, type),
                              child: Text(localizations.importAction),
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
    final localizations = context.l10n;
    return <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'export_public',
        child: Text(localizations.exportPublic),
      ),
      PopupMenuItem<String>(
        value: 'export_private',
        child: Text(localizations.exportPrivate),
      ),
      if (type == KeyRecordType.pgp)
        PopupMenuItem<String>(
          value: 'add_to_store',
          child: Text(localizations.addToGpgId),
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
                title: Text(
                  localizations.deleteKeyTitle(
                    key.type == KeyRecordType.pgp
                        ? localizations.pgpStep
                        : localizations.sshStep,
                  ),
                ),
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
                                    UiProblem.fromError(
                                      sheetContext.l10n,
                                      error,
                                    ).summary,
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
              type == KeyRecordType.pgp
                  ? context.l10n.createPgpKey
                  : context.l10n.createSshKey,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: context.l10n.nameField,
                  ),
                ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: email,
                    decoration: InputDecoration(
                      labelText: context.l10n.emailField,
                    ),
                  ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: passphrase,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.passphraseField,
                    ),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel),
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
                child: Text(context.l10n.create),
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
                      context.l10n.importPgpKey,
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
                          _importNotification(context.l10n, completion),
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
            title: Text(dialogContext.l10n.importSshKey),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportKeyForm(sheetContext, KeyRecordType.ssh);
                },
                child: Text(dialogContext.l10n.textSource),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportKeyFileForm(sheetContext, KeyRecordType.ssh);
                },
                child: Text(dialogContext.l10n.fileSource),
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
            title: Text(context.l10n.importSshKey),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: context.l10n.nameField,
                  ),
                ),
                TextField(
                  controller: keyText,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: context.l10n.keyTextField,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel),
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
                child: Text(context.l10n.importAction),
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
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
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
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
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
                  title: Text(context.l10n.importSshKeyFile),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: name,
                        decoration: InputDecoration(
                          labelText: context.l10n.nameField,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PathPickerRow(
                        title: context.l10n.keyFileField,
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
                      child: Text(context.l10n.cancel),
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
                      child: Text(context.l10n.importAction),
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
                  title: Text(dialogContext.l10n.exportPrivateKey),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        key.name,
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dialogContext.l10n.fingerprintValue(key.fingerprint),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        dialogContext.l10n.privateExportSensitive(requiredText),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmation,
                        decoration: InputDecoration(
                          labelText: dialogContext.l10n.typeToConfirm(
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
                      child: Text(dialogContext.l10n.cancel),
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
                      child: Text(dialogContext.l10n.exportAction),
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
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
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
              title: Text(context.l10n.exportedKey),
              content: SelectableText(text),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.close),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
    }
  }

  Future<void> _addPgpKeyToStore(BuildContext context, KeyRecord key) async {
    try {
      await keyRepository.addPgpKeyToSelectedStore(key.fingerprint);
      if (!context.mounted) return;
      AppNotification.show(context, key.fingerprint);
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
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
String _importNotification(
  AppLocalizations localizations,
  PgpImportCompletion completion,
) {
  final label = _keyConfirmationLabel(completion.key);
  if (completion.rememberFailed) {
    return localizations.importedKeyRememberFailed(label);
  }
  return localizations.importedKey(label);
}

String _privateKeyExportPhrase(KeyRecord key) {
  return 'EXPORT PRIVATE KEY ${_keyConfirmationLabel(key)}';
}
