part of '../settings_screen.dart';

extension _SettingsScreenSshKeySheets on SettingsScreen {
  void _showSshKeys(BuildContext context) {
    showParsAdaptiveDetail<void>(
      context: context,
      builder:
          (surfaceContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              final keys = keyRepository.keys
                  .where((key) => key.type == KeyRecordType.ssh)
                  .toList(growable: false);
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(ParsSpacing.lg),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                context.l10n.sshKeysTitle,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.githubSettings,
                              onPressed: () => openGithubSshSettings(context),
                              icon: const Icon(Icons.open_in_new),
                            ),
                          ],
                        ),
                        const SizedBox(height: ParsSpacing.xs),
                        Text(context.l10n.sshKeysGitOnlyDescription),
                        const SizedBox(height: ParsSpacing.sm),
                        AppSectionBox(
                          padding: EdgeInsets.zero,
                          title: context.l10n.sshKeysTitle,
                          emptyLabel: context.l10n.noSshKeys,
                          children: <Widget>[
                            for (final key in keys)
                              ParsSectionRow(
                                leading: const ParsSectionRowIcon(
                                  icon: Icons.vpn_key_outlined,
                                ),
                                title: key.name,
                                subtitle: key.fingerprint,
                                onTap: () => _exportSshPublic(context, key),
                                trailing: PopupMenuButton<String>(
                                  tooltip: context.l10n.keyActionsTooltip(
                                    context.l10n.sshStep,
                                    key.name,
                                  ),
                                  onSelected: (action) {
                                    switch (action) {
                                      case 'export_public':
                                        _exportSshPublic(context, key);
                                      case 'export_private':
                                        _showExportSshPrivate(context, key);
                                      case 'delete':
                                        _showDeleteSshKey(
                                          context,
                                          key,
                                          setSheetState,
                                        );
                                    }
                                  },
                                  itemBuilder:
                                      (context) => <PopupMenuEntry<String>>[
                                        PopupMenuItem(
                                          value: 'export_public',
                                          child: Text(
                                            context.l10n.exportPublic,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'export_private',
                                          child: Text(
                                            context.l10n.exportPrivate,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(context.l10n.delete),
                                        ),
                                      ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: ParsSpacing.md),
                        ParsButtonGrid(
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed:
                                  () => _showGenerateSshKey(
                                    context,
                                    setSheetState,
                                  ),
                              icon: const Icon(Icons.add),
                              label: Text(context.l10n.generateAction),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  () => _showImportSshOptions(
                                    context,
                                    setSheetState,
                                  ),
                              icon: const Icon(Icons.file_upload_outlined),
                              label: Text(context.l10n.importAction),
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

  Future<void> _showGenerateSshKey(
    BuildContext context,
    StateSetter refreshSheet,
  ) async {
    final name = TextEditingController(text: 'github-mobile-ed25519');
    KeyRecord? generated;
    await _showSshActionForm(
      context: context,
      title: context.l10n.generateSshKey,
      fields: <Widget>[
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: context.l10n.nameField),
          textInputAction: TextInputAction.done,
        ),
      ],
      submitLabel: context.l10n.generateSshKey,
      onSubmit: () async {
        generated = await keyRepository.generateSshKey(name.text.trim());
        await settingsRepository.refresh();
      },
    );
    if (!context.mounted) return;
    refreshSheet(() {});
    final key = generated;
    if (key != null) await _exportSshPublic(context, key);
  }

  Future<void> _showImportSshOptions(
    BuildContext context,
    StateSetter refreshSheet,
  ) async {
    final source = await chooseSshImportSource(context);
    if (!context.mounted || source == null) return;
    if (source == 'file') {
      await _showImportSshFile(context, refreshSheet);
    } else {
      await _showImportSshText(context, refreshSheet);
    }
  }

  Future<void> _showImportSshText(
    BuildContext context,
    StateSetter refreshSheet,
  ) async {
    final name = TextEditingController();
    final privateKey = TextEditingController();
    await _showSshActionForm(
      context: context,
      title: context.l10n.importSshKey,
      fields: <Widget>[
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: context.l10n.nameField),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: privateKey,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: context.l10n.privateKeyMaterial,
          ),
        ),
      ],
      submitLabel: context.l10n.importAction,
      onSubmit: () async {
        try {
          await keyRepository.importSshPrivateKeyText(
            name: name.text.trim(),
            privateKey: privateKey.text.trim(),
          );
          await settingsRepository.refresh();
        } finally {
          privateKey.clear();
        }
      },
    );
    if (context.mounted) refreshSheet(() {});
  }

  Future<void> _showImportSshFile(
    BuildContext context,
    StateSetter refreshSheet,
  ) async {
    SelectedKeyFile? selectedFile;
    final name = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => _SshActionFormBody(
                  title: context.l10n.importSshKeyFile,
                  fields: <Widget>[
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: context.l10n.nameField,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: ParsSpacing.sm),
                    PathPickerRow(
                      title: context.l10n.keyFileField,
                      path:
                          selectedFile?.location ??
                          _defaultSshKeyFileBasePath(),
                      isSelected: selectedFile != null,
                      onPressed: () async {
                        final selected = await pathPickerService.pickKeyFile(
                          initialDirectory: _defaultSshKeyFileBasePath(),
                        );
                        if (selected == null) return;
                        selectedFile = selected;
                        name.text = selected.fileName;
                        setSheetState(() {});
                      },
                    ),
                  ],
                  submitLabel: context.l10n.importAction,
                  canSubmit:
                      () => selectedFile != null && name.text.trim().isNotEmpty,
                  onSubmit: () async {
                    final privateKey = await selectedFile!.readText();
                    await keyRepository.importSshPrivateKeyText(
                      name: name.text.trim(),
                      privateKey: privateKey,
                    );
                    await settingsRepository.refresh();
                  },
                ),
          ),
    );
    if (context.mounted) refreshSheet(() {});
  }

  Future<void> _exportSshPublic(BuildContext context, KeyRecord key) async {
    try {
      final value = await keyRepository.exportSshPublicKey(key.name);
      if (!context.mounted) return;
      await showSshPublicKeyDialog(
        context,
        keyName: key.name,
        publicKey: value,
      );
    } catch (error) {
      if (context.mounted) {
        AppNotification.show(
          context,
          UiProblem.fromError(context.l10n, error).summary,
        );
      }
    }
  }

  void _showExportSshPrivate(BuildContext context, KeyRecord key) {
    final confirmation = TextEditingController();
    final expected = 'EXPORT PRIVATE KEY ${key.name}';
    _showSshActionForm(
      context: context,
      title: context.l10n.exportPrivate,
      fields: <Widget>[
        Text(context.l10n.typeToConfirm(expected)),
        TextField(
          controller: confirmation,
          decoration: InputDecoration(labelText: context.l10n.confirmation),
        ),
      ],
      submitLabel: context.l10n.exportPrivate,
      onSubmit: () async {
        final value = await keyRepository.exportSshPrivateKey(
          name: key.name,
          confirmation: confirmation.text,
        );
        if (context.mounted) {
          _showKeyExport(context, context.l10n.exportPrivate, value);
        }
      },
    );
  }

  Future<void> _showDeleteSshKey(
    BuildContext context,
    KeyRecord key,
    StateSetter refreshSheet,
  ) async {
    if (!await confirmDeleteSshKey(context, key.name)) return;
    try {
      await keyRepository.deleteSshKey(key.name);
      await settingsRepository.refresh();
      if (context.mounted) refreshSheet(() {});
    } catch (error) {
      if (context.mounted) {
        AppNotification.show(
          context,
          UiProblem.fromError(context.l10n, error).summary,
          severity: AppNotificationSeverity.error,
        );
      }
    }
  }

  void _showKeyExport(BuildContext context, String title, String value) {
    showDialog<void>(
      context: context,
      builder:
          (context) => ParsDialog(
            title: title,
            content: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            primary: ParsDialogAction(
              label: context.l10n.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
    );
  }

  String _defaultSshKeyFileBasePath() {
    final root = settingsRepository.store?.root;
    if (root != null && root.trim().isNotEmpty) return parentDirectory(root);
    return defaultUserDirectory();
  }

  Future<void> _showSshActionForm({
    required BuildContext context,
    required String title,
    required List<Widget> fields,
    required String submitLabel,
    required Future<void> Function() onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _SshActionFormBody(
            title: title,
            fields: fields,
            submitLabel: submitLabel,
            canSubmit: () => true,
            onSubmit: onSubmit,
          ),
    );
  }
}

class _SshActionFormBody extends StatefulWidget {
  const _SshActionFormBody({
    required this.title,
    required this.fields,
    required this.submitLabel,
    required this.canSubmit,
    required this.onSubmit,
  });

  final String title;
  final List<Widget> fields;
  final String submitLabel;
  final bool Function() canSubmit;
  final Future<void> Function() onSubmit;

  @override
  State<_SshActionFormBody> createState() => _SshActionFormBodyState();
}

class _SshActionFormBodyState extends State<_SshActionFormBody> {
  bool _submitting = false;
  String? _error;

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
              ...widget.fields,
              if (_error != null) ...<Widget>[
                const SizedBox(height: ParsSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: ParsSpacing.md),
              FilledButton(
                onPressed: _submitting || !widget.canSubmit() ? null : _submit,
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
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = UiProblem.fromError(context.l10n, error).summary;
      });
    }
  }
}
