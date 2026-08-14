import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../models/pgp_key_import.dart';
import '../../l10n/app_localizations.dart';
import '../../services/key_repository.dart';
import '../../services/security_repository.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';

class EntryDetailSheet extends StatefulWidget {
  const EntryDetailSheet({
    super.key,
    required this.entry,
    required this.repository,
    this.keyRepository,
    this.securityRepository,
    this.onSecretCleared,
    this.copyText,
    this.onOpenUri,
    this.onFavoriteChanged,
    this.onChooseKey,
    this.onOpenKeyManagement,
    this.keys = const <KeyRecord>[],
    this.clipboardClearDelay = const Duration(seconds: 45),
  });

  final PasswordEntry entry;
  final VaultRepository repository;
  final KeyRepository? keyRepository;
  final SecurityRepository? securityRepository;
  final VoidCallback? onSecretCleared;
  final Future<void> Function(String text)? copyText;
  final Future<void> Function(Uri uri)? onOpenUri;
  final VoidCallback? onFavoriteChanged;
  final VoidCallback? onChooseKey;
  final VoidCallback? onOpenKeyManagement;
  final List<KeyRecord> keys;
  final Duration clipboardClearDelay;

  @override
  State<EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends State<EntryDetailSheet> {
  final TextEditingController _passphraseController = TextEditingController();
  bool _isRevealed = false;
  late bool _isFavorite;
  bool _needsPassphrase = false;
  bool _isLoading = true;
  bool _isPreparingKey = false;
  SecretContent? _content;
  String? _loadError;
  String? _passphraseError;
  Timer? _clipboardClearTimer;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.entry.isFavorite;
    _prepareSecretLoad();
  }

