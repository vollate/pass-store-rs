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
  static const double form = 640;
  static const double page = 720;
  static const double split = 1100;
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
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 28;
  static const double pill = 999;
}

abstract final class ParsSizes {
  static const double minimumTouchTarget = 48;
  static const double icon = 24;
  static const double compactAvatar = 40;
  static const double sheetHandleWidth = 42;
  static const double sheetHandleHeight = 4;
}

abstract final class ParsMotion {
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
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

  ParsWindowClass get parsWindowClass =>
      ParsWindowClass.fromWidth(MediaQuery.sizeOf(this).width);
}
