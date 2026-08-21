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
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.sshKeysTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(context.l10n.sshKeysGitOnlyDescription),
                        const SizedBox(height: 12),
                        if (keys.isEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.vpn_key_off_outlined),
                            title: Text(context.l10n.noSshKeys),
                            subtitle: Text(context.l10n.sshOptionalDescription),
                          ),
                        for (final key in keys)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.vpn_key_outlined),
                              title: Text(key.name),
                              subtitle: Text(key.fingerprint),
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
                                        child: Text(context.l10n.exportPublic),
                                      ),
                                      PopupMenuItem(
                                        value: 'export_private',
                                        child: Text(context.l10n.exportPrivate),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(context.l10n.delete),
                                      ),
                                    ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: () => _showGenerateSshKey(context),
                              icon: const Icon(Icons.add),
                              label: Text(context.l10n.generateSshKey),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _showImportSshOptions(context),
                              icon: const Icon(Icons.file_upload_outlined),
                              label: Text(context.l10n.importSshKey),
                            ),
                            TextButton.icon(
                              onPressed: () => _showGithubSshSettings(context),
                              icon: const Icon(Icons.open_in_new),
                              label: Text(context.l10n.githubSettings),
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

  void _showGenerateSshKey(BuildContext context) {
    final name = TextEditingController(text: 'github-mobile-ed25519');
    _showSshActionForm(
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
        await keyRepository.generateSshKey(name.text);
        await settingsRepository.refresh();
      },
    );
  }

  void _showImportSshOptions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(dialogContext.l10n.importSshKey),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportSshText(context);
                },
                child: Text(dialogContext.l10n.textSource),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportSshFile(context);
                },
                child: Text(dialogContext.l10n.fileSource),
              ),
            ],
          ),
    );
  }

  void _showImportSshText(BuildContext context) {
    final name = TextEditingController();
    final privateKey = TextEditingController();
    _showSshActionForm(
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
            name: name.text,
            privateKey: privateKey.text,
          );
          await settingsRepository.refresh();
        } finally {
          privateKey.clear();
        }
      },
    );
  }

  Future<void> _showImportSshFile(BuildContext context) async {
    String? selectedPath;
    final name = TextEditingController();
    showModalBottomSheet<void>(
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
                    ),
                    const SizedBox(height: 12),
                    PathPickerRow(
                      title: context.l10n.keyFileField,
                      path: selectedPath ?? _defaultSshKeyFileBasePath(),
                      isSelected: selectedPath != null,
                      onPressed: () async {
                        final path = await pathPickerService.pickFile(
                          initialDirectory: _defaultSshKeyFileBasePath(),
                        );
                        if (path != null) {
                          setSheetState(() => selectedPath = path);
                        }
                      },
                    ),
                  ],
                  submitLabel: context.l10n.importAction,
                  canSubmit:
                      () => selectedPath != null && name.text.trim().isNotEmpty,
                  onSubmit: () async {
                    await keyRepository.importSshPrivateKeyFile(
                      name: name.text,
                      path: selectedPath!,
                    );
                    await settingsRepository.refresh();
                  },
                ),
          ),
    );
  }

  Future<void> _exportSshPublic(BuildContext context, KeyRecord key) async {
    try {
      final value = await keyRepository.exportSshPublicKey(key.name);
      if (!context.mounted) return;
      _showKeyExport(context, context.l10n.exportPublic, value);
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

  void _showDeleteSshKey(
    BuildContext context,
    KeyRecord key,
    StateSetter refreshSheet,
  ) {
    final confirmation = TextEditingController();
    _showSshActionForm(
      context: context,
      title: context.l10n.delete,
      fields: <Widget>[
        Text(context.l10n.typeToConfirm(key.name)),
        TextField(
          controller: confirmation,
          decoration: InputDecoration(labelText: context.l10n.confirmation),
        ),
      ],
      submitLabel: context.l10n.delete,
      onSubmit: () async {
        if (confirmation.text != key.name) {
          throw StateError(context.l10n.typeToConfirm(key.name));
        }
        await keyRepository.deleteSshKey(key.name);
        await settingsRepository.refresh();
        refreshSheet(() {});
      },
    );
  }

  Future<void> _showGithubSshSettings(BuildContext context) async {
    final uri = await keyRepository.githubSshSettingsUri();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(context.l10n.githubSshSettings),
            content: SelectableText(uri.toString()),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.close),
              ),
            ],
          ),
    );
  }

  void _showKeyExport(BuildContext context, String title, String value) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: SelectableText(value)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.close),
              ),
            ],
          ),
    );
  }

  String _defaultSshKeyFileBasePath() {
    final root = settingsRepository.store?.root;
    if (root != null && root.trim().isNotEmpty) return parentDirectory(root);
    return defaultUserDirectory();
  }

  void _showSshActionForm({
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
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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
