import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

class ParsResponsiveBody extends StatelessWidget {
  const ParsResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = ParsContentWidth.page,
    this.padding = const EdgeInsets.all(ParsSpacing.md),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class ParsWindowClassBuilder extends StatelessWidget {
  const ParsWindowClassBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ParsWindowClass windowClass)
  builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder:
          (context, constraints) =>
              builder(context, ParsWindowClass.fromWidth(constraints.maxWidth)),
    );
  }
}

class ParsPageDivider extends StatelessWidget {
  const ParsPageDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(height: 1);
}
