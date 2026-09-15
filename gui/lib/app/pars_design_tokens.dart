import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

enum ParsWindowClass {
  compact,
  medium,
  expanded;

  static ParsWindowClass fromWidth(double width) {
    if (width < ParsBreakpoints.medium) return ParsWindowClass.compact;
    if (width < ParsBreakpoints.expanded) return ParsWindowClass.medium;
    return ParsWindowClass.expanded;
  }
}

abstract final class ParsBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
}

abstract final class ParsContentWidth {
  static const double narrow = 420;
  static const double notification = 560;
  static const double form = 640;
  static const double page = 720;
  static const double split = 1100;
}

// Composite paddings that recur across sheets and pages. Keeping the whole
// inset here, rather than assembling it per call site, is what stops two
// surfaces from ending up a few pixels apart.
abstract final class ParsInsets {
  static const EdgeInsets page = EdgeInsets.all(ParsSpacing.lg);
  static const EdgeInsets sheetBlock = EdgeInsets.fromLTRB(
    ParsSpacing.lg,
    ParsSpacing.sm,
    ParsSpacing.lg,
    ParsSpacing.lg,
  );
  static const EdgeInsets sheetBlockTall = EdgeInsets.fromLTRB(
    ParsSpacing.lg,
    ParsSpacing.sm,
    ParsSpacing.lg,
    ParsSpacing.xl,
  );
}

abstract final class ParsSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class ParsRadii {
  static const double small = 8;
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 28;
  static const double pill = 999;
}

abstract final class ParsSizes {
  static const double hairline = 1;
  static const double focusRing = 2;
  static const double minimumTouchTarget = 48;
  static const double navigationBar = 72;
  static const double icon = 24;
  static const double iconSmall = 20;
  static const double iconTiny = 16;
  static const double compactAvatar = 40;
  static const double sheetHandleWidth = 42;
  static const double sheetHandleHeight = 4;
  static const double tallToolbar = 64;
  static const double statusBadge = 152;
  static const double qrCode = 200;
  // The gesture grid stays square and thumb-sized rather than stretching to
  // the window, so it is bounded on both axes.
  static const double gestureGrid = 320;
  static const double gestureGridMin = 160;
  static const double gestureGridViewportFactor = 0.52;
  // Keeps the last row of a scrolling page clear of the floating action
  // button once the page is scrolled to the end.
  static const double floatingActionClearance = 96;
}

// Modal sheets track the viewport instead of a fixed height, but stay within
// a readable band so a short entry does not open a full-screen sheet and a
// long one does not run past the window.
abstract final class ParsSheetMetrics {
  static const double preferredHeightFactor = 0.78;
  static const double minHeight = 240;
  static const double maxHeight = 720;
}

abstract final class ParsElevation {
  static const double flat = 0;
  static const double scrolledUnder = 1;
  static const double raised = 3;
  // Transient overlays that must read as floating above a modal surface.
  static const double overlay = 10;
}

abstract final class ParsMotion {
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  // Routine confirmations pass on their own; failures stay long enough to
  // reach their recovery action.
  static const Duration transientFeedback = Duration(seconds: 3);
  static const Duration recoverableFeedback = Duration(seconds: 8);
}

// Machine data such as store paths and fingerprints renders in a monospace
// face. No font asset is bundled, so this resolves through platform families:
// 'monospace' on Android, Menlo on Apple platforms, Consolas on Windows and
// DejaVu Sans Mono on Linux.
abstract final class ParsFonts {
  static const String mono = 'monospace';
  static const List<String> monoFallback = <String>[
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'DejaVu Sans Mono',
    'Courier New',
  ];
}

// Vault and Settings both present the same thing: a titled group of rows in
// one bordered container. The geometry is owned here, and read through the
// theme, so the two pages cannot drift apart on outline, row height or
// spacing the way separately hard-coded values did.
@immutable
class ParsSectionStyle extends ThemeExtension<ParsSectionStyle> {
  const ParsSectionStyle({
    required this.horizontalPadding,
    required this.spacing,
    required this.headerIndent,
    required this.headerSpacing,
    required this.radius,
    required this.borderWidth,
    required this.rowMinHeight,
    required this.rowPadding,
    required this.rowSpacing,
    required this.rowTrailingSpacing,
    required this.rowTitleSpacing,
  });

