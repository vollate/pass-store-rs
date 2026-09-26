import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

// Buttons sit in equal-width columns, two per row, and an odd last button
// takes the whole row. When any label would not fit on one line at half
// width, the whole group becomes one full-width button per row instead of
// wrapping labels inside narrow buttons. The check uses each button's
// single-line width, so it also covers large text scales and long
// translations.
class ParsButtonGrid extends MultiChildRenderObjectWidget {
  const ParsButtonGrid({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderButtonGrid(spacing: ParsSpacing.xs);
}

class _ButtonGridParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderButtonGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ButtonGridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ButtonGridParentData> {
  _RenderButtonGrid({required this.spacing});

  final double spacing;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ButtonGridParentData) {
      child.parentData = _ButtonGridParentData();
    }
  }

  List<RenderBox> get _children {
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    return children;
  }

  double _naturalWidth(RenderBox child) =>
      child.getMaxIntrinsicWidth(double.infinity);

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final children = _children;
    if (children.isEmpty) return constraints.smallest;
    final width =
        constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : children.map(_naturalWidth).reduce(math.max);
    final cell = (width - spacing) / 2;
    final twoColumns =
        children.length > 1 &&
        children.every((child) => _naturalWidth(child) <= cell);
    var y = 0.0;
    var index = 0;
    while (index < children.length) {
      final count = twoColumns && index + 1 < children.length ? 2 : 1;
      final childWidth = count == 2 ? cell : width;
      var rowHeight = 0.0;
      for (var offset = 0; offset < count; offset++) {
        final child = children[index + offset];
        final loose = BoxConstraints.tightFor(width: childWidth);
        final height =
            dry
                ? child.getDryLayout(loose).height
                : (child..layout(loose, parentUsesSize: true)).size.height;
        rowHeight = math.max(rowHeight, height);
      }
      if (!dry) {
        for (var offset = 0; offset < count; offset++) {
          final child = children[index + offset];
          child.layout(BoxConstraints.tight(Size(childWidth, rowHeight)));
          (child.parentData! as _ButtonGridParentData).offset = Offset(
            offset * (cell + spacing),
            y,
          );
        }
      }
      y += rowHeight;
      index += count;
      if (index < children.length) y += spacing;
    }
    return constraints.constrain(Size(width, y));
  }

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) => _children
      .map((child) => child.getMinIntrinsicWidth(height))
      .fold(0.0, math.max);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.map(_naturalWidth).fold(0.0, math.max);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _layout(BoxConstraints(maxWidth: width), dry: true).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

class ParsActionGroup extends StatelessWidget {
  const ParsActionGroup({super.key, required this.actions});

  final List<ParsActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return ParsButtonGrid(
      children: actions.map((action) => _buildAction(context, action)).toList(),
    );
  }

  Widget _buildAction(BuildContext context, ParsActionItem action) {
    final icon = Icon(action.icon);
    final label = Text(action.label, textAlign: TextAlign.center);
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
