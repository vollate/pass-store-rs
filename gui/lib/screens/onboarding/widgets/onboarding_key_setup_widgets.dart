part of '../onboarding_screen.dart';

String _pgpKeyDetails(KeyRecord key) => '${key.fingerprint}\n${key.source}';

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
    return ListView(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            keys.isEmpty ? Icons.key_off_outlined : Icons.key_outlined,
          ),
          title: Text(emptyTitle),
          subtitle: Text(emptySubtitle),
        ),
        for (final key in keys)
          Card(
            child:
                MediaQuery.textScalerOf(context).scale(1) >= 1.5
                    ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            key.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(_pgpKeyDetails(key)),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => onUseKey(key),
                              child: Text(context.l10n.usePgpKey),
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListTile(
                      title: Text(key.name),
                      subtitle: Text(_pgpKeyDetails(key)),
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
            if (allowCreate && onCreateKey != null)
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
        const SizedBox(height: 12),
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
