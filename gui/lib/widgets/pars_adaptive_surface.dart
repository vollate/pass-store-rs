import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

Future<T?> showParsAdaptiveSurface<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  bool isDismissible = true,
  double maxWidth = ParsContentWidth.form,
}) {
  final compact = context.parsWindowClass == ParsWindowClass.compact;
  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      showDragHandle: true,
      builder:
          (surfaceContext) => ParsAdaptiveSurface(
            title: title,
            maxWidth: maxWidth,
            showClose: isDismissible,
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
            child: builder(surfaceContext),
          ),
        ),
  );
}

Future<T?> showParsAdaptiveDetail<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = ParsContentWidth.form,
}) {
  if (context.parsWindowClass == ParsWindowClass.compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
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

class ParsAdaptiveSurface extends StatelessWidget {
  const ParsAdaptiveSurface({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = ParsContentWidth.form,
    this.showClose = true,
  });

  final String title;
  final Widget child;
  final double maxWidth;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;
    return SafeArea(
      child: AnimatedPadding(
        duration: ParsMotion.quick,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (showClose)
                      IconButton(
                        tooltip:
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
