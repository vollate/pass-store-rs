import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

Future<T?> showParsAdaptiveSurface<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  bool isDismissible = true,
  String? closeTooltip,
  double maxWidth = ParsContentWidth.form,
}) {
  final compact = context.parsWindowClass == ParsWindowClass.compact;
  if (compact) {
    final sheetWidth = MediaQuery.sizeOf(context).width.clamp(0.0, maxWidth);
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      showDragHandle: true,
      constraints: BoxConstraints(minWidth: sheetWidth, maxWidth: maxWidth),
      builder:
          (surfaceContext) => ParsAdaptiveSurface(
            title: title,
            maxWidth: maxWidth,
            showClose: false,
            closeTooltip: closeTooltip,
            child: builder(surfaceContext),
          ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder:
        (surfaceContext) => Dialog(
          child: ParsAdaptiveSurface(
            title: title,
            maxWidth: maxWidth,
            showClose: isDismissible,
            closeTooltip: closeTooltip,
            child: builder(surfaceContext),
          ),
        ),
  );
}

Future<T?> showParsAdaptiveDetail<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = ParsContentWidth.form,
  bool showDragHandle = true,
}) {
  if (context.parsWindowClass == ParsWindowClass.compact) {
    final sheetWidth = MediaQuery.sizeOf(context).width.clamp(0.0, maxWidth);
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: showDragHandle,
      constraints: BoxConstraints(minWidth: sheetWidth, maxWidth: maxWidth),
      builder: builder,
    );
  }
  final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
  return showDialog<T>(
    context: context,
    builder:
        (detailContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: builder(detailContext),
          ),
        ),
  );
}

/// Opens a full sub-page on compact phones so native back navigation (including
/// iOS left-edge swipe-back) and top safe-area handling work out of the box,
/// while keeping a constrained dialog on wider screens.
Future<T?> showParsAdaptivePage<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> Function(BuildContext context)? actionsBuilder,
  double maxWidth = ParsContentWidth.form,
}) {
  if (context.parsWindowClass == ParsWindowClass.compact) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: (pageContext) {
          final actions = actionsBuilder?.call(pageContext) ?? const <Widget>[];
          return Scaffold(
            appBar: AppBar(
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  pageContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: <Widget>[
                ...actions,
                if (actions.isNotEmpty) const SizedBox(width: ParsSpacing.xs),
              ],
            ),
            body: SafeArea(top: false, child: builder(pageContext)),
          );
        },
      ),
    );
  }
  final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final actions = actionsBuilder?.call(dialogContext) ?? const <Widget>[];
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ParsSpacing.lg,
                  ParsSpacing.xs,
                  ParsSpacing.xs,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(dialogContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ...actions,
                    IconButton(
                      tooltip:
                          MaterialLocalizations.of(
                            dialogContext,
                          ).closeButtonTooltip,
                      onPressed: () => Navigator.of(dialogContext).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(child: builder(dialogContext)),
            ],
          ),
        ),
      );
    },
  );
}

class ParsAdaptiveSurface extends StatelessWidget {
  const ParsAdaptiveSurface({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = ParsContentWidth.form,
    this.showClose,
    this.closeTooltip,
  });

  final String title;
  final Widget child;
  final double maxWidth;
  final bool? showClose;
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    // A rotation delivers the new viewport size one frame before the stale
    // keyboard inset clears, so the raw inset can exceed the new height.
    final compact = context.parsWindowClass == ParsWindowClass.compact;
    final displayClose = showClose ?? !compact;
    final viewportSize = MediaQuery.sizeOf(context);
    final viewportHeight = viewportSize.height;
    final minWidth = compact ? viewportSize.width.clamp(0.0, maxWidth) : 0.0;
    final keyboardInset = MediaQuery.viewInsetsOf(
      context,
    ).bottom.clamp(0.0, viewportHeight);
    final availableHeight = viewportHeight - keyboardInset;
    return SafeArea(
      child: AnimatedPadding(
        duration: ParsMotion.quick,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minWidth,
            maxWidth: maxWidth,
            maxHeight: availableHeight,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              ParsSpacing.lg,
              ParsSpacing.xs,
              ParsSpacing.lg,
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (displayClose)
                      IconButton(
                        tooltip:
                            closeTooltip ??
                            MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: ParsSpacing.md),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
