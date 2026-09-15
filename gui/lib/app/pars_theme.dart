import 'package:flutter/material.dart';

import 'pars_design_tokens.dart';

class ParsTheme {
  static const Color primary = Color(0xFF0F766E);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color darkSurface = Color(0xFF111827);

  // ColorScheme.fromSeed runs the Material tonal-palette algorithm and the
  // surrounding ThemeData carries every component sub-theme, so building both
  // brightnesses costs more than a frame budget on a phone. The result is
  // immutable and input-free, so it is built once and shared. Theme edits need
  // a restart rather than a hot reload to take effect.
  static ThemeData? _light;
  static ThemeData? _dark;

  static ThemeData light() => _light ??= _build(Brightness.light);

  static ThemeData dark() => _dark ??= _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: isDark ? darkSurface : surface,
    );
    final semanticColors =
        isDark ? ParsSemanticColors.dark : ParsSemanticColors.light;
    final entryPalette =
        isDark ? ParsEntryPalette.dark : ParsEntryPalette.light;
    const section = ParsSectionStyle.standard;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ParsRadii.control),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: <ThemeExtension<dynamic>>[
        semanticColors,
        entryPalette,
        section,
      ],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: ParsElevation.flat,
        scrolledUnderElevation: ParsElevation.scrolledUnder,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      // Cards use the same fill, radius and outline as a grouped section, so a
      // standalone card and a section container read as one component family.
      cardTheme: CardThemeData(
        elevation: ParsElevation.flat,
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: section.borderRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: section.borderWidth,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: ParsSizes.navigationBar,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color:
                selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color:
                selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
        ),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ParsSpacing.md,
          vertical: ParsSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ParsRadii.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ParsRadii.control),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ParsRadii.control),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: ParsSizes.focusRing,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ParsRadii.control),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ParsRadii.control),
          borderSide: BorderSide(
            color: colorScheme.error,
            width: ParsSizes.focusRing,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, ParsSizes.minimumTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: ParsSpacing.md,
            vertical: ParsSpacing.sm,
          ),
          shape: controlShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, ParsSizes.minimumTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: ParsSpacing.md,
            vertical: ParsSpacing.sm,
          ),
          shape: controlShape,
          side: BorderSide(color: colorScheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, ParsSizes.minimumTouchTarget),
          shape: controlShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(ParsSizes.minimumTouchTarget),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.secondaryContainer,
        disabledColor: colorScheme.surfaceContainerLow,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ParsRadii.pill),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        secondaryLabelStyle: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minLeadingWidth: ParsSizes.compactAvatar,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ParsSpacing.md,
          vertical: ParsSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ParsRadii.control),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: ParsElevation.raised,
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ParsRadii.sheet),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: ParsElevation.raised,
        modalElevation: ParsElevation.raised,
        backgroundColor: colorScheme.surfaceContainerLow,
        modalBackgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ParsRadii.sheet),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: ParsSizes.hairline,
        space: ParsSizes.hairline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: controlShape,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(ParsRadii.control),
        ),
        textStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
    );

    return base.copyWith(textTheme: _typography(base.textTheme));
  }

  // The stock Material scale leaves entry names and their paths at the same
  // weight, which flattens the list. Titles carry the weight, supporting text
  // stays regular and leans on colour instead.
  static TextTheme _typography(TextTheme base) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.25,
      ),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: base.bodySmall?.copyWith(height: 1.3),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  // Paths, fingerprints and other machine data are easier to scan and compare
  // in a monospace face.
  static TextStyle mono(TextStyle base) {
    return base.copyWith(
      fontFamily: ParsFonts.mono,
      fontFamilyFallback: ParsFonts.monoFallback,
      letterSpacing: 0,
    );
  }
}
