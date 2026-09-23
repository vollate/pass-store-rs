import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import '../bridge/frb_generated/frb_generated.dart';
import '../bridge/pars_bridge_api.dart';
import '../l10n/app_localizations.dart';
import '../services/autofill_repository.dart';
import '../services/bridge_backed_repository.dart';
import '../services/key_repository.dart';
import '../services/mobile_pgp_backend.dart';
import '../services/security_repository.dart';
import '../services/ui_preferences_store.dart';
import 'pars_design_tokens.dart';
import 'pars_gui_app.dart';
import 'pars_theme.dart';

class ParsBootstrapApp extends StatefulWidget {
  const ParsBootstrapApp({super.key, this.start = createParsGuiApp});

  final Future<Widget> Function() start;

  @override
  State<ParsBootstrapApp> createState() => _ParsBootstrapAppState();
}

class _ParsBootstrapAppState extends State<ParsBootstrapApp> {
  Widget? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final app = await widget.start();
      if (!mounted) return;
      setState(() {
        _app = app;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('pars bootstrap failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) return app;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ParsTheme.light(),
      darkTheme: ParsTheme.dark(),
      themeMode: ThemeMode.system,
      home: _BootstrapStatusScreen(
        error: _error,
        onRetry: () {
          setState(() => _error = null);
          unawaited(_load());
        },
      ),
    );
  }
}

class _BootstrapStatusScreen extends StatelessWidget {
  const _BootstrapStatusScreen({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ParsContentWidth.narrow,
            ),
            child: Padding(
              padding: ParsInsets.page,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (error == null) const CircularProgressIndicator(),
                  if (error != null)
                    Text(
                      localizations.failed,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  const SizedBox(height: ParsSpacing.xl),
                  Text(
                    error == null
                        ? localizations.storeActionInProgress
                        : error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: ParsSpacing.lg),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(localizations.retry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<Widget> createParsGuiApp() async {
  debugPrint('pars bootstrap: rust init');
  await RustLib.init(
    externalLibrary:
        Platform.isIOS ? ExternalLibrary.process(iKnowHowToUseIt: true) : null,
  );
  const bridge = FrbParsBridgeApi();
  debugPrint('pars bootstrap: pgp runtime');
  final pgpRuntime = await configureDefaultPgpRuntime(
    bridge: bridge,
    desktopConfigPath: BridgeBackedRepository.defaultConfigPath(),
  );
  debugPrint('pars bootstrap: security');
  final securityRepository = await SecureStorageSecurityRepository.load();
  final appSupportDirectory = await getApplicationSupportDirectory();
  final uiPreferencesStore = FileUiPreferencesStore(
    File('${appSupportDirectory.path}/pars_ui_preferences.json'),
  );
  late final BridgeBackedRepository repository;
  final autofillRepository = BridgeAutofillRepository(
    bridge: const FrbAutofillBridgeApi(),
    configPath: pgpRuntime.configPath,
    indexPath: '${pgpRuntime.configPath}.autofill.json',
    storeId: 'canonical-store',
    storeName: 'Pars',
    storeRoot: '',
    pgpExecutable: pgpRuntime.pgpExecutable,
    securityRepository: securityRepository,
    currentStoreId: () => 'canonical-store',
    currentStoreName: () => repository.lifecycle.store?.name ?? 'Pars',
    currentStoreRoot: () => repository.lifecycle.store?.root ?? '',
    currentStoreReady:
        () =>
            !repository.storeRemovalInProgress &&
            !repository.lifecycle.requiresStoreSetup &&
            !repository.lifecycle.requiresStoreRepair,
    validatePgpPassphraseForCurrentStore: (fingerprint, passphrase) async {
      final store = repository.lifecycle.store;
      if (store == null || repository.storeRemovalInProgress) return false;
      final expected = fingerprint.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final matching = repository.keys.where(
        (key) =>
            key.hasPrivateKey &&
            key.hasLocalKeyMaterial &&
            key.fingerprint.replaceAll(RegExp(r'\s+'), '').toUpperCase() ==
                expected &&
            pgpIdentityMatchesAnyRecipient(
              fingerprint: key.fingerprint,
              identity: key.name,
              recipients: store.pgpRecipients,
            ),
      );
      if (matching.isEmpty) return false;
      try {
        final prepared = await repository.preparePgpPrivateKey(
          fingerprint: matching.first.fingerprint,
          passphrase: passphrase,
        );
        return prepared.fingerprint
                .replaceAll(RegExp(r'\s+'), '')
                .toUpperCase() ==
            expected;
      } catch (_) {
        return false;
      }
    },
  );
  repository = BridgeBackedRepository(
    bridge: bridge,
    configPath: pgpRuntime.configPath,
    pgpExecutable: pgpRuntime.pgpExecutable,
    pgpBackendLabel: pgpRuntime.diagnosticsLabel,
    sshDir: pgpRuntime.sshDir,
    managedStoreBaseDir: pgpRuntime.storeBaseDir,
    securityRepository: securityRepository,
    autofillRepository: autofillRepository,
  );
  // A cached snapshot is enough to route and paint the first frame; the vault
  // rescans on mount. Only a cache miss has to block startup on a full scan.
  var hydrated = false;
  try {
    debugPrint('pars bootstrap: hydrate');
    hydrated = await repository.hydrateFromCache();
  } catch (error) {
    debugPrint('pars bootstrap: hydrate failed: $error');
  }
  if (!hydrated) {
    try {
      debugPrint('pars bootstrap: refresh');
      await repository.refresh();
    } catch (error) {
      debugPrint('pars bootstrap: refresh failed: $error');
    }
  }
  unawaited(() async {
    try {
      await autofillRepository.publishPlatformState();
    } catch (error) {
      debugPrint('pars bootstrap: autofill publish failed: $error');
    }
  }());
  debugPrint('pars bootstrap: ready');
  return ParsGuiApp(
    vaultRepository: repository,
    settingsRepository: repository,
    keyRepository: repository,
    gitRepository: repository,
    securityRepository: securityRepository,
    autofillRepository: autofillRepository,
    uiPreferencesStore: uiPreferencesStore,
  );
}
