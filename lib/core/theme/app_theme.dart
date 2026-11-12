import 'package:flutter/material.dart';

/// Ink-first palette: pure white and pure black canvases, with every tint
/// living at component level. No gradients, no glows, no tinted section bands.
/// One saturated accent (deep green, paired with a warm gold for social proof)
/// carries actions; red is reserved for destructive and failure states only.
class AppPalette {
  const AppPalette._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  static const Color inkLight = Color(0xFF0A0A0A);
  static const Color inkDark = Color(0xFFF2F2F2);

  static const Color mutedLight = Color(0xFF6B6B6B);
  static const Color mutedDark = Color(0xFF9A9A9A);

  static const Color surfaceLight = Color(0xFFF6F6F4);
  static const Color surfaceDark = Color(0xFF121212);

  static const Color hairlineLight = Color(0xFFE4E4E1);
  static const Color hairlineDark = Color(0xFF262626);

  static const Color accentLight = Color(0xFF1B5E3C);
  static const Color accentDark = Color(0xFF4FBE85);

  static const Color goldLight = Color(0xFF9A7317);
  static const Color goldDark = Color(0xFFD8B158);

  static const Color dangerLight = Color(0xFFB3261E);
  static const Color dangerDark = Color(0xFFEF6F64);
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Comfortable one-thumb reach target, held even on low-density screens.
  static const double touchTarget = 44;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppPalette.accentDark : AppPalette.accentLight,
      onPrimary: isDark ? AppPalette.black : AppPalette.white,
      primaryContainer: isDark ? AppPalette.surfaceDark : AppPalette.surfaceLight,
      onPrimaryContainer: isDark ? AppPalette.inkDark : AppPalette.inkLight,
      secondary: isDark ? AppPalette.goldDark : AppPalette.goldLight,
      onSecondary: isDark ? AppPalette.black : AppPalette.white,
      surface: isDark ? AppPalette.black : AppPalette.white,
      onSurface: isDark ? AppPalette.inkDark : AppPalette.inkLight,
      error: isDark ? AppPalette.dangerDark : AppPalette.dangerLight,
      onError: isDark ? AppPalette.black : AppPalette.white,
      outline: isDark ? AppPalette.hairlineDark : AppPalette.hairlineLight,
    );

    final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);

    // Tight, generous line height and no letter-spacing: the feed is read at
    // arm's length on a 5-inch screen, and Ge'ez glyphs need more vertical
    // room than Latin.
    final text = base.textTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          displaySmall: _display(scheme),
          headlineSmall: _headline(scheme),
          titleLarge: _title(scheme, 22, FontWeight.w600),
          titleMedium: _title(scheme, 17, FontWeight.w600),
          bodyLarge: _body(scheme, 16),
          bodyMedium: _body(scheme, 14.5),
          bodySmall: _body(scheme, 12.5).copyWith(color: isDark ? AppPalette.mutedDark : AppPalette.mutedLight),
          labelLarge: _label(scheme, 15),
          labelMedium: _label(scheme, 13),
          labelSmall: _label(scheme, 11.5),
        );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(size: 22, color: scheme.onSurface),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.touchTarget),
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary, textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppPalette.surfaceDark : AppPalette.surfaceLight,
        hintStyle: text.bodyMedium?.copyWith(color: isDark ? AppPalette.mutedDark : AppPalette.mutedLight),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
        border: _inputBorder(Colors.transparent),
        enabledBorder: _inputBorder(scheme.outline),
        focusedBorder: _inputBorder(scheme.primary, width: 1.6),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurface,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.onSurface,
        unselectedItemColor: isDark ? AppPalette.mutedDark : AppPalette.mutedLight,
        selectedLabelStyle: text.labelMedium,
        unselectedLabelStyle: text.labelMedium,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppPalette.surfaceDark : AppPalette.inkLight,
        contentTextStyle: text.bodyMedium?.copyWith(color: isDark ? AppPalette.inkDark : AppPalette.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: scheme.outline)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: isDark ? AppPalette.mutedDark : AppPalette.mutedLight,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelMedium,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
    );
  }

  static TextStyle _display(ColorScheme s) => TextStyle(
    fontSize: 32,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: s.onSurface,
    letterSpacing: -0.3,
  );

  static TextStyle _headline(ColorScheme s) => TextStyle(
    fontSize: 26,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: s.onSurface,
    letterSpacing: -0.2,
  );

  static TextStyle _title(ColorScheme s, double size, FontWeight weight) => TextStyle(
    fontSize: size,
    height: 1.4,
    fontWeight: weight,
    color: s.onSurface,
  );

  static TextStyle _body(ColorScheme s, double size) => TextStyle(
    fontSize: size,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: s.onSurface,
  );

  static TextStyle _label(ColorScheme s, double size) => TextStyle(
    fontSize: size,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: s.onSurface,
  );

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );
}
