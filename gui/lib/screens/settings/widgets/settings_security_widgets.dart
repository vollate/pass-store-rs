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
    showParsAdaptiveSurface<void>(
      context: context,
      title: title,
      builder:
          (context) => Text(context.l10n.featureUnavailableDescription),
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
    showParsAdaptiveSurface<void>(
      context: context,
      title: localizations.runtimeDiagnosticsTitle,
      builder:
          (context) => _RuntimeDiagnosticsSheetBody(diagnostics: diagnostics),
    );
  }

  void _showSecuritySheet(BuildContext context) {
    final rootContext = context;
    showParsAdaptiveDetail<void>(
      context: context,
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
    showParsAdaptiveSurface<void>(
      context: context,
      title: context.l10n.pgpSessionTimeoutTitle,
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
    showParsAdaptiveSurface<void>(
      context: context,
      title: context.l10n.keychainPassphraseTitle,
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

class _RuntimeDiagnosticsSheetBody extends StatelessWidget {
  const _RuntimeDiagnosticsSheetBody({required this.diagnostics});

  final RuntimeDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    return AppSectionBox(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _DiagnosticRow(
          icon: Icons.hub_outlined,
          label: context.l10n.bridgeLoadedLabel,
          value: diagnostics.bridgeLoaded ? context.l10n.yes : context.l10n.no,
        ),
        _DiagnosticRow(
          icon: Icons.info_outline,
          label: context.l10n.coreVersionLabel,
          value: diagnostics.coreVersion,
        ),
        _DiagnosticRow(
          icon: Icons.memory_outlined,
          label: context.l10n.nativeLibraryLabel,
          value: diagnostics.nativeLibrary,
        ),
        _DiagnosticRow(
          icon: Icons.enhanced_encryption_outlined,
          label: context.l10n.pgpBackendLabel,
          value: diagnostics.pgpBackend,
        ),
        _DiagnosticRow(
          icon: Icons.account_tree_outlined,
          label: context.l10n.gitBackendLabel,
          value: diagnostics.gitBackend,
        ),
        _DiagnosticRow(
          icon: Icons.key_outlined,
          label: context.l10n.keyStorageBackendLabel,
          value: diagnostics.keyStorageBackend,
        ),
      ],
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

  late Future<({BiometricUnlockStatus status, BiometricKind kind})>
  _biometricsFuture;

  @override
  void initState() {
    super.initState();
    _biometricsFuture = _loadBiometrics();
  }

  @override
  void didUpdateWidget(covariant _SecuritySettingsSheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.securityRepository != widget.securityRepository) {
      _biometricsFuture = _loadBiometrics();
    }
  }

  LocalUnlockMethod get _currentMethod =>
      widget.securityRepository.unlockMethod ?? platformDefaultUnlockMethod();

  Future<void> _openMethodEditor(LocalUnlockMethod method) async {
    final l10n = context.l10n;
    final saved = await switch (method) {
      LocalUnlockMethod.pin => showParsAdaptivePage<bool>(
        context: context,
        title: l10n.changePin,
        builder:
            (editorContext) => _PinChangeSheetBody(
              securityRepository: widget.securityRepository,
              onSaved: () {
                if (editorContext.mounted) {
                  Navigator.of(editorContext).pop(true);
                }
              },
            ),
      ),
      LocalUnlockMethod.password => showParsAdaptiveSurface<bool>(
        context: context,
        title: l10n.setAppPassword,
        builder:
            (editorContext) => _PasswordChangeSheetBody(
              securityRepository: widget.securityRepository,
              onSaved: () {
                if (editorContext.mounted) {
                  Navigator.of(editorContext).pop(true);
                }
              },
            ),
      ),
    };
    if (saved != true || !mounted) return;
    widget.onSecuritySettingsChanged?.call();
    setState(() {});
    widget.onNotify(
      method == LocalUnlockMethod.pin ? l10n.pinConfirmed : l10n.passwordSaved,
    );
  }

  Future<({BiometricUnlockStatus status, BiometricKind kind})>
  _loadBiometrics() async {
    final status = await widget.securityRepository.biometricUnlockStatus();
    final kind = await widget.securityRepository.biometricKind();
    return (status: status, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final usesPassword = _currentMethod == LocalUnlockMethod.password;
    return ParsAdaptiveSurface(
      title:
          usesPassword
              ? context.l10n.passwordBiometricsTitle
              : context.l10n.pinBiometricsTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ParsActionGroup(
            actions: <ParsActionItem>[
              ParsActionItem(
                label:
                    usesPassword
                        ? context.l10n.changePassword
                        : context.l10n.changePin,
                icon: usesPassword ? Icons.password : Icons.dialpad,
                onPressed: () => _openMethodEditor(_currentMethod),
              ),
              ParsActionItem(
                label:
                    usesPassword
                        ? context.l10n.usePinLock
                        : context.l10n.usePasswordLock,
                icon: usesPassword ? Icons.dialpad : Icons.password,
                onPressed:
                    () => _openMethodEditor(
                      usesPassword
                          ? LocalUnlockMethod.pin
                          : LocalUnlockMethod.password,
                    ),
              ),
            ],
          ),
          const SizedBox(height: ParsSpacing.md),
          FutureBuilder<({BiometricUnlockStatus status, BiometricKind kind})>(
            future: _biometricsFuture,
            builder: (context, snapshot) {
              final status =
                  snapshot.data?.status ?? BiometricUnlockStatus.unavailable;
              final biometricKind =
                  snapshot.data?.kind ?? BiometricKind.fingerprint;
              final biometricAvailable =
                  status != BiometricUnlockStatus.unavailable;
              final biometricValue =
                  status == BiometricUnlockStatus.available &&
                  widget.securityRepository.biometricUnlockEnabled;

              Future<void> toggleLockOnResume(bool value) async {
                await widget.securityRepository.setLockOnResume(value);
                widget.onSecuritySettingsChanged?.call();
                setState(() {});
              }

              Future<void> toggleBiometric(bool value) async {
                final localizations = context.l10n;
                try {
                  await widget.runDuringSystemAuthentication(
                    () => widget.securityRepository.setBiometricUnlockEnabled(
                      value,
                    ),
                  );
                  widget.onSecuritySettingsChanged?.call();
                } catch (error) {
                  final message =
                      UiProblem.fromError(localizations, error).summary;
                  widget.onNotify(message);
                }
                if (mounted) {
                  setState(() {
                    _biometricsFuture = _loadBiometrics();
                  });
                }
              }

              return AppSectionBox(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  ParsSectionRow(
                    leading: const ParsSectionRowIcon(
                      icon: Icons.lock_clock_outlined,
                    ),
                    title: context.l10n.requireUnlockOnResume,
                    subtitle:
                        usesPassword
                            ? context.l10n.passwordFallbackDescription
                            : context.l10n.pinFallbackDescription,
                    onTap:
                        () => toggleLockOnResume(
                          !widget.securityRepository.lockOnResume,
                        ),
                    trailing: Switch(
                      value: widget.securityRepository.lockOnResume,
                      onChanged: toggleLockOnResume,
                    ),
                  ),
                  ParsSectionRow(
                    leading: ParsSectionRowIcon.custom(
                      child: BiometricIcon(kind: biometricKind),
                    ),
                    title: context.l10n.biometricUnlock,
                    subtitle: _biometricSubtitle(context.l10n, status),
                    onTap:
                        biometricAvailable
                            ? () => toggleBiometric(!biometricValue)
                            : null,
                    trailing: Switch(
                      value: biometricValue,
                      onChanged: biometricAvailable ? toggleBiometric : null,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: ParsSpacing.md),
          Text(
            context.l10n.autoLockTimeout,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: ParsSpacing.xs),
          Wrap(
            spacing: ParsSpacing.xs,
            runSpacing: ParsSpacing.xs,
            children: <Widget>[
              for (final timeout in _timeoutOptions)
                ChoiceChip(
                  label: Text(_timeoutLabel(context.l10n, timeout)),
                  selected:
                      widget.securityRepository.autoLockTimeout == timeout,
                  onSelected: (_) async {
                    await widget.securityRepository.setAutoLockTimeout(timeout);
                    widget.onSecuritySettingsChanged?.call();
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: ParsSpacing.md),
          ParsButtonGrid(
            children: <Widget>[
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
        ],
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

class _PinChangeSheetBody extends StatelessWidget {
  const _PinChangeSheetBody({
    required this.securityRepository,
    required this.onSaved,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    final compact = context.parsWindowClass == ParsWindowClass.compact;
    final content = Padding(
      padding: const EdgeInsets.all(ParsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.l10n.enterConfirmPin),
          const SizedBox(height: ParsSpacing.sm),
          Expanded(
            child: PinSetupPanel(
              securityRepository: securityRepository,
              onSaved: onSaved,
            ),
          ),
        ],
      ),
    );
    if (compact) return content;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: content,
    );
  }
}

class _PasswordChangeSheetBody extends StatelessWidget {
  const _PasswordChangeSheetBody({
    required this.securityRepository,
    required this.onSaved,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.enterConfirmPassword),
        const SizedBox(height: ParsSpacing.md),
        PasswordSetupPanel(
          securityRepository: securityRepository,
          onSaved: onSaved,
        ),
      ],
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
    return Wrap(
      spacing: ParsSpacing.xs,
      runSpacing: ParsSpacing.xs,
      children: <Widget>[
        for (final expiration in PgpSessionExpiration.values)
          ChoiceChip(
            label: Text(_localizedPgpExpiration(context.l10n, expiration)),
            selected:
                widget.securityRepository.pgpSessionExpiration == expiration,
            onSelected: (_) async {
              await widget.securityRepository.setPgpSessionExpiration(
                expiration,
              );
              widget.onSecuritySettingsChanged?.call();
              setState(() {});
            },
          ),
      ],
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
    Future<void> toggleStorage(bool value) async {
      await widget.securityRepository.setPgpPassphraseStorageEnabled(value);
      if (!value) {
        await _dropEncryptedLoginAndUrlIndex();
      }
      widget.onSecuritySettingsChanged?.call();
      if (mounted) setState(() {});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSectionBox(
          padding: EdgeInsets.zero,
          children: <Widget>[
            ParsSectionRow(
              leading: const ParsSectionRowIcon(icon: Icons.key_outlined),
              title: context.l10n.storePgpPassphrase,
              subtitle: context.l10n.savedInSecureStorage,
              onTap:
                  () => toggleStorage(
                    !widget.securityRepository.pgpPassphraseStorageEnabled,
                  ),
              trailing: Switch(
                value: widget.securityRepository.pgpPassphraseStorageEnabled,
                onChanged: toggleStorage,
              ),
            ),
          ],
        ),
        const SizedBox(height: ParsSpacing.sm),
        if (widget.privatePgpKeys.isEmpty)
          AppSectionBox(
            padding: EdgeInsets.zero,
            children: <Widget>[
              ParsSectionRow(
                leading: const ParsSectionRowIcon(icon: Icons.key_off_outlined),
                title: context.l10n.noPrivatePgpKeys,
                subtitle: context.l10n.createPrivatePgpKeyFirst,
              ),
            ],
          )
        else
              DropdownButtonFormField<String>(
                key: const Key('pgp-passphrase-key-dropdown'),
                initialValue: _selectedFingerprint,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.l10n.pgpKey),
                items: widget.privatePgpKeys
                    .map(
                      (key) => DropdownMenuItem<String>(
                        value: key.fingerprint,
                        child: Text(
                          key.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
            const SizedBox(height: ParsSpacing.xs),
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
            const SizedBox(height: ParsSpacing.sm),
            ParsButtonGrid(
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
            const SizedBox(height: ParsSpacing.sm),
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
    );
  }

  /// Enrichment can no longer be refreshed once the durable passphrase is
  /// gone, so its decrypted metadata is dropped and the index falls back to
  /// path-derived records, which never require a passphrase.
  Future<void> _dropEncryptedLoginAndUrlIndex() async {
    final repository = widget.autofillRepository;
    if (repository == null) return;
    try {
      await repository.forgetEncryptedLoginAndUrls();
      await repository.rebuildIndex(widget.entries);
    } catch (error) {
      repository.recordSyncFailure(error);
      if (!mounted) return;
      AppNotification.show(
        context,
        UiProblem.fromError(context.l10n, error).summary,
        severity: AppNotificationSeverity.error,
      );
    }
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
