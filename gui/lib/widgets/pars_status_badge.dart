import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

enum ParsStatusKind { neutral, success, warning, error, busy, unavailable }

class ParsStatusBadge extends StatelessWidget {
  const ParsStatusBadge({
    super.key,
    required this.label,
    required this.kind,
    this.tooltip,
    this.onPressed,
  });

  final String label;
  final ParsStatusKind kind;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = _foreground(context);
    final icon = _icon;
    final badge = Semantics(
      button: onPressed != null,
      liveRegion: kind == ParsStatusKind.error,
      label: label,
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: onPressed,
        backgroundColor: color.withValues(alpha: 0.12),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
    return Tooltip(message: tooltip ?? label, child: badge);
  }

  Color _foreground(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.parsColors;
    return switch (kind) {
      ParsStatusKind.neutral => theme.colorScheme.onSurfaceVariant,
      ParsStatusKind.success => semantic.success,
      ParsStatusKind.warning => semantic.warning,
      ParsStatusKind.error => theme.colorScheme.error,
      ParsStatusKind.busy => semantic.busy,
      ParsStatusKind.unavailable => semantic.unavailable,
    };
  }

  IconData get _icon => switch (kind) {
    ParsStatusKind.neutral => Icons.info_outline,
    ParsStatusKind.success => Icons.check_circle_outline,
    ParsStatusKind.warning => Icons.warning_amber_rounded,
    ParsStatusKind.error => Icons.error_outline,
    ParsStatusKind.busy => Icons.sync,
    ParsStatusKind.unavailable => Icons.block_outlined,
  };
}
