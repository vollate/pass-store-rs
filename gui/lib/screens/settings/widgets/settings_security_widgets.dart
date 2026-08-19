part of '../settings_screen.dart';

extension _SettingsScreenSecuritySheets on SettingsScreen {
  void _showUnavailableSheet(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _UnavailableFeatureSheetBody(title: title),
    );
  }

  void _showRuntimeDiagnostics(BuildContext context) {
    final diagnostics =
        _runtimeDiagnostics?.runtimeDiagnostics(securityRepository) ??
        RuntimeDiagnostics(
          bridgeLoaded: false,
          coreVersion: 'Unavailable',
          pgpBackend: 'Unavailable',
          gitBackend: 'Unavailable',
          keyStorageBackend: keyStorageBackendLabel(securityRepository),
          nativeLibrary: 'Unavailable',
        );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _RuntimeDiagnosticsSheetBody(diagnostics: diagnostics),
    );
  }

  void _showSecuritySheet(BuildContext context) {
    final rootContext = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder:
          (context) => _SecuritySettingsSheetBody(
            securityRepository: securityRepository,
            onSecuritySettingsChanged: onSecuritySettingsChanged,
            runDuringSystemAuthentication: _runDuringSystemAuthentication,
            onOnboardingReset: onOnboardingReset,
            onNotify: (message) {
              if (rootContext.mounted) {
                AppNotification.show(rootContext, message);
              }
            },
          ),
    );
  }

  Future<T> _runDuringSystemAuthentication<T>(
    Future<T> Function() action,
  ) async {
    final runner = runDuringSystemAuthentication;
    if (runner == null) {
      return action();
    }
    return runner(action);
  }

  void _showPgpSessionTimeoutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (context) => _PgpSessionTimeoutSheetBody(
            securityRepository: securityRepository,
            onSecuritySettingsChanged: onSecuritySettingsChanged,
          ),
    );
  }

  void _showPgpPassphraseStorageSheet(BuildContext context) {
    final privatePgpKeys = keyRepository.keys
        .where((key) => key.type == KeyRecordType.pgp && key.hasPrivateKey)
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _PgpPassphraseStorageSheetBody(
            securityRepository: securityRepository,
            privatePgpKeys: privatePgpKeys,
            autofillRepository: autofillRepository,
            entries: vaultRepository?.entries ?? const <PasswordEntry>[],
            onSecuritySettingsChanged: onSecuritySettingsChanged,
          ),
    );
  }
}

class _UnavailableFeatureSheetBody extends StatelessWidget {
  const _UnavailableFeatureSheetBody({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
            const Text(
              'This repository does not provide the operations required for '
              'this feature. Use a bridge-backed repository to enable it.',
            ),
          ],
        ),
      ),
    );
  }
}

class _RuntimeDiagnosticsSheetBody extends StatelessWidget {
  const _RuntimeDiagnosticsSheetBody({required this.diagnostics});

