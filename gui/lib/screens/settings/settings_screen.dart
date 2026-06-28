import 'package:flutter/material.dart';

import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/path_picker_service.dart';
import '../../services/runtime_diagnostics.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../widgets/app_notification.dart';
import '../../widgets/gesture_setup_panel.dart';
import '../../widgets/path_picker_row.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
    required this.securityRepository,
    this.pathPickerService = const SystemPathPickerService(),
    this.onSecuritySettingsChanged,
    this.runDuringSystemAuthentication,
    this.onOnboardingReset,
  });

  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final PathPickerService pathPickerService;
  final VoidCallback? onSecuritySettingsChanged;
  final Future<T> Function<T>(Future<T> Function() action)?
  runDuringSystemAuthentication;
  final VoidCallback? onOnboardingReset;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: <Widget>[
              _SettingsSection(
                title: 'Security',
                children: <Widget>[
                  _SettingsTile(
                    title: 'Gesture lock and biometrics',
                    subtitle:
                        securityRepository.lockOnResume
                            ? 'Lock on app resume'
                            : 'Gesture unlock configured',
                    icon: Icons.pattern,
                    onTap: () => _showSecuritySheet(context),
                  ),
                  _SettingsTile(
                    title: 'PGP session timeout',
                    subtitle: securityRepository.pgpSessionExpiration.label,
                    icon: Icons.timer_outlined,
                    onTap: () => _showPgpSessionTimeoutSheet(context),
                  ),
                  _SettingsTile(
                    title: 'KMS / Keychain passphrase',
                    subtitle:
                        securityRepository.hasStoredPgpPassphrase
                            ? 'PGP passphrase cached'
                            : 'Optional encrypted passphrase cache',
                    icon: Icons.key_outlined,
                    onTap: () => _showPgpPassphraseStorageSheet(context),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Key management',
                children: <Widget>[
                  _SettingsTile(
                    title: 'PGP keys',
                    subtitle: 'Create, import, export, delete',
                    icon: Icons.enhanced_encryption_outlined,
                    onTap: () => _showKeys(context, KeyRecordType.pgp),
                  ),
                  _SettingsTile(
                    title: 'SSH keys',
                    subtitle: 'GitHub access keys',
                    icon: Icons.vpn_key_outlined,
                    onTap: () => _showKeys(context, KeyRecordType.ssh),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Password stores and Git',
                children: <Widget>[
                  _SettingsTile(
                    title: 'Password stores',
                    subtitle: settingsRepository.currentRepoName,
                    icon: Icons.folder_outlined,
                    onTap: () => _showPasswordStores(context),
                  ),
                  _SettingsTile(
                    title: 'Git sync and remotes',
                    subtitle: 'Pull, push, status, remotes',
                    icon: Icons.sync,
                    onTap: () => _showGitSync(context),
                  ),
                  _SettingsTile(
                    title: 'Advanced git args',
                    subtitle: 'Arguments after git only',
                    icon: Icons.terminal,
                    onTap: () => _showGitArgs(context),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Platform',
                children: <Widget>[
                  _SettingsTile(
                    title: 'Runtime diagnostics',
                    subtitle: 'Bridge, core, crypto, Git, key storage',
                    icon: Icons.health_and_safety_outlined,
                    onTap: () => _showRuntimeDiagnostics(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  GitOperationsRepository? get _gitOperations =>
      gitRepository is GitOperationsRepository
          ? gitRepository as GitOperationsRepository
          : null;

  RuntimeDiagnosticsRepository? get _runtimeDiagnostics =>
      settingsRepository is RuntimeDiagnosticsRepository
          ? settingsRepository as RuntimeDiagnosticsRepository
          : null;

  void _showTextSheet(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This configuration surface is mocked in phase 1 and will be wired to platform services later.',
                  ),
                ],
              ),
            ),
          ),
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
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Runtime diagnostics',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
          ),
    );
  }

  void _showSecuritySheet(BuildContext context) {
    final rootContext = context;
    var isChangingGesture = false;
    final timeoutOptions = <Duration>[
      Duration.zero,
      const Duration(minutes: 1),
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(hours: 1),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSheetState) {
              if (isChangingGesture) {
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
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Draw and confirm a new local unlock gesture.',
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: GestureSetupPanel(
                              securityRepository: securityRepository,
                              onSaved: () {
                                onSecuritySettingsChanged?.call();
                                setSheetState(() => isChangingGesture = false);
                                AppNotification.show(
                                  rootContext,
                                  'Gesture updated',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            () => setSheetState(() => isChangingGesture = true),
                        icon: const Icon(Icons.pattern),
                        label: const Text('Change gesture'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Require unlock on app resume'),
                        subtitle: const Text(
                          'Gesture unlock is used as fallback',
                        ),
                        value: securityRepository.lockOnResume,
                        onChanged: (value) async {
                          await securityRepository.setLockOnResume(value);
                          onSecuritySettingsChanged?.call();
                          setSheetState(() {});
                        },
                      ),
                      FutureBuilder<BiometricUnlockStatus>(
                        future: securityRepository.biometricUnlockStatus(),
                        builder: (context, snapshot) {
                          final status =
                              snapshot.data ??
                              BiometricUnlockStatus.unavailable;
                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Biometric unlock'),
                            subtitle: Text(_biometricSubtitle(status)),
                            value:
                                status == BiometricUnlockStatus.available &&
                                securityRepository.biometricUnlockEnabled,
                            onChanged:
                                status == BiometricUnlockStatus.unavailable
                                    ? null
                                    : (value) async {
                                      try {
                                        await _runDuringSystemAuthentication(
                                          () => securityRepository
                                              .setBiometricUnlockEnabled(value),
                                        );
                                        onSecuritySettingsChanged?.call();
                                      } catch (error) {
                                        if (rootContext.mounted) {
                                          final message =
                                              error is StateError
                                                  ? error.message
                                                  : '$error';
                                          AppNotification.show(
                                            rootContext,
                                            message,
                                          );
                                        }
                                      }
                                      setSheetState(() {});
                                    },
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Auto-lock timeout',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final timeout in timeoutOptions)
                            ChoiceChip(
                              label: Text(_timeoutLabel(timeout)),
                              selected:
                                  securityRepository.autoLockTimeout == timeout,
                              onSelected: (_) async {
                                await securityRepository.setAutoLockTimeout(
                                  timeout,
                                );
                                onSecuritySettingsChanged?.call();
                                setSheetState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await securityRepository.setOnboardingComplete(false);
                          onOnboardingReset?.call();
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
            },
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

  Future<T> _runDuringSystemAuthentication<T>(
    Future<T> Function() action,
  ) async {
    final runner = runDuringSystemAuthentication;
    if (runner == null) {
      return action();
    }
    return runner(action);
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

  void _showPgpSessionTimeoutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'PGP session timeout',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final expiration
                                in PgpSessionExpiration.values)
                              ChoiceChip(
                                label: Text(expiration.label),
                                selected:
                                    securityRepository.pgpSessionExpiration ==
                                    expiration,
                                onSelected: (_) async {
                                  await securityRepository
                                      .setPgpSessionExpiration(expiration);
                                  onSecuritySettingsChanged?.call();
                                  setSheetState(() {});
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _showPgpPassphraseStorageSheet(BuildContext context) {
    final passphrase = TextEditingController();
    final privatePgpKeys = keyRepository.keys
        .where((key) => key.type == KeyRecordType.pgp && key.hasPrivateKey)
        .toList(growable: false);
    String? selectedFingerprint =
        privatePgpKeys.isEmpty ? null : privatePgpKeys.first.fingerprint;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => SafeArea(
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
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Store PGP passphrase'),
                          subtitle: const Text(
                            'Saved in the platform secure storage provider',
                          ),
                          value: securityRepository.pgpPassphraseStorageEnabled,
                          onChanged: (value) async {
                            await securityRepository
                                .setPgpPassphraseStorageEnabled(value);
                            onSecuritySettingsChanged?.call();
                            setSheetState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        if (privatePgpKeys.isEmpty)
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
                            initialValue: selectedFingerprint,
                            decoration: const InputDecoration(
                              labelText: 'PGP key',
                            ),
                            items: privatePgpKeys
                                .map(
                                  (key) => DropdownMenuItem<String>(
                                    value: key.fingerprint,
                                    child: Text(key.name),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged:
                                securityRepository.pgpPassphraseStorageEnabled
                                    ? (value) {
                                      setSheetState(() {
                                        selectedFingerprint = value;
                                      });
                                    }
                                    : null,
                          ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: passphrase,
                          enabled:
                              securityRepository.pgpPassphraseStorageEnabled,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText:
                                securityRepository.hasStoredPgpPassphrase
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
                                  securityRepository
                                              .pgpPassphraseStorageEnabled &&
                                          selectedFingerprint != null
                                      ? () async {
                                        try {
                                          await securityRepository
                                              .savePgpPassphrase(
                                                fingerprint:
                                                    selectedFingerprint!,
                                                passphrase: passphrase.text,
                                              );
                                          passphrase.clear();
                                          onSecuritySettingsChanged?.call();
                                          setSheetState(() {});
                                        } catch (error) {
                                          if (!context.mounted) return;
                                          AppNotification.show(
                                            context,
                                            error.toString(),
                                          );
                                        }
                                      }
                                      : null,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Save'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  securityRepository.hasStoredPgpPassphrase
                                      ? () async {
                                        await securityRepository
                                            .clearPgpPassphrase();
                                        onSecuritySettingsChanged?.call();
                                        setSheetState(() {});
                                      }
                                      : null,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Clear'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<PgpPassphraseCache?>(
                          future: securityRepository.readPgpPassphrase(),
                          builder: (context, snapshot) {
                            final cached = snapshot.data;
                            final cachedKey =
                                cached == null
                                    ? null
                                    : _keyForFingerprint(
                                      privatePgpKeys,
                                      cached.fingerprint,
                                    );
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
                ),
          ),
    );
  }

  void _showKeys(BuildContext context, KeyRecordType type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSheetState) {
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
                          type == KeyRecordType.pgp ? 'PGP keys' : 'SSH keys',
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
                                  ? 'No PGP keys'
                                  : 'No SSH keys',
                            ),
                            subtitle: const Text('Create or import a key.'),
                          ),
                        for (final key in keys)
                          Card(
                            child: ListTile(
                              title: Text(key.name),
                              subtitle: Text(
                                '${key.fingerprint}\n${key.source}\n${key.hasPrivateKey ? 'Private' : 'Public'}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                tooltip:
                                    'Actions for ${key.typeLabel} key ${key.name}',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'export_public':
                                      _exportPublicKey(context, key);
                                      break;
                                    case 'export_private':
                                      _showPrivateExportForm(context, key);
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
                                    (context) => _keyActionMenuItems(key.type),
                              ),
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
                              child: const Text('Create'),
                            ),
                            OutlinedButton(
                              onPressed:
                                  () => _showImportKeyOptions(context, type),
                              child: const Text('Import'),
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

  List<PopupMenuEntry<String>> _keyActionMenuItems(KeyRecordType type) {
    return <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'export_public',
        child: Text('Export public'),
      ),
      const PopupMenuItem<String>(
        value: 'export_private',
        child: Text('Export private'),
      ),
      if (type == KeyRecordType.pgp)
        const PopupMenuItem<String>(
          value: 'add_to_store',
          child: Text('Add to .gpg-id'),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(value: 'delete', child: Text('Delete key')),
    ];
  }

  void _showDeleteKeyDialog(
    BuildContext sheetContext,
    KeyRecord key,
    StateSetter setSheetState,
  ) {
    final confirmation = TextEditingController();
    final requiredText =
        key.type == KeyRecordType.pgp ? key.fingerprint : key.name;
    showDialog<void>(
      context: sheetContext,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: Text('Delete ${key.typeLabel} key'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(key.name),
                      const SizedBox(height: 8),
                      Text(
                        'This removes local key material from this device. Type $requiredText to delete this key.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmation,
                        decoration: const InputDecoration(
                          labelText: 'Confirmation',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          confirmation.text == requiredText
                              ? () async {
                                try {
                                  if (key.type == KeyRecordType.pgp) {
                                    await keyRepository.deletePgpKey(
                                      key.fingerprint,
                                    );
                                    await securityRepository
                                        .clearPgpPassphraseForFingerprint(
                                          key.fingerprint,
                                        );
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
                                    'Deleted ${key.name}',
                                  );
                                } catch (error) {
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  setSheetState(() {});
                                  if (!sheetContext.mounted) return;
                                  AppNotification.show(
                                    sheetContext,
                                    error.toString(),
                                  );
                                }
                              }
                              : null,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
          ),
    );
  }

  KeyRecord? _keyForFingerprint(List<KeyRecord> keys, String fingerprint) {
    for (final key in keys) {
      if (key.fingerprint == fingerprint) {
        return key;
      }
    }
    return null;
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
              type == KeyRecordType.pgp ? 'Create PGP key' : 'Create SSH key',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                if (type == KeyRecordType.pgp)
                  TextField(
                    controller: passphrase,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
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
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  void _showImportKeyOptions(BuildContext context, KeyRecordType type) {
    final sheetContext = context;
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(
              type == KeyRecordType.pgp ? 'Import PGP key' : 'Import SSH key',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportKeyForm(sheetContext, type);
                },
                child: const Text('Text'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showImportKeyFileForm(sheetContext, type);
                },
                child: const Text('File'),
              ),
            ],
          ),
    );
  }

  void _showImportKeyForm(BuildContext context, KeyRecordType type) {
    final name = TextEditingController();
    final keyText = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              type == KeyRecordType.pgp ? 'Import PGP key' : 'Import SSH key',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (type == KeyRecordType.ssh)
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                TextField(
                  controller: keyText,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Key text'),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _runKeyAction(context, () async {
                      try {
                        if (type == KeyRecordType.ssh) {
                          return await keyRepository.importSshPrivateKeyText(
                            name: name.text,
                            privateKey: keyText.text,
                          );
                        }
                        if (keyText.text.contains('PGP PRIVATE KEY BLOCK')) {
                          return await keyRepository.importPgpPrivateKeyText(
                            keyText.text,
                          );
                        }
                        return await keyRepository.importPgpPublicKeyText(
                          keyText.text,
                        );
                      } finally {
                        keyText.clear();
                      }
                    }),
                child: const Text('Import'),
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
      AppNotification.show(context, '$error');
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
      AppNotification.show(context, '$error');
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
                  title: Text(
                    type == KeyRecordType.pgp
                        ? 'Import PGP key file'
                        : 'Import SSH key file',
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (type == KeyRecordType.ssh)
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                      if (type == KeyRecordType.ssh) const SizedBox(height: 12),
                      PathPickerRow(
                        title: 'Key file',
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
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          selectedPath == null
                              ? null
                              : () => _runKeyAction(
                                context,
                                () =>
                                    type == KeyRecordType.pgp
                                        ? keyRepository.importPgpPrivateKeyFile(
                                          selectedPath!,
                                        )
                                        : keyRepository.importSshPrivateKeyFile(
                                          name: name.text,
                                          path: selectedPath!,
                                        ),
                              ),
                      child: const Text('Import'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showPrivateExportForm(BuildContext context, KeyRecord key) {
    final confirmation = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Export private key'),
            content: TextField(
              controller: confirmation,
              decoration: const InputDecoration(labelText: 'Confirmation'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => _showExportedText(
                      context,
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
                    ),
                child: const Text('Export'),
              ),
            ],
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
      AppNotification.show(context, error.toString());
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
              title: const Text('Exported key'),
              content: SelectableText(text),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(context, error.toString());
    }
  }

  Future<void> _addPgpKeyToStore(BuildContext context, KeyRecord key) async {
    try {
      await keyRepository.addPgpKeyToSelectedStore(key.fingerprint);
      if (!context.mounted) return;
      AppNotification.show(context, key.fingerprint);
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(context, error.toString());
    }
  }

  void _showPasswordStores(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Password stores',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(settingsRepository.lifecycle.onboardingState.label),
                    const SizedBox(height: 12),
                    if (settingsRepository.stores.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.folder_off_outlined),
                        title: Text('No password stores'),
                        subtitle: Text('Create, import, or clone a store.'),
                      ),
                    for (final store in settingsRepository.stores)
                      Card(
                        child: ListTile(
                          title: Text(store.name),
                          subtitle: Text(
                            '${store.root}\n${store.issues.isEmpty ? 'Ready' : store.issues.join(', ')}',
                          ),
                          isThreeLine: true,
                          leading: Icon(
                            store.isDefault
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected:
                                (value) => _handleStoreMenu(
                                  context,
                                  action: value,
                                  root: store.root,
                                ),
                            itemBuilder:
                                (context) => const <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'select',
                                    child: Text('Select'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Text('Remove from app'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('Delete local store'),
                                  ),
                                ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: () => _showCreateStoreForm(context),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Create'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showImportStoreForm(context),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Import'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showCloneStoreForm(context),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Clone'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _handleStoreMenu(
    BuildContext context, {
    required String action,
    required String root,
  }) {
    switch (action) {
      case 'select':
        _runStoreAction(context, () => settingsRepository.selectStore(root));
        break;
      case 'remove':
        _runStoreAction(
          context,
          () => settingsRepository.removeStore(root: root),
        );
        break;
      case 'delete':
        _showDeleteStoreForm(context, root);
        break;
    }
  }

  void _showCreateStoreForm(BuildContext context) {
    final name = TextEditingController(text: 'Personal');
    final keys = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Create local store',
      submitLabel: 'Create',
      canSubmit: () => selectedBase != null,
      onSubmit:
          () => settingsRepository.createLocalStore(
            name: name.text,
            root: joinFilesystemPath(selectedBase!, slugPathSegment(name.text)),
            pgpKeys: keys.text
                .split(',')
                .map((key) => key.trim())
                .where((key) => key.isNotEmpty)
                .toList(growable: false),
            setDefault: true,
            initializeGit: true,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: 12),
            PathPickerRow(
              title: 'Store folder',
              path: joinFilesystemPath(
                selectedBase ?? defaultBase,
                slugPathSegment(name.text),
              ),
              isSelected: selectedBase != null,
              onPressed:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedBase = path;
                        }),
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keys,
              decoration: const InputDecoration(labelText: 'PGP keys'),
            ),
          ],
    );
  }

  void _showImportStoreForm(BuildContext context) {
    final defaultBase = _defaultStoreBasePath();
    String? selectedRoot;
    _showPickerStoreForm(
      context: context,
      title: 'Import local store',
      submitLabel: 'Import',
      canSubmit: () => selectedRoot != null,
      onSubmit:
          () => settingsRepository.importLocalStore(
            root: selectedRoot!,
            setDefault: true,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            PathPickerRow(
              title: 'Store folder',
              path: selectedRoot ?? defaultBase,
              isSelected: selectedRoot != null,
              onPressed:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedRoot = path;
                        }),
                  ),
            ),
          ],
    );
  }

  void _showCloneStoreForm(BuildContext context) {
    final remote = TextEditingController();
    final defaultBase = _defaultStoreBasePath();
    String? selectedBase;
    _showPickerStoreForm(
      context: context,
      title: 'Clone Git store',
      submitLabel: 'Clone',
      canSubmit: () => selectedBase != null,
      onSubmit:
          () => settingsRepository.cloneStore(
            remoteUrl: remote.text,
            root: joinFilesystemPath(
              selectedBase!,
              slugFromRemoteUrl(remote.text),
            ),
            setDefault: true,
          ),
      builder:
          (sheetContext, setSheetState) => <Widget>[
            TextField(
              controller: remote,
              decoration: const InputDecoration(labelText: 'Remote URL'),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: 12),
            PathPickerRow(
              title: 'Store folder',
              path: joinFilesystemPath(
                selectedBase ?? defaultBase,
                slugFromRemoteUrl(remote.text),
              ),
              isSelected: selectedBase != null,
              onPressed:
                  () => _chooseFolder(
                    sheetContext,
                    initialDirectory: defaultBase,
                    onSelected:
                        (path) => setSheetState(() {
                          selectedBase = path;
                        }),
                  ),
            ),
          ],
    );
  }

  void _showPickerStoreForm({
    required BuildContext context,
    required String title,
    required String submitLabel,
    required bool Function() canSubmit,
    required List<Widget> Function(BuildContext, StateSetter) builder,
    required Future<void> Function() onSubmit,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => SafeArea(
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
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        ...builder(context, setSheetState),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed:
                              canSubmit()
                                  ? () async {
                                    await _runStoreAction(context, onSubmit);
                                  }
                                  : null,
                          child: SizedBox(
                            width: double.infinity,
                            child: Center(child: Text(submitLabel)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _showDeleteStoreForm(BuildContext context, String root) {
    final confirmation = TextEditingController();
    _showStoreForm(
      context: context,
      title: 'Delete local store',
      fields: <Widget>[
        Text(root),
        TextField(
          controller: confirmation,
          decoration: const InputDecoration(
            labelText: 'Type full path to confirm',
          ),
        ),
      ],
      submitLabel: 'Delete',
      onSubmit:
          () => settingsRepository.deleteLocalStore(
            root: root,
            confirmation: confirmation.text,
          ),
    );
  }

  void _showStoreForm({
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
          (context) => SafeArea(
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
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...fields,
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await _runStoreAction(context, onSubmit);
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(child: Text(submitLabel)),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _runStoreAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (context.mounted) {
        AppNotification.show(context, '$error');
      }
    }
  }

  void _showGitSync(BuildContext context) {
    final git = _gitOperations;
    if (git == null) {
      _showTextSheet(context, 'Git sync and remotes');
      return;
    }

    var message = 'Update password store';
    var remoteName = 'origin';
    var remoteUrl = '';
    var deleteConfirmation = '';
    var pushAfterCommit = false;
    var running = false;
    GitOperationResult? output;
    List<GitRemote> remotes = const <GitRemote>[];
    String? errorText;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> refreshRemotes() async {
                try {
                  final loaded = await git.listRemotes();
                  if (sheetContext.mounted) {
                    setSheetState(() => remotes = loaded);
                  }
                } catch (error) {
                  if (sheetContext.mounted) {
                    setSheetState(() => errorText = error.toString());
                  }
                }
              }

              Future<void> run(
                Future<GitOperationResult> Function() action,
              ) async {
                setSheetState(() {
                  running = true;
                  errorText = null;
                });
                try {
                  final result = await action();
                  if (sheetContext.mounted) {
                    setSheetState(() {
                      output = result;
                      running = false;
                    });
                  }
                } catch (error) {
                  if (sheetContext.mounted) {
                    setSheetState(() {
                      errorText = error.toString();
                      running = false;
                    });
                  }
                }
              }

              return SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      MediaQuery.of(context).viewInsets.bottom + 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Git sync and remotes',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Chip(label: Text(gitRepository.gitStatus.label)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed:
                                  running
                                      ? null
                                      : () => run(git.refreshGitStatus),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Status'),
                            ),
                            OutlinedButton.icon(
                              onPressed: running ? null : () => run(git.pull),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Pull'),
                            ),
                            OutlinedButton.icon(
                              onPressed: running ? null : () => run(git.push),
                              icon: const Icon(Icons.upload_outlined),
                              label: const Text('Push'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  running ? null : () => run(git.recoverByPull),
                              icon: const Icon(Icons.healing_outlined),
                              label: const Text('Recover pull'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Commit message',
                          ),
                          onChanged: (value) => message = value,
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: pushAfterCommit,
                          onChanged:
                              running
                                  ? null
                                  : (value) => setSheetState(
                                    () => pushAfterCommit = value ?? false,
                                  ),
                          title: const Text('Push after commit'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed:
                              running
                                  ? null
                                  : () => run(() async {
                                    final commit = await git.commit(message);
                                    if (!pushAfterCommit) {
                                      return commit;
                                    }
                                    final push = await git.push();
                                    return _combineGitOutput(commit, push);
                                  }),
                          icon: const Icon(Icons.add_task_outlined),
                          label: const Text('Commit'),
                        ),
                        const Divider(height: 28),
                        _RemoteList(remotes: remotes),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: running ? null : refreshRemotes,
                              icon: const Icon(Icons.list_alt_outlined),
                              label: const Text('List remotes'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Remote name',
                          ),
                          onChanged: (value) => remoteName = value,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Remote URL',
                          ),
                          onChanged: (value) => remoteUrl = value,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton(
                              onPressed:
                                  running
                                      ? null
                                      : () => run(
                                        () => git.addRemote(
                                          name: remoteName,
                                          url: remoteUrl,
                                        ),
                                      ),
                              child: const Text('Add remote'),
                            ),
                            OutlinedButton(
                              onPressed:
                                  running
                                      ? null
                                      : () => run(
                                        () => git.editRemote(
                                          name: remoteName,
                                          url: remoteUrl,
                                        ),
                                      ),
                              child: const Text('Update remote'),
                            ),
                            OutlinedButton(
                              onPressed:
                                  running
                                      ? null
                                      : () => run(
                                        () => git.removeRemote(remoteName),
                                      ),
                              child: const Text('Remove remote'),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Delete confirmation',
                          ),
                          onChanged: (value) => deleteConfirmation = value,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed:
                              running
                                  ? null
                                  : () => run(
                                    () => git.deleteLocalRepo(
                                      confirmation: deleteConfirmation,
                                    ),
                                  ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete local repo'),
                        ),
                        if (running) ...const <Widget>[
                          SizedBox(height: 12),
                          LinearProgressIndicator(),
                        ],
                        if (errorText != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (output != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _GitOutputPanel(output: output!),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  void _showGitArgs(BuildContext context) {
    final git = _gitOperations;
    var argsText = '';
    var running = false;
    GitOperationResult? output;
    String? errorText;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> run() async {
                if (git == null) {
                  setSheetState(
                    () => errorText = 'Git operations are not available.',
                  );
                  return;
                }
                if (argsText.trim().isEmpty) {
                  setSheetState(
                    () => errorText = 'Enter at least one Git argument.',
                  );
                  return;
                }
                setSheetState(() {
                  running = true;
                  errorText = null;
                });
                try {
                  final result = await git.runArgs(_parseGitArgs(argsText));
                  if (sheetContext.mounted) {
                    setSheetState(() {
                      output = result;
                      running = false;
                    });
                  }
                } catch (error) {
                  if (sheetContext.mounted) {
                    setSheetState(() {
                      errorText = error.toString();
                      running = false;
                    });
                  }
                }
              }

              return SafeArea(
                child: SingleChildScrollView(
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
                          'Advanced git args',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Only enter arguments after git. Shell syntax is not accepted.',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            const Text(
                              'git',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: argsText,
                                decoration: const InputDecoration(
                                  hintText: 'status, log',
                                ),
                                onChanged: (value) {
                                  argsText = value;
                                  setSheetState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText('git ${argsText.trim()}'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: running ? null : run,
                          child: const SizedBox(
                            width: double.infinity,
                            child: Center(child: Text('Run selected command')),
                          ),
                        ),
                        if (running) ...const <Widget>[
                          SizedBox(height: 12),
                          LinearProgressIndicator(),
                        ],
                        if (errorText != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (output != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _GitOutputPanel(output: output!),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  List<String> _parseGitArgs(String value) {
    return value
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  GitOperationResult _combineGitOutput(
    GitOperationResult first,
    GitOperationResult second,
  ) {
    return GitOperationResult(
      command: '${first.command}\n${second.command}',
      stdout: '${first.stdout}${second.stdout}',
      stderr: '${first.stderr}${second.stderr}',
      exitCode: second.exitCode,
      success: first.success && second.success,
    );
  }
}

class _RemoteList extends StatelessWidget {
  const _RemoteList({required this.remotes});

  final List<GitRemote> remotes;

  @override
  Widget build(BuildContext context) {
    if (remotes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: remotes
          .map(
            (remote) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_queue_outlined),
              title: Text(remote.name),
              subtitle: Text('${remote.fetchUrl}\n${remote.pushUrl}'),
              isThreeLine: true,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _GitOutputPanel extends StatelessWidget {
  const _GitOutputPanel({required this.output});

  final GitOperationResult output;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(
              output.command,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Exit: ${output.exitCode ?? 'signal'}'),
            Text(output.success ? 'Success' : 'Failed'),
            if (output.stdout.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'stdout',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(output.stdout),
            ],
            if (output.stderr.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'stderr',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(output.stderr),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF64748B),
              letterSpacing: 0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