  @override
  void didUpdateWidget(covariant EntryDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.repository != widget.repository) {
      _clearSecret();
      _isFavorite = widget.entry.isFavorite;
      _prepareSecretLoad();
    }
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    _clearSecret();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('entry-detail-sheet'),
      width: double.infinity,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_needsPassphrase) {
      final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      return AnimatedPadding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Center(child: _SheetHandle()),
                const SizedBox(height: 18),
                Text(
                  'PGP passphrase required',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(widget.entry.path),
                const SizedBox(height: 16),
                TextField(
                  controller: _passphraseController,
                  autofocus: true,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'PGP passphrase',
                    errorText: _passphraseError,
                  ),
                  onSubmitted: (_) => _startPgpSession(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isPreparingKey ? null : _startPgpSession,
                    icon:
                        _isPreparingKey
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.lock_open),
                    label: Text(
                      _isPreparingKey
                          ? AppLocalizations.of(
                            context,
                          ).pgpPreparationInProgress
                          : 'Unlock entry',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              _SheetHandle(),
              SizedBox(height: 24),
              CircularProgressIndicator(),
              SizedBox(height: 18),
            ],
          ),
        ),
      );
    }

    if (_loadError != null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Center(child: _SheetHandle()),
              const SizedBox(height: 18),
              Text(
                'Could not decrypt entry',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _loadError!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _loadSecret,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        widget.onChooseKey ??
                        () => _showMessage('Open key import from Settings'),
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Choose/import key'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        widget.onOpenKeyManagement ??
                        () => _showMessage('Open Settings > PGP keys'),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open key management'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final content = _content;
    if (content == null) {
      return const SafeArea(child: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final passwordSurfaceColor =
        theme.inputDecorationTheme.fillColor ??
        colorScheme.surfaceContainerHighest;
    final url = _entryUrl(content);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Center(child: _SheetHandle()),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    child: Text(widget.entry.initials),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.entry.displayName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          widget.entry.path,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                key: const ValueKey<String>('entry-password-surface'),
                decoration: BoxDecoration(
                  color: passwordSurfaceColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _isRevealed ? content.password : '••••••••••••••',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colorScheme.onSurface,
                            letterSpacing: _isRevealed ? 0 : 2,
                          ),
                        ),
                      ),
                      IconButton(
                        color: colorScheme.onSurfaceVariant,
                        tooltip: _isRevealed ? 'Hide' : 'Reveal',
                        onPressed:
                            () => setState(() => _isRevealed = !_isRevealed),
                        icon: Icon(
                          _isRevealed
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _copyPassword,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy password'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _isRevealed = !_isRevealed),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Reveal'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _toggleFavorite,
                    icon: Icon(
                      _isFavorite ? Icons.star : Icons.star_border_outlined,
                    ),
                    label: Text(_isFavorite ? 'Unfavorite' : 'Favorite'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  if (url != null)
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(url),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open URL'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _showQrCode(content.password),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('QR code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              if (content.fields.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Fields',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final field in content.fields)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(field.label),
                    subtitle: Text(field.value),
                    trailing: TextButton(
                      onPressed: () => _copyField(field),
                      child: const Text('Copy'),
                    ),
                  ),
              ],
              if (content.rawNotes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Raw notes',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(content.rawNotes),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadSecret() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final content = await widget.repository.readEntry(widget.entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _content = content;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _clearSecret();
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  void _prepareSecretLoad() {
    if (_shouldPromptForPassphrase) {
      _needsPassphrase = true;
      _isLoading = false;
      _loadError = null;
      return;
    }
    _needsPassphrase = false;
    _loadSecret();
  }

  bool get _shouldPromptForPassphrase {
    final securityRepository = widget.securityRepository;
    return securityRepository != null &&
        !securityRepository.hasActivePgpSession;
  }

  Future<void> _startPgpSession() async {
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      setState(() => _passphraseError = 'Enter a passphrase.');
      return;
    }
    final securityRepository = widget.securityRepository;
    if (securityRepository == null) {
      return;
    }
    final fingerprint = _primaryPrivatePgpFingerprint;
    if (fingerprint == null) {
      setState(() => _passphraseError = 'Select or import a private PGP key.');
      return;
    }
    setState(() {
      _isPreparingKey = true;
      _passphraseError = null;
    });
    try {
      final keyRepository = widget.keyRepository;
      if (keyRepository != null) {
        final prepared = await keyRepository.preparePgpPrivateKey(
          fingerprint: fingerprint,
          passphrase: passphrase,
        );
        if (prepared.fingerprint.trim().toUpperCase() !=
            fingerprint.trim().toUpperCase()) {
          throw const PgpImportException(
            PgpImportFailureKind.reprotectionFailed,
            'Prepared PGP fingerprint did not match the selected key.',
          );
        }
      }
      await securityRepository.startPgpSession(
        fingerprint: fingerprint,
        passphrase: passphrase,
      );
      _passphraseController.clear();
      if (!mounted) return;
      setState(() {
        _isPreparingKey = false;
        _needsPassphrase = false;
        _passphraseError = null;
      });
      await _loadSecret();
    } catch (error) {
      _passphraseController.clear();
      if (!mounted) return;
      final localizations = AppLocalizations.of(context);
      setState(() {
        _isPreparingKey = false;
        _passphraseError = switch (error) {
          PgpImportException(kind: PgpImportFailureKind.passphraseRequired) =>
            localizations.pgpPassphraseRequired,
          PgpImportException(kind: PgpImportFailureKind.incorrectPassphrase) =>
            localizations.pgpPassphraseIncorrect,
          PgpImportException(
            kind: PgpImportFailureKind.unsupportedProtection,
          ) =>
            localizations.pgpUnsupportedProtection,
          PgpImportException(kind: PgpImportFailureKind.reprotectionFailed) =>
            localizations.pgpReprotectionFailed,
          _ => error.toString(),
        };
      });
    }
  }

  String? get _primaryPrivatePgpFingerprint {
    for (final key in widget.keys) {
      if (key.type == KeyRecordType.pgp && key.hasPrivateKey) {
        return key.fingerprint;
      }
    }
    return null;
  }

  Future<void> _copyPassword() async {
    try {
      final password = await widget.repository.copyEntryPassword(widget.entry);
      await _copyText(password);
      _showMessage('Copied ${widget.entry.displayName} password');
    } catch (error) {
      _showMessage('Could not copy password: $error');
    }
  }

  Future<void> _copyField(ParsedSecretField field) async {
    await _copyText(field.value);
    _showMessage('Copied ${field.label}');
  }

  Future<void> _toggleFavorite() async {
    await widget.repository.toggleFavorite(widget.entry);
    if (!mounted) {
      return;
    }
    setState(() => _isFavorite = !_isFavorite);
    widget.onFavoriteChanged?.call();
  }

  void _showQrCode(String password) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder:
          (context) => SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const _SheetHandle(),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Password QR code',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close QR code',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    QrImageView(
                      data: password,
                      version: QrVersions.auto,
                      size: 200,
                      // Keep QR modules on a fixed high-contrast background.
                      backgroundColor: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _copyText(String text) async {
    final writer = widget.copyText ?? _copyToSystemClipboard;
    await writer(text);
    _clipboardClearTimer?.cancel();
    if (widget.clipboardClearDelay <= Duration.zero) {
      return;
    }
    _clipboardClearTimer = Timer(widget.clipboardClearDelay, () {
      writer('');
    });
  }

  Future<void> _openUrl(Uri uri) async {
    final opener = widget.onOpenUri;
    if (opener != null) {
      await opener(uri);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showMessage('Could not open ${uri.toString()}');
    }
  }

  Uri? _entryUrl(SecretContent content) {
    final raw = content.fieldValue('url') ?? content.fieldValue('website');
    if (raw == null) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    return uri;
  }

  Future<void> _copyToSystemClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppNotification.show(context, message);
  }

  void _clearSecret() {
    _isRevealed = false;
    _content = null;
    widget.onSecretCleared?.call();
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
