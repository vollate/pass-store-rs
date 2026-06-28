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
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.key_off_outlined),
            title: Text('No PGP keys found'),
            subtitle: Text('Create or import a key to encrypt entries.'),
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
                  child: const Text('Use PGP key'),
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
              label: const Text('Create PGP key'),
            ),
            OutlinedButton.icon(
              onPressed: onImportKey,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import PGP key'),
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
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vpn_key_outlined),
            title: Text('No SSH keys configured'),
            subtitle: Text('SSH is optional and can be added later.'),
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
              label: const Text('Generate SSH key'),
            ),
            OutlinedButton.icon(
              onPressed: onImportKey,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import SSH key'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenGithubSettings,
              icon: const Icon(Icons.open_in_new),
              label: const Text('GitHub settings'),
            ),
            TextButton(onPressed: onSkip, child: const Text('Skip SSH')),
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
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        TextField(
          controller: passphrase,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
      ],
    );
  }
}

class _ImportPgpKeyFields extends StatelessWidget {
  const _ImportPgpKeyFields({required this.keyText});

  final TextEditingController keyText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: keyText,
      minLines: 4,
      maxLines: 8,
      decoration: const InputDecoration(labelText: 'Key text'),
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
      decoration: const InputDecoration(labelText: 'Name'),
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
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: privateKey,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Private key'),
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
          _error = error.toString();
          _isSubmitting = false;
        });
      }
    }
  }
}
