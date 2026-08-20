part of '../onboarding_screen.dart';

class _PgpSetupStep extends StatelessWidget {
  const _PgpSetupStep({
    required this.keys,
    required this.onUseKey,
    required this.onCreateKey,
    required this.onImportKey,
  });

  final List<KeyRecord> keys;
  final ValueChanged<KeyRecord> onUseKey;
  final VoidCallback onCreateKey;
  final VoidCallback onImportKey;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        if (keys.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_off_outlined),
            title: Text(context.l10n.noPgpKeysFound),
            subtitle: Text(context.l10n.createOrImportEncryptionKey),
          )
        else
          for (final key in keys)
            Card(
              child: ListTile(
                title: Text(key.name),
                subtitle: Text('${key.fingerprint}\n${key.source}'),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: () => onUseKey(key),
                  child: Text(context.l10n.usePgpKey),
                ),
              ),
            ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onCreateKey,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.createPgpKey),
            ),
            OutlinedButton.icon(
              onPressed: onImportKey,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(context.l10n.importPgpKey),
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
    required this.onCreateKey,
    required this.onImportKey,
    required this.onOpenGithubSettings,
    required this.onSkip,
  });

  final List<KeyRecord> keys;
  final VoidCallback onCreateKey;
  final VoidCallback onImportKey;
  final VoidCallback onOpenGithubSettings;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        if (keys.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(context.l10n.noSshKeysConfigured),
            subtitle: Text(context.l10n.sshOptionalDescription),
          )
        else
          for (final key in keys)
            Card(
              child: ListTile(
                title: Text(key.name),
                subtitle: Text('${key.fingerprint}\n${key.source}'),
                isThreeLine: true,
              ),
            ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onCreateKey,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.generateSshKey),
            ),
            OutlinedButton.icon(
              onPressed: onImportKey,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(context.l10n.importSshKey),
            ),
            OutlinedButton.icon(
              onPressed: onOpenGithubSettings,
              icon: const Icon(Icons.open_in_new),
              label: Text(context.l10n.githubSettings),
            ),
            TextButton(onPressed: onSkip, child: Text(context.l10n.skipSsh)),
          ],
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
        ),
        TextField(
          controller: email,
          decoration: InputDecoration(labelText: context.l10n.emailField),
        ),
        TextField(
          controller: passphrase,
          obscureText: true,
          decoration: InputDecoration(labelText: context.l10n.passphraseField),
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
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
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
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 10),
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
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = UiProblem.fromError(context.l10n, error).summary;
          _isSubmitting = false;
        });
      }
    }
  }
}