  static const standard = ParsSectionStyle(
    horizontalPadding: ParsSpacing.md,
    spacing: ParsSpacing.lg,
    headerIndent: ParsSpacing.xxs,
    headerSpacing: ParsSpacing.xs,
    radius: ParsRadii.card,
    borderWidth: ParsSizes.hairline,
    rowMinHeight: ParsSizes.minimumTouchTarget + ParsSpacing.xs,
    rowPadding: EdgeInsets.fromLTRB(
      ParsSpacing.sm,
      ParsSpacing.xs,
      ParsSpacing.xs,
      ParsSpacing.xs,
    ),
    rowSpacing: ParsSpacing.sm,
    rowTrailingSpacing: ParsSpacing.xs,
    rowTitleSpacing: ParsSpacing.xxs,
  );

  // Page gutter shared by every section on a page.
  final double horizontalPadding;
  // Gap above a section, which doubles as the gap between two sections.
  final double spacing;
  final double headerIndent;
  final double headerSpacing;
  final double radius;
  final double borderWidth;
  final double rowMinHeight;
  final EdgeInsets rowPadding;
  // Between the leading slot and the label column.
  final double rowSpacing;
  // Between the label column and the trailing control.
  final double rowTrailingSpacing;
  // Between a row title and its supporting line.
  final double rowTitleSpacing;

  EdgeInsets get padding =>
      EdgeInsets.fromLTRB(horizontalPadding, spacing, horizontalPadding, 0);

  EdgeInsets get headerPadding =>
      EdgeInsets.only(left: headerIndent, bottom: headerSpacing);

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  // Separators start at the row label rather than under the leading slot.
  double get dividerIndent =>
      rowPadding.left + ParsSizes.compactAvatar + rowSpacing;

  @override
  ParsSectionStyle copyWith({
    double? horizontalPadding,
    double? spacing,
    double? headerIndent,
    double? headerSpacing,
    double? radius,
    double? borderWidth,
    double? rowMinHeight,
    EdgeInsets? rowPadding,
    double? rowSpacing,
    double? rowTrailingSpacing,
    double? rowTitleSpacing,
  }) {
    return ParsSectionStyle(
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      spacing: spacing ?? this.spacing,
      headerIndent: headerIndent ?? this.headerIndent,
      headerSpacing: headerSpacing ?? this.headerSpacing,
      radius: radius ?? this.radius,
      borderWidth: borderWidth ?? this.borderWidth,
      rowMinHeight: rowMinHeight ?? this.rowMinHeight,
      rowPadding: rowPadding ?? this.rowPadding,
      rowSpacing: rowSpacing ?? this.rowSpacing,
      rowTrailingSpacing: rowTrailingSpacing ?? this.rowTrailingSpacing,
      rowTitleSpacing: rowTitleSpacing ?? this.rowTitleSpacing,
    );
  }

  @override
  ParsSectionStyle lerp(covariant ParsSectionStyle? other, double t) {
    if (other == null) return this;
    return ParsSectionStyle(
      horizontalPadding:
          lerpDouble(horizontalPadding, other.horizontalPadding, t)!,
      spacing: lerpDouble(spacing, other.spacing, t)!,
      headerIndent: lerpDouble(headerIndent, other.headerIndent, t)!,
      headerSpacing: lerpDouble(headerSpacing, other.headerSpacing, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t)!,
      rowMinHeight: lerpDouble(rowMinHeight, other.rowMinHeight, t)!,
      rowPadding: EdgeInsets.lerp(rowPadding, other.rowPadding, t)!,
      rowSpacing: lerpDouble(rowSpacing, other.rowSpacing, t)!,
      rowTrailingSpacing:
          lerpDouble(rowTrailingSpacing, other.rowTrailingSpacing, t)!,
      rowTitleSpacing: lerpDouble(rowTitleSpacing, other.rowTitleSpacing, t)!,
    );
  }
}

// Identity accents for entry rows. A single shared accent makes a long list
// read as undifferentiated noise, so each entry derives a stable slot from its
// own name. Every pair is checked to clear 4.5:1 against its own fill.
@immutable
class ParsEntryPalette extends ThemeExtension<ParsEntryPalette> {
  const ParsEntryPalette({required this.fills, required this.foregrounds});

