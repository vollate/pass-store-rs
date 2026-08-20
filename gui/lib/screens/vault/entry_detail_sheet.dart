import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../models/pgp_key_import.dart';
import '../../l10n/l10n.dart';
import '../../services/key_repository.dart';
import '../../services/security_repository.dart';
import '../../services/sensitive_clipboard_service.dart';
import '../../services/ui_problem.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';

enum _EntryDetailMenuAction { edit, move, rename, qr, regenerate, delete }

class EntryDetailSheet extends StatefulWidget {
  const EntryDetailSheet({
    super.key,
    required this.entry,
    required this.repository,
    this.keyRepository,
    this.securityRepository,
    this.clipboardService,
    this.privacyEvents,
    this.onSecretCleared,
    this.copyText,
    this.onOpenUri,
    this.onFavoriteChanged,
    this.onEdit,
    this.onMove,
    this.onRename,
    this.onRegenerate,
    this.onDelete,
    this.onChooseKey,
    this.onOpenKeyManagement,
    this.keys = const <KeyRecord>[],
    this.clipboardClearDelay = const Duration(seconds: 45),
  });

  final PasswordEntry entry;
  final VaultRepository repository;
  final KeyRepository? keyRepository;
  final SecurityRepository? securityRepository;
  final SensitiveClipboardService? clipboardService;
  final ValueListenable<int>? privacyEvents;
  final VoidCallback? onSecretCleared;
  final Future<void> Function(String text)? copyText;
  final Future<void> Function(Uri uri)? onOpenUri;
  final VoidCallback? onFavoriteChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onMove;
  final VoidCallback? onRename;
  final VoidCallback? onRegenerate;
  final VoidCallback? onDelete;
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
  late final SensitiveClipboardService _clipboardService;
  late final bool _ownsClipboardService;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.entry.isFavorite;
    _ownsClipboardService = widget.clipboardService == null;
    widget.privacyEvents?.addListener(_handlePrivacyEvent);
    _clipboardService =
        widget.clipboardService ??
        SensitiveClipboardService(
          platform:
              widget.copyText == null
                  ? const SystemSensitiveClipboardPlatform()
                  : CallbackSensitiveClipboardPlatform(widget.copyText!),
          clearDelay: widget.clipboardClearDelay,
        );
    _prepareSecretLoad();
  }

  @override
  void didUpdateWidget(covariant EntryDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.privacyEvents != widget.privacyEvents) {
      oldWidget.privacyEvents?.removeListener(_handlePrivacyEvent);
      widget.privacyEvents?.addListener(_handlePrivacyEvent);
    }
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.repository != widget.repository) {
      _clearSecret();
      _isFavorite = widget.entry.isFavorite;
      _prepareSecretLoad();
    }
  }

  @override
  void dispose() {
    widget.privacyEvents?.removeListener(_handlePrivacyEvent);
    if (_ownsClipboardService) _clipboardService.dispose();
    _clearSecret();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;
    final preferredHeight = (availableHeight * 0.78).clamp(0.0, 720.0);
    final stableHeight =
        availableHeight < 240
            ? availableHeight
            : preferredHeight.clamp(240.0, 720.0);
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        key: const ValueKey<String>('entry-detail-sheet'),
        width: double.infinity,
        height: stableHeight.toDouble(),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final localizations = context.l10n;
    if (_needsPassphrase) {
      return SafeArea(
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
                localizations.pgpPassphraseRequiredTitle,
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
                  labelText: localizations.pgpPassphraseLabel,
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
                        ? context.l10n.pgpPreparationInProgress
                        : localizations.unlockEntry,
                  ),
                ),
              ),
            ],
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
                localizations.decryptEntryFailedTitle,
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
                    label: Text(localizations.retry),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        widget.onChooseKey ??
                        () => _showMessage(localizations.openKeyImportHint),
                    icon: const Icon(Icons.key_outlined),
                    label: Text(localizations.chooseImportKey),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        widget.onOpenKeyManagement ??
                        () => _showMessage(localizations.openPgpKeysHint),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(localizations.openKeyManagement),
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
                  IconButton(
                    tooltip:
                        _isFavorite
                            ? localizations.unfavorite
                            : localizations.favorite,
                    isSelected: _isFavorite,
                    onPressed: _toggleFavorite,
                    icon: const Icon(Icons.star_border_outlined),
                    selectedIcon: const Icon(Icons.star),
                  ),
                  PopupMenuButton<_EntryDetailMenuAction>(
                    tooltip: localizations.moreActions,
                    onSelected:
                        (action) => _handleMenuAction(action, content.password),
                    itemBuilder: (context) => _secondaryMenuItems(context),
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
                        tooltip:
                            _isRevealed
                                ? localizations.hide
                                : localizations.reveal,
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
                    label: Text(localizations.copyPassword),
                  ),
                  if (url != null)
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(url),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(localizations.openUrl),
                    ),
                ],
              ),
              if (content.fields.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  localizations.fields,
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
                      child: Text(localizations.copy),
                    ),
                  ),
              ],
              if (content.rawNotes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  localizations.rawNotes,
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

  List<PopupMenuEntry<_EntryDetailMenuAction>> _secondaryMenuItems(
    BuildContext context,
  ) {
    final localizations = context.l10n;
    return <PopupMenuEntry<_EntryDetailMenuAction>>[
      if (widget.onEdit != null)
        _menuItem(
          value: _EntryDetailMenuAction.edit,
          icon: Icons.edit_outlined,
          label: localizations.edit,
        ),
      if (widget.onMove != null)
        _menuItem(
          value: _EntryDetailMenuAction.move,
          icon: Icons.drive_file_move_outlined,
          label: localizations.move,
        ),
      if (widget.onRename != null)
        _menuItem(
          value: _EntryDetailMenuAction.rename,
          icon: Icons.drive_file_rename_outline,
          label: localizations.rename,
        ),
      _menuItem(
        value: _EntryDetailMenuAction.qr,
        icon: Icons.qr_code_2,
        label: localizations.qrCode,
      ),
      if (widget.onRegenerate != null)
        _menuItem(
          value: _EntryDetailMenuAction.regenerate,
          icon: Icons.refresh,
          label: localizations.regenerate,
        ),
      if (widget.onDelete != null) const PopupMenuDivider(),
      if (widget.onDelete != null)
        _menuItem(
          value: _EntryDetailMenuAction.delete,
          icon: Icons.delete_outline,
          label: localizations.delete,
          color: Theme.of(context).colorScheme.error,
        ),
    ];
  }

  PopupMenuItem<_EntryDetailMenuAction> _menuItem({
    required _EntryDetailMenuAction value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return PopupMenuItem<_EntryDetailMenuAction>(
      value: value,
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

  void _handleMenuAction(_EntryDetailMenuAction action, String password) {
    switch (action) {
      case _EntryDetailMenuAction.edit:
        widget.onEdit?.call();
        break;
      case _EntryDetailMenuAction.move:
        widget.onMove?.call();
        break;
      case _EntryDetailMenuAction.rename:
        widget.onRename?.call();
        break;
      case _EntryDetailMenuAction.qr:
        _showQrCode(password);
        break;
      case _EntryDetailMenuAction.regenerate:
        widget.onRegenerate?.call();
        break;
      case _EntryDetailMenuAction.delete:
        widget.onDelete?.call();
        break;
    }
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
        _loadError = UiProblem.fromError(context.l10n, error).summary;
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
      setState(() => _passphraseError = context.l10n.enterPassphrase);
      return;
    }
    final securityRepository = widget.securityRepository;
    if (securityRepository == null) {
      return;
    }
    final fingerprint = _primaryPrivatePgpFingerprint;
    if (fingerprint == null) {
      setState(() => _passphraseError = context.l10n.selectPrivatePgpKey);
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
      final localizations = context.l10n;
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
          _ => UiProblem.fromError(context.l10n, error).summary,
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
    final localizations = context.l10n;
    try {
      final password = await widget.repository.copyEntryPassword(widget.entry);
      await _copyText(password);
      _showMessage(localizations.copiedEntryPassword(widget.entry.displayName));
    } catch (_) {
      _showMessage(localizations.couldNotCopyPassword);
    }
  }

  Future<void> _copyField(ParsedSecretField field) async {
    final message = context.l10n.copiedField(field.label);
    await _copyText(field.value);
    _showMessage(message);
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
                            context.l10n.passwordQrCode,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.closeQrCode,
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

  Future<void> _copyText(String text) {
    return _clipboardService.copySecret(text);
  }

  Future<void> _openUrl(Uri uri) async {
    final failureMessage = context.l10n.couldNotOpenUrl;
    final opener = widget.onOpenUri;
    if (opener != null) {
      await opener(uri);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showMessage(failureMessage);
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

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppNotification.show(context, message);
  }

  void _handlePrivacyEvent() {
    if (!mounted) return;
    _clearSecret();
    Navigator.of(context).maybePop();
  }

  void _clearSecret() {
    final hadSecret = _content != null;
    _isRevealed = false;
    _content = null;
    if (hadSecret) widget.onSecretCleared?.call();
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
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
