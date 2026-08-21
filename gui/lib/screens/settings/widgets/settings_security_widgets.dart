part of '../settings_screen.dart';

String _localizedPgpExpiration(
  AppLocalizations localizations,
  PgpSessionExpiration expiration,
) {
  return switch (expiration) {
    PgpSessionExpiration.immediately => localizations.immediately,
    PgpSessionExpiration.fiveMinutes => localizations.minutesShort(5),
    PgpSessionExpiration.fifteenMinutes => localizations.minutesShort(15),
    PgpSessionExpiration.oneHour => localizations.hoursShort(1),
    PgpSessionExpiration.untilAppExit => localizations.untilAppExit,
  };
}

extension _SettingsScreenSecuritySheets on SettingsScreen {
  void _showUnavailableSheet(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _UnavailableFeatureSheetBody(title: title),
    );
  }

  void _showRuntimeDiagnostics(BuildContext context) {
    final localizations = context.l10n;
    final diagnostics =
        _runtimeDiagnostics?.runtimeDiagnostics(securityRepository) ??
        RuntimeDiagnostics(
          bridgeLoaded: false,
          coreVersion: localizations.unavailable,
          pgpBackend: localizations.unavailable,
          gitBackend: localizations.unavailable,
          keyStorageBackend: keyStorageBackendLabel(securityRepository),
          nativeLibrary: localizations.unavailable,
        );
    showParsAdaptiveDetail<void>(
      context: context,
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
    final recipients =
        settingsRepository.store?.pgpRecipients ?? const <String>[];
    final privatePgpKeys = keyRepository.keys
        .where(
          (key) =>
              key.type == KeyRecordType.pgp &&
              key.hasPrivateKey &&
              key.hasLocalKeyMaterial &&
              pgpIdentityMatchesAnyRecipient(
                fingerprint: key.fingerprint,
                identity: key.name,
                recipients: recipients,
              ),
        )
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => _PgpPassphraseStorageSheetBody(
            securityRepository: securityRepository,
            keyRepository: keyRepository,
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
            Text(context.l10n.featureUnavailableDescription),
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
                context.l10n.runtimeDiagnosticsTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _DiagnosticRow(
                label: context.l10n.bridgeLoadedLabel,
                value:
                    diagnostics.bridgeLoaded
                        ? context.l10n.yes
                        : context.l10n.no,
              ),
              _DiagnosticRow(
                label: context.l10n.coreVersionLabel,
                value: diagnostics.coreVersion,
              ),
              _DiagnosticRow(
                label: context.l10n.nativeLibraryLabel,
                value: diagnostics.nativeLibrary,
              ),
              _DiagnosticRow(
                label: context.l10n.pgpBackendLabel,
                value: diagnostics.pgpBackend,
              ),
              _DiagnosticRow(
                label: context.l10n.gitBackendLabel,
                value: diagnostics.gitBackend,
              ),
              _DiagnosticRow(
                label: context.l10n.keyStorageBackendLabel,
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
          widget.onNotify(context.l10n.gestureConfirmed);
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
              context.l10n.gestureBiometricsTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _isChangingGesture = true),
              icon: const Icon(Icons.pattern),
              label: Text(context.l10n.changeGesture),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.requireUnlockOnResume),
              subtitle: Text(context.l10n.gestureFallbackDescription),
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
                  title: Text(context.l10n.biometricUnlock),
                  subtitle: Text(_biometricSubtitle(context.l10n, status)),
                  value:
                      status == BiometricUnlockStatus.available &&
                      widget.securityRepository.biometricUnlockEnabled,
                  onChanged:
                      status == BiometricUnlockStatus.unavailable
                          ? null
                          : (value) async {
                            final localizations = context.l10n;
                            try {
                              await widget.runDuringSystemAuthentication(
                                () => widget.securityRepository
                                    .setBiometricUnlockEnabled(value),
                              );
                              widget.onSecuritySettingsChanged?.call();
                            } catch (error) {
                              final message =
                                  UiProblem.fromError(
                                    localizations,
                                    error,
                                  ).summary;
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
              context.l10n.autoLockTimeout,
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
                    label: Text(_timeoutLabel(context.l10n, timeout)),
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
              label: Text(context.l10n.resetOnboarding),
            ),
          ],
        ),
      ),
    );
  }

  String _timeoutLabel(AppLocalizations localizations, Duration timeout) {
    if (timeout <= Duration.zero) return localizations.never;
    if (timeout.inMinutes < 60) {
      return localizations.minutesShort(timeout.inMinutes);
    }
    return localizations.hoursShort(timeout.inHours);
  }

  String _biometricSubtitle(
    AppLocalizations localizations,
    BiometricUnlockStatus status,
  ) {
    switch (status) {
      case BiometricUnlockStatus.available:
        return localizations.enabledOnDevice;
      case BiometricUnlockStatus.disabled:
        return localizations.availableOnDevice;
      case BiometricUnlockStatus.unavailable:
        return localizations.unavailableOnDevice;
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
                context.l10n.changeGesture,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(context.l10n.drawConfirmGesture),
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
              context.l10n.pgpSessionTimeoutTitle,
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
                    label: Text(
                      _localizedPgpExpiration(context.l10n, expiration),
                    ),
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
    required this.keyRepository,
    required this.privatePgpKeys,
    required this.entries,
    this.autofillRepository,
    this.onSecuritySettingsChanged,
  });

  final SecurityRepository securityRepository;
  final KeyRepository keyRepository;
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
              context.l10n.keychainPassphraseTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.storePgpPassphrase),
              subtitle: Text(context.l10n.savedInSecureStorage),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key_off_outlined),
                title: Text(context.l10n.noPrivatePgpKeys),
                subtitle: Text(context.l10n.createPrivatePgpKeyFirst),
              )
            else
              DropdownButtonFormField<String>(
                key: const Key('pgp-passphrase-key-dropdown'),
                initialValue: _selectedFingerprint,
                decoration: InputDecoration(labelText: context.l10n.pgpKey),
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
                        ? context.l10n.replaceCachedPassphrase
                        : context.l10n.pgpPassphraseLabel,
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
                            final keyMismatchMessage =
                                context.l10n.pgpKeyDoesNotMatchStore;
                            try {
                              final selectedFingerprint = _selectedFingerprint!;
                              final prepared = await widget.keyRepository
                                  .preparePgpPrivateKey(
                                    fingerprint: selectedFingerprint,
                                    passphrase: _passphrase.text,
                                  );
                              if (prepared.fingerprint
                                      .replaceAll(' ', '')
                                      .toUpperCase() !=
                                  selectedFingerprint
                                      .replaceAll(' ', '')
                                      .toUpperCase()) {
                                throw StateError(keyMismatchMessage);
                              }
                              await widget.securityRepository.savePgpPassphrase(
                                fingerprint: selectedFingerprint,
                                passphrase: _passphrase.text,
                              );
                              await widget.autofillRepository
                                  ?.publishPlatformState();
                              _passphrase.clear();
                              widget.onSecuritySettingsChanged?.call();
                              setState(() {});
                            } catch (error) {
                              if (!context.mounted) return;
                              AppNotification.show(
                                context,
                                UiProblem.fromError(
                                  context.l10n,
                                  error,
                                ).summary,
                                severity: AppNotificationSeverity.error,
                              );
                            }
                          }
                          : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(context.l10n.save),
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
                  label: Text(context.l10n.clear),
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
                      ? context.l10n.noCachedPassphrase
                      : context.l10n.cachedForKey(
                        cachedKey?.name ?? cached.fingerprint,
                      ),
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
