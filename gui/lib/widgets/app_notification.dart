import 'dart:async';

import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

enum AppNotificationSeverity { info, success, warning, error }

class AppNotification {
  AppNotification._();

  static OverlayEntry? _entry;
  static AppNotificationSeverity? _severity;

  static void show(
    BuildContext context,
    String message, {
    AppNotificationSeverity severity = AppNotificationSeverity.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final currentSeverity = _severity;
    if (_entry != null &&
        currentSeverity != null &&
        _isHighSeverity(currentSeverity) &&
        !_isHighSeverity(severity)) {
      return;
    }
    _removeEntry();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final resolvedDuration = duration ?? _durationFor(severity);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration:
              resolvedDuration > Duration.zero
                  ? resolvedDuration
                  : const Duration(days: 1),
          action:
              actionLabel == null || onAction == null
                  ? null
                  : SnackBarAction(label: actionLabel, onPressed: onAction),
        ),
      );
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (context) => _AppNotificationBanner(
            message: message,
            severity: severity,
            duration: resolvedDuration,
            actionLabel: actionLabel,
            onAction: onAction,
            onDismiss: () {
              if (_entry == entry) dismiss();
            },
          ),
    );
    _entry = entry;
    _severity = severity;
    overlay.insert(entry);
  }

  static void dismiss() => _removeEntry();

  static Duration _durationFor(AppNotificationSeverity severity) {
    return switch (severity) {
      AppNotificationSeverity.info => const Duration(seconds: 3),
      AppNotificationSeverity.success => const Duration(seconds: 3),
      AppNotificationSeverity.warning => const Duration(seconds: 8),
      AppNotificationSeverity.error => const Duration(seconds: 8),
    };
  }

  static bool _isHighSeverity(AppNotificationSeverity severity) {
    return severity == AppNotificationSeverity.warning ||
        severity == AppNotificationSeverity.error;
  }

  static void _removeEntry() {
    final entry = _entry;
    _entry = null;
    _severity = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

class _AppNotificationBanner extends StatefulWidget {
  const _AppNotificationBanner({
    required this.message,
    required this.severity,
    required this.duration,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppNotificationSeverity severity;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  State<_AppNotificationBanner> createState() => _AppNotificationBannerState();
}

class _AppNotificationBannerState extends State<_AppNotificationBanner> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    if (widget.duration > Duration.zero) {
      _dismissTimer = Timer(widget.duration, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = _foreground(context);
    final background = Color.alphaBlend(
      foreground.withValues(alpha: 0.14),
      colorScheme.surfaceContainerHighest,
    );

    return Positioned.fill(
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ParsSpacing.md,
              ParsSpacing.sm,
              ParsSpacing.md,
              0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                elevation: 10,
                color: background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ParsRadii.control),
                  side: BorderSide(color: foreground.withValues(alpha: 0.45)),
                ),
                child: Semantics(
                  liveRegion: true,
                  container: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: ParsSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        Icon(_icon, color: foreground),
                        const SizedBox(width: ParsSpacing.sm),
                        Expanded(
                          child: Text(
                            widget.message,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                        if (widget.actionLabel != null &&
                            widget.onAction != null)
                          TextButton(
                            onPressed: () {
                              widget.onAction!();
                              widget.onDismiss();
                            },
                            child: Text(widget.actionLabel!),
                          ),
                        IconButton(
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                          onPressed: widget.onDismiss,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _foreground(BuildContext context) {
    return switch (widget.severity) {
      AppNotificationSeverity.info => context.parsColors.info,
      AppNotificationSeverity.success => context.parsColors.success,
      AppNotificationSeverity.warning => context.parsColors.warning,
      AppNotificationSeverity.error => Theme.of(context).colorScheme.error,
    };
  }

  IconData get _icon => switch (widget.severity) {
    AppNotificationSeverity.info => Icons.info_outline,
    AppNotificationSeverity.success => Icons.check_circle_outline,
    AppNotificationSeverity.warning => Icons.warning_amber_rounded,
    AppNotificationSeverity.error => Icons.error_outline,
  };
}
