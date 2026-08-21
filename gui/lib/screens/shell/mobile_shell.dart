import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/pars_design_tokens.dart';
import '../../l10n/l10n.dart';
import '../../services/autofill_repository.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/path_picker_service.dart';
import '../../services/security_repository.dart';
import '../../services/sensitive_clipboard_service.dart';
import '../../services/settings_repository.dart';
import '../../services/ui_preferences_store.dart';
import '../../services/vault_repository.dart';
import '../settings/settings_screen.dart';
import '../vault/vault_screen.dart';
import 'shell_view_state.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.vaultRepository,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
    required this.securityRepository,
    required this.autofillRepository,
    required this.pathPickerService,
    required this.localePreference,
    required this.onLocalePreferenceChanged,
    required this.clipboardService,
    required this.privacyEvents,
    required this.onLock,
    this.onSecuritySettingsChanged,
    this.runDuringSystemAuthentication,
    this.onStoreLifecycleChanged,
    this.onOnboardingReset,
  });

  final VaultRepository vaultRepository;
  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final AutofillRepository autofillRepository;
  final PathPickerService pathPickerService;
  final AppLocalePreference localePreference;
  final Future<void> Function(AppLocalePreference preference)
  onLocalePreferenceChanged;
  final SensitiveClipboardService clipboardService;
  final ValueListenable<int> privacyEvents;
  final VoidCallback onLock;
  final VoidCallback? onSecuritySettingsChanged;
  final Future<T> Function<T>(Future<T> Function() action)?
  runDuringSystemAuthentication;
  final Future<void> Function()? onStoreLifecycleChanged;
  final VoidCallback? onOnboardingReset;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;
  final VaultDestinationState _vaultState = VaultDestinationState();
  final SettingsDestinationState _settingsState = SettingsDestinationState();

  @override
  void dispose() {
    _vaultState.dispose();
    _settingsState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final pages = <Widget>[
      VaultScreen(
        key: const PageStorageKey<String>('vault-destination'),
        vaultRepository: widget.vaultRepository,
        gitRepository: widget.gitRepository,
        keyRepository: widget.keyRepository,
        securityRepository: widget.securityRepository,
        keys: widget.keyRepository.keys,
        viewState: _vaultState,
        clipboardService: widget.clipboardService,
        privacyEvents: widget.privacyEvents,
        onLock: widget.onLock,
      ),
      SettingsScreen(
        key: const PageStorageKey<String>('settings-destination'),
        settingsRepository: widget.settingsRepository,
        keyRepository: widget.keyRepository,
        gitRepository: widget.gitRepository,
        securityRepository: widget.securityRepository,
        autofillRepository: widget.autofillRepository,
        vaultRepository: widget.vaultRepository,
        pathPickerService: widget.pathPickerService,
        localePreference: widget.localePreference,
        scrollController: _settingsState.scrollController,
        onLocalePreferenceChanged: widget.onLocalePreferenceChanged,
        onSecuritySettingsChanged: widget.onSecuritySettingsChanged,
        runDuringSystemAuthentication: widget.runDuringSystemAuthentication,
        onStoreLifecycleChanged: widget.onStoreLifecycleChanged,
        onOnboardingReset: widget.onOnboardingReset,
      ),
    ];
    final content = IndexedStack(index: _index, children: pages);

    return PopScope<void>(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final windowClass = ParsWindowClass.fromWidth(constraints.maxWidth);
          if (windowClass == ParsWindowClass.compact) {
            return Scaffold(
              body: SafeArea(child: content),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _selectDestination,
                destinations: <NavigationDestination>[
                  NavigationDestination(
                    icon: const Icon(Icons.lock_outline),
                    selectedIcon: const Icon(Icons.lock),
                    label: localizations.vaultTitle,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: localizations.settingsTitle,
                  ),
                ],
              ),
            );
          }
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _selectDestination,
                    labelType: NavigationRailLabelType.all,
                    destinations: <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: const Icon(Icons.lock_outline),
                        selectedIcon: const Icon(Icons.lock),
                        label: Text(localizations.vaultTitle),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings),
                        label: Text(localizations.settingsTitle),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectDestination(int value) {
    if (_index == value) return;
    setState(() => _index = value);
  }
}
