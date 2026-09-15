import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

// Rows are grouped into a single bordered container with hairline separators
// rather than rendered as detached cards. Detached cards spend a large share
// of vertical space on gaps and corners, and read as a pile of unrelated
// objects instead of one scannable list. Every page uses this section so the
// outline, row height and spacing stay identical across the app; the geometry
// comes from ParsSectionStyle rather than from each caller.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
    this.emptyLabel,
  });

  final String title;
  final List<Widget> children;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: AppSectionBox(
        title: title,
        emptyLabel: emptyLabel,
        children: children,
      ),
    );
  }
}

// Box-context form for pages and sheets that are not built from slivers.
class AppSectionBox extends StatelessWidget {
  const AppSectionBox({
    super.key,
    required this.title,
    required this.children,
    this.emptyLabel,
  });

  final String title;
  final List<Widget> children;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = context.parsSection;
    final isEmpty = children.isEmpty;

    return Padding(
      padding: style.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: style.headerPadding,
            // Sentence case, not upper case. `toUpperCase()` is a no-op on
            // Chinese, so forcing caps made the English and Chinese builds
            // render visibly different heading hierarchies.
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: style.borderRadius,
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: style.borderWidth,
              ),
            ),
            child: ClipRRect(
              borderRadius: style.borderRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children:
                    isEmpty
                        ? <Widget>[_EmptyRow(label: emptyLabel)]
                        : <Widget>[
                          for (
                            var index = 0;
                            index < children.length;
                            index++
                          ) ...<Widget>[
                            children[index],
                            if (index != children.length - 1)
                              Divider(
                                height: ParsSizes.hairline,
                                thickness: ParsSizes.hairline,
                                indent: style.dividerIndent,
                                endIndent: 0,
                              ),
                          ],
                        ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The one row shape used inside a section. Entry rows, settings rows and
// navigation rows differ only in what they put in the leading, trailing and
// label slots, so none of them measure themselves.
class ParsSectionRow extends StatelessWidget {
  const ParsSectionRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.subtitleStyle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.semanticLabel,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final TextStyle? subtitleStyle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = context.parsSection;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? '$title, $subtitle',
      child: Material(
        color:
            selected
                ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: style.rowMinHeight),
            child: Padding(
              padding: style.rowPadding,
              child: Row(
                children: <Widget>[
                  leading,
                  SizedBox(width: style.rowSpacing),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        SizedBox(height: style.rowTitleSpacing),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              subtitleStyle ??
                              theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing case final trailing?) ...<Widget>[
                    SizedBox(width: style.rowTrailingSpacing),
                    trailing,
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

// Neutral leading slot for rows that identify themselves with an icon rather
// than with an accent-coloured monogram.
class ParsSectionRowIcon extends StatelessWidget {
  const ParsSectionRowIcon({super.key, required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: ParsSizes.compactAvatar,
      height: ParsSizes.compactAvatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(ParsRadii.control),
      ),
      child: Icon(
        icon,
        size: ParsSizes.iconSmall,
        color: color ?? colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = context.parsSection;
    if (label == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ParsSpacing.md,
        vertical: ParsSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.inbox_outlined,
            size: ParsSizes.iconSmall,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: style.rowSpacing),
          Expanded(
            child: Text(
              label!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
