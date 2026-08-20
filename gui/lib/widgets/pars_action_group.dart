import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

enum ParsActionKind { primary, secondary, tertiary, destructive }

@immutable
class ParsActionItem {
  const ParsActionItem({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.kind = ParsActionKind.secondary,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final ParsActionKind kind;
  final String? tooltip;
}

class ParsActionGroup extends StatelessWidget {
  const ParsActionGroup({
    super.key,
    required this.actions,
    this.alignment = WrapAlignment.start,
  });

  final List<ParsActionItem> actions;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ParsSpacing.xs,
      runSpacing: ParsSpacing.xs,
      alignment: alignment,
      children: actions.map((action) => _buildAction(context, action)).toList(),
    );
  }

  Widget _buildAction(BuildContext context, ParsActionItem action) {
    final icon = Icon(action.icon);
    final label = Text(action.label);
    final button = switch (action.kind) {
      ParsActionKind.primary => FilledButton.icon(
        onPressed: action.onPressed,
        icon: icon,
        label: label,
      ),
      ParsActionKind.secondary => OutlinedButton.icon(
        onPressed: action.onPressed,
        icon: icon,
        label: label,
      ),
      ParsActionKind.tertiary => TextButton.icon(
        onPressed: action.onPressed,
        icon: icon,
        label: label,
      ),
      ParsActionKind.destructive => OutlinedButton.icon(
        onPressed: action.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        icon: icon,
        label: label,
      ),
    };
    return Semantics(
      button: true,
      enabled: action.onPressed != null,
      label: action.label,
      child: Tooltip(message: action.tooltip ?? action.label, child: button),
    );
  }
}
