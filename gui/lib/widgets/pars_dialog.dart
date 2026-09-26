import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import 'pars_action_group.dart';

@immutable
class ParsDialogAction {
  const ParsDialogAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
}

// Every confirmation and choice popup uses this layout: a title row, the
// content, and at most two equal-width buttons side by side. Material's
// AlertDialog stacks its actions one per line as soon as they do not fit a
// single row, which is what three actions or a long label always hit on a
// phone. A third action belongs in the title row: dismissal as the close icon,
// secondary links as header icons.
class ParsDialog extends StatelessWidget {
  const ParsDialog({
    super.key,
    required this.title,
    required this.primary,
    this.content,
    this.secondary,
    this.destructive = false,
    this.showClose = false,
    this.headerActions = const <Widget>[],
  });

  final String title;
  final Widget? content;
  final ParsDialogAction primary;
  final ParsDialogAction? secondary;
  final bool destructive;
  final bool showClose;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final secondaryAction = secondary;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ParsContentWidth.narrow),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ParsSpacing.xl,
            ParsSpacing.lg,
            ParsSpacing.md,
            ParsSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ...headerActions,
                  if (showClose)
                    IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              if (content case final content?) ...<Widget>[
                const SizedBox(height: ParsSpacing.sm),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: ParsSpacing.xs),
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      child: content,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: ParsSpacing.xl),
              Padding(
                padding: const EdgeInsets.only(right: ParsSpacing.xs),
                child: ParsButtonGrid(
                  children: <Widget>[
                    if (secondaryAction != null)
                      _button(
                        secondaryAction,
                        (onPressed, icon, label) =>
                            icon == null
                                ? OutlinedButton(
                                  onPressed: onPressed,
                                  child: label,
                                )
                                : OutlinedButton.icon(
                                  onPressed: onPressed,
                                  icon: icon,
                                  label: label,
                                ),
                      ),
                    _button(primary, (onPressed, icon, label) {
                      final style =
                          destructive
                              ? FilledButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              )
                              : null;
                      return icon == null
                          ? FilledButton(
                            onPressed: onPressed,
                            style: style,
                            child: label,
                          )
                          : FilledButton.icon(
                            onPressed: onPressed,
                            style: style,
                            icon: icon,
                            label: label,
                          );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
    ParsDialogAction action,
    Widget Function(VoidCallback? onPressed, Widget? icon, Widget label) build,
  ) {
    return build(
      action.onPressed,
      action.icon == null ? null : Icon(action.icon),
      Text(action.label, textAlign: TextAlign.center),
    );
  }
}