  final RuntimeDiagnostics diagnostics;

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
                'Runtime diagnostics',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _DiagnosticRow(
                label: 'Bridge loaded',
                value: diagnostics.bridgeLoaded ? 'Yes' : 'No',
              ),
              _DiagnosticRow(
                label: 'Core version',
                value: diagnostics.coreVersion,
              ),
              _DiagnosticRow(
                label: 'Native library',
                value: diagnostics.nativeLibrary,
              ),
              _DiagnosticRow(
                label: 'PGP backend',
                value: diagnostics.pgpBackend,
              ),
              _DiagnosticRow(
                label: 'Git backend',
                value: diagnostics.gitBackend,
              ),
              _DiagnosticRow(
                label: 'Key storage backend',
                value: diagnostics.keyStorageBackend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecuritySettingsSheetBody extends StatefulWidget {
  const _SecuritySettingsSheetBody({
    required this.securityRepository,
    required this.runDuringSystemAuthentication,
    required this.onNotify,
    this.onSecuritySettingsChanged,
    this.onOnboardingReset,
  });

  final SecurityRepository securityRepository;
  final Future<T> Function<T>(Future<T> Function() action)
  runDuringSystemAuthentication;
  final ValueChanged<String> onNotify;
  final VoidCallback? onSecuritySettingsChanged;
  final VoidCallback? onOnboardingReset;

  @override
  State<_SecuritySettingsSheetBody> createState() =>
      _SecuritySettingsSheetBodyState();
}

class _SecuritySettingsSheetBodyState
    extends State<_SecuritySettingsSheetBody> {
  static const _timeoutOptions = <Duration>[
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  var _isChangingGesture = false;

  @override
  Widget build(BuildContext context) {
    if (_isChangingGesture) {
      return _GestureChangeSheetBody(
        securityRepository: widget.securityRepository,
        onSaved: () {
          widget.onSecuritySettingsChanged?.call();
          setState(() => _isChangingGesture = false);
          widget.onNotify('Gesture updated');
        },
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Gesture lock and biometrics',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _isChangingGesture = true),
              icon: const Icon(Icons.pattern),
              label: const Text('Change gesture'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require unlock on app resume'),
              subtitle: const Text('Gesture unlock is used as fallback'),
              value: widget.securityRepository.lockOnResume,
              onChanged: (value) async {
                await widget.securityRepository.setLockOnResume(value);
                widget.onSecuritySettingsChanged?.call();
                setState(() {});
              },
            ),
            FutureBuilder<BiometricUnlockStatus>(
              future: widget.securityRepository.biometricUnlockStatus(),
              builder: (context, snapshot) {
                final status =
                    snapshot.data ?? BiometricUnlockStatus.unavailable;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Biometric unlock'),
                  subtitle: Text(_biometricSubtitle(status)),
                  value:
                      status == BiometricUnlockStatus.available &&
                      widget.securityRepository.biometricUnlockEnabled,
                  onChanged:
                      status == BiometricUnlockStatus.unavailable
                          ? null
                          : (value) async {
                            try {
                              await widget.runDuringSystemAuthentication(
                                () => widget.securityRepository
                                    .setBiometricUnlockEnabled(value),
                              );
                              widget.onSecuritySettingsChanged?.call();
                            } catch (error) {
                              final message =
                                  error is StateError
                                      ? error.message
                                      : '$error';
                              widget.onNotify(message);
                            }
                            if (mounted) {
                              setState(() {});
                            }
                          },
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Auto-lock timeout',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final timeout in _timeoutOptions)
                  ChoiceChip(
                    label: Text(_timeoutLabel(timeout)),
                    selected:
                        widget.securityRepository.autoLockTimeout == timeout,
                    onSelected: (_) async {
                      await widget.securityRepository.setAutoLockTimeout(
                        timeout,
                      );
                      widget.onSecuritySettingsChanged?.call();
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.securityRepository.setOnboardingComplete(false);
                widget.onOnboardingReset?.call();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset onboarding'),
            ),
          ],
        ),
      ),
    );
  }

  String _timeoutLabel(Duration timeout) {
    if (timeout <= Duration.zero) {
      return 'Never';
    }
    if (timeout.inMinutes < 60) {
      return '${timeout.inMinutes} min';
    }
    return '${timeout.inHours} hour';
  }

  String _biometricSubtitle(BiometricUnlockStatus status) {
    switch (status) {
      case BiometricUnlockStatus.available:
        return 'Use device biometrics, with gesture fallback';
      case BiometricUnlockStatus.disabled:
        return 'Available on this device';
      case BiometricUnlockStatus.unavailable:
        return 'Unavailable on this device';
    }
  }
}

class _GestureChangeSheetBody extends StatelessWidget {
  const _GestureChangeSheetBody({
    required this.securityRepository,
    required this.onSaved,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Change gesture',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Draw and confirm a new local unlock gesture.'),
              const SizedBox(height: 12),
              Expanded(
                child: GestureSetupPanel(
                  securityRepository: securityRepository,
                  onSaved: onSaved,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PgpSessionTimeoutSheetBody extends StatefulWidget {
  const _PgpSessionTimeoutSheetBody({
    required this.securityRepository,
    this.onSecuritySettingsChanged,
  });

  final SecurityRepository securityRepository;
  final VoidCallback? onSecuritySettingsChanged;

  @override
  State<_PgpSessionTimeoutSheetBody> createState() =>
      _PgpSessionTimeoutSheetBodyState();
}

class _PgpSessionTimeoutSheetBodyState
    extends State<_PgpSessionTimeoutSheetBody> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'PGP session timeout',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final expiration in PgpSessionExpiration.values)
                  ChoiceChip(
                    label: Text(expiration.label),
                    selected:
                        widget.securityRepository.pgpSessionExpiration ==
                        expiration,
                    onSelected: (_) async {
                      await widget.securityRepository.setPgpSessionExpiration(
                        expiration,
                      );
                      widget.onSecuritySettingsChanged?.call();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PgpPassphraseStorageSheetBody extends StatefulWidget {
  const _PgpPassphraseStorageSheetBody({
    required this.securityRepository,
    required this.privatePgpKeys,
    required this.entries,
    this.autofillRepository,
    this.onSecuritySettingsChanged,
  });

  final SecurityRepository securityRepository;
  final List<KeyRecord> privatePgpKeys;
  final List<PasswordEntry> entries;
  final AutofillRepository? autofillRepository;
  final VoidCallback? onSecuritySettingsChanged;

  @override
  State<_PgpPassphraseStorageSheetBody> createState() =>
      _PgpPassphraseStorageSheetBodyState();
}

class _PgpPassphraseStorageSheetBodyState
    extends State<_PgpPassphraseStorageSheetBody> {
  late final TextEditingController _passphrase;
  String? _selectedFingerprint;

  @override
  void initState() {
    super.initState();
    _passphrase = TextEditingController();
    _selectedFingerprint =
        widget.privatePgpKeys.isEmpty
            ? null
            : widget.privatePgpKeys.first.fingerprint;
  }

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

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
              'KMS / Keychain passphrase',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Store PGP passphrase'),
              subtitle: const Text(
                'Saved in the platform secure storage provider',
              ),
              value: widget.securityRepository.pgpPassphraseStorageEnabled,
              onChanged: (value) async {
                await widget.securityRepository.setPgpPassphraseStorageEnabled(
                  value,
                );
                if (!value) {
                  await widget.autofillRepository?.clearIndex();
                }
                widget.onSecuritySettingsChanged?.call();
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            if (widget.privatePgpKeys.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.key_off_outlined),
                title: Text('No private PGP keys'),
                subtitle: Text(
                  'Import or create a private PGP key before saving a passphrase.',
                ),
              )
            else
              DropdownButtonFormField<String>(
                key: const Key('pgp-passphrase-key-dropdown'),
                initialValue: _selectedFingerprint,
                decoration: const InputDecoration(labelText: 'PGP key'),
                items: widget.privatePgpKeys
                    .map(
                      (key) => DropdownMenuItem<String>(
                        value: key.fingerprint,
                        child: Text(key.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged:
                    widget.securityRepository.pgpPassphraseStorageEnabled
                        ? (value) {
                          setState(() {
                            _selectedFingerprint = value;
                          });
                        }
                        : null,
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _passphrase,
              enabled: widget.securityRepository.pgpPassphraseStorageEnabled,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    widget.securityRepository.hasStoredPgpPassphrase
                        ? 'Replace cached passphrase'
                        : 'PGP passphrase',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      widget.securityRepository.pgpPassphraseStorageEnabled &&
                              _selectedFingerprint != null
                          ? () async {
                            try {
                              await widget.securityRepository.savePgpPassphrase(
                                fingerprint: _selectedFingerprint!,
                                passphrase: _passphrase.text,
                              );
                              await widget.autofillRepository
                                  ?.publishPlatformState();
                              _passphrase.clear();
                              widget.onSecuritySettingsChanged?.call();
                              setState(() {});
                            } catch (error) {
                              if (!context.mounted) return;
                              AppNotification.show(context, error.toString());
                            }
                          }
                          : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      widget.securityRepository.hasStoredPgpPassphrase
                          ? () async {
                            await widget.securityRepository
                                .clearPgpPassphrase();
                            await widget.autofillRepository
                                ?.publishPlatformState();
                            widget.onSecuritySettingsChanged?.call();
                            setState(() {});
                          }
                          : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<PgpPassphraseCache?>(
              future: widget.securityRepository.readPgpPassphrase(),
              builder: (context, snapshot) {
                final cached = snapshot.data;
                final cachedKey =
                    cached == null
                        ? null
                        : _keyForFingerprint(cached.fingerprint);
                return Text(
                  cached == null
                      ? 'No PGP passphrase is cached.'
                      : 'Cached for ${cachedKey?.name ?? cached.fingerprint}',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  KeyRecord? _keyForFingerprint(String fingerprint) {
    for (final key in widget.privatePgpKeys) {
      if (key.fingerprint == fingerprint) {
        return key;
      }
    }
    return null;
  }
}