  final List<Color> fills;
  final List<Color> foregrounds;

  static const light = ParsEntryPalette(
    fills: <Color>[
      Color(0xFFE6F1FB),
      Color(0xFFE1F5EE),
      Color(0xFFEEEDFE),
      Color(0xFFFAEEDA),
      Color(0xFFFBEAF0),
      Color(0xFFEAF3DE),
    ],
    foregrounds: <Color>[
      Color(0xFF0C447C),
      Color(0xFF085041),
      Color(0xFF3C3489),
      Color(0xFF633806),
      Color(0xFF72243E),
      Color(0xFF27500A),
    ],
  );

  static const dark = ParsEntryPalette(
    fills: <Color>[
      Color(0xFF0C447C),
      Color(0xFF085041),
      Color(0xFF3C3489),
      Color(0xFF633806),
      Color(0xFF72243E),
      Color(0xFF27500A),
    ],
    foregrounds: <Color>[
      Color(0xFFB5D4F4),
      Color(0xFF9FE1CB),
      Color(0xFFCECBF6),
      Color(0xFFFAC775),
      Color(0xFFF4C0D1),
      Color(0xFFC0DD97),
    ],
  );

  int slotFor(String seed) {
    if (fills.isEmpty) return 0;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return hash % fills.length;
  }

  Color fillFor(String seed) => fills[slotFor(seed)];

  Color foregroundFor(String seed) => foregrounds[slotFor(seed)];

  @override
  ParsEntryPalette copyWith({List<Color>? fills, List<Color>? foregrounds}) {
    return ParsEntryPalette(
      fills: fills ?? this.fills,
      foregrounds: foregrounds ?? this.foregrounds,
    );
  }

  @override
  ParsEntryPalette lerp(covariant ParsEntryPalette? other, double t) {
    if (other == null) return this;
    return ParsEntryPalette(
      fills: _lerpColors(fills, other.fills, t),
      foregrounds: _lerpColors(foregrounds, other.foregrounds, t),
    );
  }

  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return <Color>[
      for (var index = 0; index < a.length; index++)
        Color.lerp(a[index], b[index], t)!,
    ];
  }
}

@immutable
class ParsSemanticColors extends ThemeExtension<ParsSemanticColors> {
  const ParsSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.busy,
    required this.unavailable,
  });

  final Color success;
  final Color warning;
  final Color info;
  final Color busy;
  final Color unavailable;

  static const light = ParsSemanticColors(
    success: Color(0xFF166534),
    warning: Color(0xFF92400E),
    info: Color(0xFF075985),
    busy: Color(0xFF6D28D9),
    unavailable: Color(0xFF475569),
  );

  static const dark = ParsSemanticColors(
    success: Color(0xFF86EFAC),
    warning: Color(0xFFFDE68A),
    info: Color(0xFF7DD3FC),
    busy: Color(0xFFC4B5FD),
    unavailable: Color(0xFF94A3B8),
  );

  @override
  ParsSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? busy,
    Color? unavailable,
  }) {
    return ParsSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      busy: busy ?? this.busy,
      unavailable: unavailable ?? this.unavailable,
    );
  }

  @override
  ParsSemanticColors lerp(covariant ParsSemanticColors? other, double t) {
    if (other == null) return this;
    return ParsSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      busy: Color.lerp(busy, other.busy, t)!,
      unavailable: Color.lerp(unavailable, other.unavailable, t)!,
    );
  }
}

extension ParsThemeAccess on BuildContext {
  ParsSemanticColors get parsColors =>
      Theme.of(this).extension<ParsSemanticColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? ParsSemanticColors.dark
          : ParsSemanticColors.light);

  ParsEntryPalette get parsEntryPalette =>
      Theme.of(this).extension<ParsEntryPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? ParsEntryPalette.dark
          : ParsEntryPalette.light);

  ParsSectionStyle get parsSection =>
      Theme.of(this).extension<ParsSectionStyle>() ?? ParsSectionStyle.standard;

  ParsWindowClass get parsWindowClass =>
      ParsWindowClass.fromWidth(MediaQuery.sizeOf(this).width);
}
