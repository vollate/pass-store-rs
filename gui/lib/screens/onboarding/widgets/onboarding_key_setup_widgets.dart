part of '../onboarding_screen.dart';

// Key steps keep their list in the middle and their actions pinned at the
// bottom, so actions stay reachable however many keys exist. At large text
// sizes the actions alone can exceed the step height, so the whole step
// scrolls instead.
class _KeyStepLayout extends StatelessWidget {
  const _KeyStepLayout({
    required this.buildList,
    required this.actions,
    this.intro,
  });

  final Widget? intro;
  final Widget Function(bool scrollable) buildList;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final lead = <Widget>[
      if (intro case final intro?) ...<Widget>[
        intro,
        const SizedBox(height: ParsSpacing.md),
      ],
    ];
    if (largeText) {
      return ListView(
        children: <Widget>[...lead, buildList(false), ...actions],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[...lead, Expanded(child: buildList(true)), ...actions],
    );
  }
}

Widget _fullWidthButton(Widget button) =>
    SizedBox(width: double.infinity, child: button);

class _PgpKeysStep extends StatelessWidget {
  const _PgpKeysStep({
    required this.keys,
    required this.selectedFingerprint,
    required this.onSelectKey,
    required this.onCreateKey,
    required this.onImportKey,
    required this.onContinue,
  });

  final List<KeyRecord> keys;
  final String? selectedFingerprint;
  final ValueChanged<KeyRecord> onSelectKey;
  final VoidCallback onCreateKey;
  final VoidCallback onImportKey;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final showSelection = keys.length > 1;
    return _KeyStepLayout(
      buildList:
          (scrollable) => AppSectionBox(
            padding: EdgeInsets.zero,
            scrollable: scrollable,
            title: localizations.pgpKeysTitle,
            emptyLabel: localizations.noPrivatePgpKeys,
            children: <Widget>[
              for (final key in keys)
                ParsSectionRow(
                  leading: const ParsSectionRowIcon(icon: Icons.key_outlined),
                  title: key.name,
                  subtitle: key.fingerprint,
                  selected:
                      showSelection && key.fingerprint == selectedFingerprint,
                  onTap: () => onSelectKey(key),
                  trailing:
                      showSelection && key.fingerprint == selectedFingerprint
                          ? Padding(
                            padding: const EdgeInsets.all(ParsSpacing.sm),
                            child: Icon(
                              Icons.check_circle,
                              color: colorScheme.primary,
                            ),
                          )
                          : null,
                ),
            ],
          ),
      actions: <Widget>[
        const SizedBox(height: ParsSpacing.md),
        ParsButtonGrid(
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: onCreateKey,
              icon: const Icon(Icons.add),
              label: Text(localizations.create),
            ),
            OutlinedButton.icon(
              onPressed: onImportKey,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(localizations.importAction),
            ),
          ],
        ),
        const SizedBox(height: ParsSpacing.sm),
        _fullWidthButton(
          FilledButton(
            onPressed: keys.isEmpty ? null : onContinue,
            child: Text(localizations.continueAction),
          ),
        ),
      ],
    );
  }
}

class _PgpSetupStep extends StatelessWidget {
  const _PgpSetupStep({
    required this.keys,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onUseKey,
    required this.onCreateKey,
    required this.onImportKey,
    required this.allowCreate,
  });

  final List<KeyRecord> keys;
  final String emptyTitle;
  final String emptySubtitle;
  final ValueChanged<KeyRecord> onUseKey;
  final VoidCallback? onCreateKey;
  final VoidCallback onImportKey;
  final bool allowCreate;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final theme = Theme.of(context);
    return _KeyStepLayout(
      intro: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(emptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: ParsSpacing.xxs),
          Text(
            emptySubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      buildList:
          (scrollable) => AppSectionBox(
            padding: EdgeInsets.zero,
            scrollable: scrollable,
            title: localizations.pgpKeysTitle,
            emptyLabel: localizations.noPrivatePgpKeys,
            children: <Widget>[
              for (final key in keys)
                ParsSectionRow(
                  leading: const ParsSectionRowIcon(icon: Icons.key_outlined),
                  title: key.name,
                  subtitle: key.fingerprint,
                  onTap: () => onUseKey(key),
                  trailing: TextButton(
                    onPressed: () => onUseKey(key),
                    child: Text(localizations.usePgpKey),
                  ),
                ),
            ],
          ),
      actions: <Widget>[
        const SizedBox(height: ParsSpacing.md),
        ParsButtonGrid(
          children: <Widget>[
            if (allowCreate && onCreateKey != null)
              FilledButton.tonalIcon(
                onPressed: onCreateKey,
                icon: const Icon(Icons.add),
                label: Text(localizations.createPgpKey),
              ),
            OutlinedButton.icon(
              onPressed: onImportKey,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(localizations.importPgpKey),
            ),
          ],
        ),
      ],
    );
  }
}

class _SshSetupStep extends StatelessWidget {
  const _SshSetupStep({
    required this.keys,
    required this.onGenerateKey,
    required this.onImportKey,
    required this.onShowPublicKey,
    required this.onDeleteKey,
    required this.onContinue,
  });

