import 'package:flutter/material.dart';

import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../services/autofill_repository.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/path_picker_service.dart';
import '../../services/pgp_import_service.dart';
import '../../services/runtime_diagnostics.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';
import '../../widgets/gesture_setup_panel.dart';
import '../../widgets/path_picker_row.dart';
import '../../widgets/pgp_key_import_body.dart';

part 'widgets/settings_security_widgets.dart';
part 'widgets/settings_key_management_widgets.dart';
part 'widgets/settings_store_widgets.dart';
part 'widgets/settings_git_widgets.dart';
part 'widgets/settings_autofill_widgets.dart';
part 'widgets/settings_sections.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
    required this.securityRepository,
    this.autofillRepository,
    this.vaultRepository,
    this.pathPickerService = const SystemPathPickerService(),
    this.onSecuritySettingsChanged,
    this.runDuringSystemAuthentication,
    this.onOnboardingReset,
  });

  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final AutofillRepository? autofillRepository;
  final VaultRepository? vaultRepository;
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
                    title: 'System autofill',
                    subtitle: _autofillSubtitle,
                    icon: Icons.password_outlined,
                    onTap: () => _showAutofill(context),
                  ),
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

  String get _autofillSubtitle {
    final repository = autofillRepository;
    if (repository == null) {
      return 'Unavailable';
    }
    final status = repository.status;
    if (status.available) {
      return '${status.indexedEntries} entries indexed';
    }
    return status.message ?? 'Not refreshed';
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
