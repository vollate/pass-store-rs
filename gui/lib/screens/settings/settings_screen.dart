import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../services/autofill_repository.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/path_picker_service.dart';
import '../../services/runtime_diagnostics.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/store_lifecycle.dart';
import '../../services/ui_preferences_store.dart';
import '../../services/ui_problem.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';
import '../../widgets/gesture_setup_panel.dart';
import '../../widgets/path_picker_row.dart';
import '../../widgets/pars_adaptive_surface.dart';

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
    this.localePreference = AppLocalePreference.system,
    this.scrollController,
    this.onLocalePreferenceChanged,
    this.onSecuritySettingsChanged,
    this.runDuringSystemAuthentication,
    this.onStoreLifecycleChanged,
    this.onOnboardingReset,
  });

  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final AutofillRepository? autofillRepository;
  final VaultRepository? vaultRepository;
  final PathPickerService pathPickerService;
  final AppLocalePreference localePreference;
  final ScrollController? scrollController;
  final Future<void> Function(AppLocalePreference preference)?
  onLocalePreferenceChanged;
  final VoidCallback? onSecuritySettingsChanged;
  final Future<T> Function<T>(Future<T> Function() action)?
  runDuringSystemAuthentication;
  final Future<void> Function()? onStoreLifecycleChanged;
  final VoidCallback? onOnboardingReset;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    return CustomScrollView(
      controller: scrollController,
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(
            localizations.settingsTitle,
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
                title: localizations.appearanceSection,
                children: <Widget>[
                  _SettingsTile(
                    title: localizations.languageTitle,
                    subtitle: _localeLabel(localizations, localePreference),
                    icon: Icons.language,
                    onTap: () => _showLanguage(context),
                  ),
                ],
              ),
              _SettingsSection(
                title: localizations.securityPrivacySection,
                children: <Widget>[
                  _SettingsTile(
                    title: localizations.gestureBiometricsTitle,
                    subtitle:
                        securityRepository.lockOnResume
                            ? localizations.lockOnResumeState
                            : localizations.gestureConfiguredState,
                    icon: Icons.pattern,
                    onTap: () => _showSecuritySheet(context),
                  ),
                  _SettingsTile(
                    title: localizations.pgpSessionTimeoutTitle,
                    subtitle: _localizedPgpExpiration(
                      localizations,
                      securityRepository.pgpSessionExpiration,
                    ),
                    icon: Icons.timer_outlined,
                    onTap: () => _showPgpSessionTimeoutSheet(context),
                  ),
                  _SettingsTile(
                    title: localizations.keychainPassphraseTitle,
                    subtitle:
                        securityRepository.hasStoredPgpPassphrase
                            ? localizations.pgpPassphraseCachedState
                            : localizations.optionalPassphraseCacheState,
                    icon: Icons.key_outlined,
                    onTap: () => _showPgpPassphraseStorageSheet(context),
                  ),
                ],
              ),
              _SettingsSection(
                title: localizations.vaultSyncSection,
                children: <Widget>[
                  _SettingsTile(
                    title: localizations.passwordStore,
                    subtitle: _passwordStoreSubtitle(localizations),
                    icon: Icons.folder_outlined,
                    onTap: () => _showPasswordStore(context),
                  ),
                  _SettingsTile(
                    title: localizations.gitSyncTitle,
                    subtitle: _gitModeSubtitle(localizations),
                    icon: Icons.sync,
                    onTap: () => _showGitSync(context),
                  ),
                ],
              ),
              _SettingsSection(
                title: localizations.autofillSection,
                children: <Widget>[
                  _SettingsTile(
                    title: localizations.systemAutofillTitle,
                    subtitle: _autofillSubtitle(localizations),
                    icon: Icons.password_outlined,
                    onTap: () => _showAutofill(context),
                  ),
                ],
              ),
              _SettingsSection(
                title: localizations.advancedSupportSection,
                children: <Widget>[
                  if (!Platform.isAndroid && !Platform.isIOS)
                    _SettingsTile(
                      title: localizations.advancedGitArgsTitle,
                      subtitle: localizations.advancedGitArgsDescription,
                      icon: Icons.terminal,
                      onTap: () => _showGitArgs(context),
                    ),
                  _SettingsTile(
                    title: localizations.runtimeDiagnosticsTitle,
                    subtitle: localizations.runtimeDiagnosticsDescription,
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

  Future<void> _showLanguage(BuildContext context) async {
    final localizations = context.l10n;
    final onChanged = onLocalePreferenceChanged;
    if (onChanged == null) {
      AppNotification.show(context, localizations.languageUnavailable);
      return;
    }
    final selected = await showParsAdaptiveSurface<AppLocalePreference>(
      context: context,
      title: localizations.languageTitle,
      builder:
          (surfaceContext) => Column(
            mainAxisSize: MainAxisSize.min,
            children: AppLocalePreference.values
                .map(
                  (preference) => ListTile(
                    leading: Icon(
                      preference == localePreference
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                    ),
                    title: Text(_localeLabel(localizations, preference)),
                    selected: preference == localePreference,
                    onTap: () => Navigator.of(surfaceContext).pop(preference),
                  ),
                )
                .toList(growable: false),
          ),
    );
    if (selected == null || selected == localePreference || !context.mounted) {
      return;
    }
    try {
      await onChanged(selected);
    } catch (_) {
      if (context.mounted) {
        AppNotification.show(context, localizations.languageSaveFailed);
      }
    }
  }

  String _localeLabel(
    AppLocalizations localizations,
    AppLocalePreference preference,
  ) {
    return switch (preference) {
      AppLocalePreference.system => localizations.languageSystem,
      AppLocalePreference.english => localizations.languageEnglish,
      AppLocalePreference.chinese => localizations.languageChinese,
    };
  }

  GitOperationsRepository? get _gitOperations =>
      gitRepository is GitOperationsRepository
          ? gitRepository as GitOperationsRepository
          : null;

  RuntimeDiagnosticsRepository? get _runtimeDiagnostics =>
      settingsRepository is RuntimeDiagnosticsRepository
          ? settingsRepository as RuntimeDiagnosticsRepository
          : null;

  String _gitModeSubtitle(AppLocalizations localizations) {
    return switch (settingsRepository.store?.gitMode) {
      null || StoreGitMode.disabled => localizations.gitDisabledState,
      StoreGitMode.local => localizations.gitLocalState,
      StoreGitMode.remote => localizations.gitRemoteState,
      StoreGitMode.invalid => localizations.invalidGitMetadataTitle,
    };
  }

  String _passwordStoreSubtitle(AppLocalizations localizations) {
    final store = settingsRepository.store;
    if (store == null) return localizations.noPasswordStoreConfigured;
    if (!store.exists) return localizations.passwordStoreFolderNotFound;
    if (!store.hasGpgId) return localizations.missingGpgIdTitle;
    if (store.pgpKeyMissing) return localizations.requiredPgpKeyMissingTitle;
    if (store.gitMode == StoreGitMode.invalid) {
      return localizations.invalidGitMetadataTitle;
    }
    return store.name;
  }

  String _autofillSubtitle(AppLocalizations localizations) {
    final status = autofillRepository?.status;
    if (status == null) return localizations.autofillUnavailableState;
    return switch (status.kind) {
      AutofillStatusKind.ready => localizations.autofillIndexedEntries(
        status.indexedEntries,
      ),
      AutofillStatusKind.needsRebuild => localizations.autofillNeedsRebuild,
      AutofillStatusKind.busy => localizations.autofillBusy,
      AutofillStatusKind.disabled => localizations.autofillDisabled,
      AutofillStatusKind.unavailable => localizations.autofillUnavailableState,
    };
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