  final List<KeyRecord> keys;
  final VoidCallback onGenerateKey;
  final VoidCallback onImportKey;
  final ValueChanged<KeyRecord> onShowPublicKey;
  final ValueChanged<KeyRecord> onDeleteKey;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final theme = Theme.of(context);
    final generate = FilledButton.tonalIcon(
      onPressed: onGenerateKey,
      icon: const Icon(Icons.add),
      label: Text(
        localizations.generateAction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final import = OutlinedButton.icon(
      onPressed: onImportKey,
      icon: const Icon(Icons.file_upload_outlined),
      label: Text(
        localizations.importAction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    Widget keyList(bool scrollable) => AppSectionBox(
      padding: EdgeInsets.zero,
      scrollable: scrollable,
      title: localizations.sshKeysTitle,
      emptyLabel: localizations.noSshKeysConfigured,
      children: <Widget>[
        for (final key in keys)
          ParsSectionRow(
            leading: const ParsSectionRowIcon(icon: Icons.vpn_key_outlined),
            title: key.name,
            subtitle: key.fingerprint,
            onTap: () => onShowPublicKey(key),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: localizations.publicKeyMaterial,
                  onPressed: () => onShowPublicKey(key),
                  icon: const Icon(Icons.content_copy_outlined),
                ),
                IconButton(
                  tooltip: localizations.delete,
                  onPressed: () => onDeleteKey(key),
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return _KeyStepLayout(
      buildList: keyList,
      actions: <Widget>[
        const SizedBox(height: ParsSpacing.md),
        ParsButtonGrid(children: <Widget>[generate, import]),
        const SizedBox(height: ParsSpacing.sm),
        _fullWidthButton(
          keys.isEmpty
              ? OutlinedButton(
                onPressed: onContinue,
                child: Text(localizations.skipSsh),
              )
              : FilledButton(
                onPressed: onContinue,
                child: Text(localizations.continueAction),
              ),
        ),
      ],
    );
  }
}

class _StoreRepairStep extends StatelessWidget {
  const _StoreRepairStep({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: Theme.of(context).colorScheme.error),
          title: Text(title),
          subtitle: Text(message),
        ),
        const SizedBox(height: ParsSpacing.sm),
        FilledButton.tonal(
          onPressed: onAction,
          child: SizedBox(
            width: double.infinity,
            child: Center(child: Text(actionLabel)),
          ),
        ),
      ],
    );
  }
}

class _CreatePgpKeyFields extends StatelessWidget {
  const _CreatePgpKeyFields({
    required this.name,
    required this.email,
    required this.passphrase,
  });

  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController passphrase;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: context.l10n.nameField),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: email,
          decoration: InputDecoration(labelText: context.l10n.emailField),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: passphrase,
          obscureText: true,
          decoration: InputDecoration(labelText: context.l10n.passphraseField),
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }
}

class _CreateSshKeyFields extends StatelessWidget {
  const _CreateSshKeyFields({required this.name});

  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: name,
      decoration: InputDecoration(labelText: context.l10n.nameField),
      textInputAction: TextInputAction.done,
    );
  }
}

class _ImportSshKeyFields extends StatelessWidget {
  const _ImportSshKeyFields({required this.name, required this.privateKey});

  final TextEditingController name;
  final TextEditingController privateKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
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
    );
  }
}

class _ImportSshFileSheet extends StatefulWidget {
  const _ImportSshFileSheet({
    required this.repository,
    required this.pathPickerService,
    required this.initialDirectory,
    required this.onImported,
  });

  final KeyRepository repository;
  final PathPickerService pathPickerService;
  final String initialDirectory;
  final VoidCallback onImported;

  @override
  State<_ImportSshFileSheet> createState() => _ImportSshFileSheetState();
}

class _ImportSshFileSheetState extends State<_ImportSshFileSheet> {
  final TextEditingController _name = TextEditingController();
  SelectedKeyFile? _selected;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        !_isSubmitting && _selected != null && _name.text.trim().isNotEmpty;
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
                context.l10n.importSshKeyFile,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: ParsSpacing.sm),
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: context.l10n.nameField),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ParsSpacing.sm),
              PathPickerRow(
                title: context.l10n.keyFileField,
                path: _selected?.location ?? widget.initialDirectory,
                isSelected: _selected != null,
                onPressed: _chooseFile,
              ),
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
                onPressed: canSubmit ? _submit : null,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(child: Text(context.l10n.importAction)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseFile() async {
    try {
      final selected = await widget.pathPickerService.pickKeyFile(
        initialDirectory: widget.initialDirectory,
      );
      if (selected == null || !mounted) return;
      _selected = selected;
      _name.text = selected.fileName;
      setState(() => _error = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UiProblem.fromError(context.l10n, error).summary);
    }
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final privateKey = await selected.readText();
      await widget.repository.importSshPrivateKeyText(
        name: _name.text.trim(),
        privateKey: privateKey,
      );
      widget.onImported();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = UiProblem.fromError(context.l10n, error).summary;
        _isSubmitting = false;
      });
    }
  }
}

class _OnboardingFormSheet extends StatefulWidget {
  const _OnboardingFormSheet({
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
  State<_OnboardingFormSheet> createState() => _OnboardingFormSheetState();
}

class _OnboardingFormSheetState extends State<_OnboardingFormSheet> {
  bool _isSubmitting = false;
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
                onPressed: _isSubmitting ? null : _submit,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(
                    child:
                        _isSubmitting
                            ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: ParsSpacing.sm),
                                Text(widget.submitLabel),
                              ],
                            )
                            : Text(widget.submitLabel),
                  ),
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
      await widget.onSubmit();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = UiProblem.fromError(context.l10n, error).summary;
        _isSubmitting = false;
      });
    }
  }
}
