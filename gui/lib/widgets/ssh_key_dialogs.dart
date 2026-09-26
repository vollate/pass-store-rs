import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/sensitive_clipboard_service.dart';
import 'app_notification.dart';
import 'pars_dialog.dart';

final Uri githubSshKeysUri = Uri.parse('https://github.com/settings/keys');

Future<void> showSshPublicKeyDialog(
  BuildContext context, {
  required String keyName,
  required String publicKey,
}) {
  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) =>
            _SshPublicKeyDialog(keyName: keyName, publicKey: publicKey.trim()),
  );
}

Future<bool> confirmDeleteSshKey(BuildContext context, String keyName) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final localizations = dialogContext.l10n;
      return ParsDialog(
        title: localizations.deleteKeyTitle(localizations.sshStep),
        content: Text(localizations.deleteSshKeyQuestion(keyName)),
        destructive: true,
        secondary: ParsDialogAction(
          label: localizations.cancel,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        primary: ParsDialogAction(
          label: localizations.delete,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      );
    },
  );
  return approved ?? false;
}

Future<void> openGithubSshSettings(BuildContext context) async {
  var opened = false;
  try {
    opened = await launchUrl(
      githubSshKeysUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    AppNotification.show(
      context,
      githubSshKeysUri.toString(),
      severity: AppNotificationSeverity.warning,
    );
  }
}

class _SshPublicKeyDialog extends StatelessWidget {
  const _SshPublicKeyDialog({required this.keyName, required this.publicKey});

  final String keyName;
  final String publicKey;

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    return ParsDialog(
      title: keyName,
      showClose: true,
      content: SelectableText(
        publicKey,
        key: const Key('ssh-public-key-text'),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      secondary: ParsDialogAction(
        label: localizations.githubSettings,
        icon: Icons.open_in_new,
        onPressed: () => openGithubSshSettings(context),
      ),
      primary: ParsDialogAction(
        label: localizations.copy,
        icon: Icons.copy,
        onPressed: () => _copy(context),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final clipboard = SensitiveClipboardService();
    try {
      await clipboard.copyPublic(publicKey);
    } finally {
      clipboard.dispose();
    }
    if (!context.mounted) return;
    AppNotification.show(
      context,
      context.l10n.copiedField(context.l10n.publicKeyMaterial),
      severity: AppNotificationSeverity.success,
    );
  }
}

// Text or file source choice shared by the onboarding and Settings SSH import.
Future<String?> chooseSshImportSource(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final localizations = dialogContext.l10n;
      return ParsDialog(
        title: localizations.importSshKey,
        showClose: true,
        secondary: ParsDialogAction(
          label: localizations.textSource,
          icon: Icons.notes_outlined,
          onPressed: () => Navigator.of(dialogContext).pop('text'),
        ),
        primary: ParsDialogAction(
          label: localizations.fileSource,
          icon: Icons.insert_drive_file_outlined,
          onPressed: () => Navigator.of(dialogContext).pop('file'),
        ),
      );
    },
  );
}
