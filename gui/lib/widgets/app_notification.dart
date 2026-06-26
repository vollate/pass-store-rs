import 'dart:async';

import 'package:flutter/material.dart';

class AppNotification {
  AppNotification._();

  static const Duration _defaultDuration = Duration(seconds: 3);
  static OverlayEntry? _entry;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) {
    _removeEntry();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (context) => _AppNotificationBanner(
            message: message,
            duration: duration,
            onDismiss: () {
              if (_entry == entry) {
                dismiss();
              }
            },
          ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    _removeEntry();
  }

  static void _removeEntry() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }
}

class _AppNotificationBanner extends StatefulWidget {
  const _AppNotificationBanner({
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  final String message;
  final Duration duration;
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

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  elevation: 10,
                  color: colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        widget.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onInverseSurface,
                        ),
                      ),
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
}
