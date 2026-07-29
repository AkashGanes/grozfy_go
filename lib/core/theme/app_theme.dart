import 'package:flutter/material.dart';

class AppTheme {
  static const Color nightBlue = Color(0xFF0E1B2B);
  static const Color oceanBlue = Color(0xFF1C4E80);
  static const Color mint = Color(0xFF35C2B5);
  static const Color mango = Color(0xFFF6A623);
  static const Color card = Color(0xFFF4F7FB);

  // Light neutral tokens (match the palette already used across screens).
  static const Color lightOnSurface = Color(0xFF101828);
  static const Color lightOnSurfaceVariant = Color(0xFF667085);
  static const Color lightOutline = Color(0xFF98A2B3);
  static const Color lightOutlineVariant = Color(0xFFE4E7EC);
  static const Color lightSubtleFill = Color(0xFFEEF2F7);
  static const Color lightBody = Color(0xFF293847);
  static const Color lightError = Color(0xFFDC2626);

  // Dark neutral tokens — single source of truth for dark mode surfaces/text.
  static const Color darkScaffold = Color(0xFF12141C);
  static const Color darkSurface = Color(0xFF1B1E2A);
  static const Color darkSubtleFill = Color(0xFF252A38);
  static const Color darkOnSurface = Color(0xFFF2F4F7);
  static const Color darkOnSurfaceVariant = Color(0xFFB6BDCA);
  static const Color darkOutline = Color(0xFF4A5164);
  static const Color darkOutlineVariant = Color(0xFF2A2F3D);
  static const Color darkError = Color(0xFFFF8080);

  /// Lifts a (possibly dark) accent so buttons, icons and indicators stay
  /// vivid on dark surfaces. Light mode uses the accent untouched.
  static Color brightenForDark(Color color) {
    final HSLColor hsl = HSLColor.fromColor(color);
    if (hsl.lightness >= 0.58) return color;
    return hsl.withLightness(0.58).toColor();
  }

  static const List<Color> backgroundColorOptions = [
    Color(0xFFF0F4FA),
    Color(0xFFFFFFFF),
    Color(0xFFF5F0E8),
    Color(0xFFE8F5E9),
    Color(0xFFE3F2FD),
    Color(0xFFFCE4EC),
    Color(0xFFF3E5F5),
    Color(0xFFFFF3E0),
  ];

  static const List<Color> accentColorOptions = [
    Color(0xFF1C4E80),
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
  ];

  static ThemeData getLightTheme({
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
  }) {
    final Color bgColor = scaffoldBackgroundColor ?? const Color(0xFFF0F4FA);
    final Color primary = primaryColor ?? oceanBlue;

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgColor,
      fontFamily: 'Poppins',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: mint,
        tertiary: mango,
        surface: card,
      ).copyWith(
        onSurface: lightOnSurface,
        onSurfaceVariant: lightOnSurfaceVariant,
        outline: lightOutline,
        outlineVariant: lightOutlineVariant,
        surfaceContainerHighest: lightSubtleFill,
        error: lightError,
      ),
    );

    return base.copyWith(
      cardColor: Colors.white,
      dividerColor: lightOutlineVariant,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: nightBlue,
        centerTitle: true,
      ),
      iconTheme: const IconThemeData(color: lightOnSurface),
      dividerTheme: const DividerThemeData(
        color: lightOutlineVariant,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: lightOnSurfaceVariant,
        textColor: lightOnSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: lightError, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: lightError, width: 1.6),
        ),
        helperStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 11.5,
        ),
        errorStyle: const TextStyle(
          color: lightError,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
        errorMaxLines: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: lightOutline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: nightBlue,
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: nightBlue,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: lightOnSurface,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: lightOnSurface,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(fontSize: 16, color: lightBody),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: lightBody),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: lightOnSurfaceVariant,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: lightOnSurface,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: lightOnSurfaceVariant,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: lightOnSurfaceVariant,
        ),
      ),
    );
  }

  static ThemeData getDarkTheme({
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
  }) {
    final Color bgColor = scaffoldBackgroundColor ?? darkScaffold;
    final Color primary = brightenForDark(primaryColor ?? oceanBlue);

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgColor,
      fontFamily: 'Poppins',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        primary: primary,
        secondary: mint,
        tertiary: mango,
        surface: darkSurface,
      ).copyWith(
        onPrimary: Colors.white,
        onSurface: darkOnSurface,
        onSurfaceVariant: darkOnSurfaceVariant,
        outline: darkOutline,
        outlineVariant: darkOutlineVariant,
        surfaceContainerHighest: darkSubtleFill,
        error: darkError,
      ),
    );

    return base.copyWith(
      cardColor: darkSurface,
      dividerColor: darkOutlineVariant,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: darkOnSurface,
        centerTitle: true,
      ),
      iconTheme: const IconThemeData(color: darkOnSurface),
      dividerTheme: const DividerThemeData(
        color: darkOutlineVariant,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: darkOnSurfaceVariant,
        textColor: darkOnSurface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkError, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkError, width: 1.6),
        ),
        helperStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 11.5,
        ),
        errorStyle: const TextStyle(
          color: darkError,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
        errorMaxLines: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkOnSurface,
          side: const BorderSide(color: darkOutline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: darkOnSurface),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: darkOnSurface,
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: darkOnSurface,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(fontSize: 16, color: darkOnSurface),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: darkOnSurface),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: darkOnSurfaceVariant,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: darkOnSurfaceVariant,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: darkOnSurfaceVariant,
        ),
      ),
    );
  }

  static ThemeData getTheme({
    required ThemeMode mode,
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
  }) {
    switch (mode) {
      case ThemeMode.light:
        return getLightTheme(
          scaffoldBackgroundColor: scaffoldBackgroundColor,
          primaryColor: primaryColor,
        );
      case ThemeMode.dark:
        return getDarkTheme(
          scaffoldBackgroundColor: scaffoldBackgroundColor,
          primaryColor: primaryColor,
        );
      case ThemeMode.system:
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark
            ? getDarkTheme(
                scaffoldBackgroundColor: scaffoldBackgroundColor,
                primaryColor: primaryColor,
              )
            : getLightTheme(
                scaffoldBackgroundColor: scaffoldBackgroundColor,
                primaryColor: primaryColor,
              );
    }
  }
}
