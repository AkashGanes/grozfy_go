import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF006246);
  static const Color primaryContainer = Color(0xFF007D5A);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFBEFFDF);
  static const Color primaryFixed = Color(0xFF93F6CB);
  static const Color primaryFixedDim = Color(0xFF77D9B0);
  static const Color onPrimaryFixed = Color(0xFF002115);
  static const Color onPrimaryFixedVariant = Color(0xFF005139);

  static const Color secondary = Color(0xFF4C56AF);
  static const Color secondaryContainer = Color(0xFF959EFD);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF27308A);
  static const Color secondaryFixed = Color(0xFFE0E0FF);
  static const Color secondaryFixedDim = Color(0xFFBDC2FF);
  static const Color onSecondaryFixed = Color(0xFF000767);
  static const Color onSecondaryFixedVariant = Color(0xFF343D96);

  static const Color tertiary = Color(0xFF734E00);
  static const Color tertiaryContainer = Color(0xFF926500);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFFFFEFDA);
  static const Color tertiaryFixed = Color(0xFFFFDEAC);
  static const Color tertiaryFixedDim = Color(0xFFFFBA38);
  static const Color onTertiaryFixed = Color(0xFF281900);
  static const Color onTertiaryFixedVariant = Color(0xFF604100);

  static const Color surface = Color(0xFFF6FBF5);
  static const Color surfaceBright = Color(0xFFF6FBF5);
  static const Color surfaceDim = Color(0xFFD6DBD6);
  static const Color surfaceContainer = Color(0xFFEAEFEA);
  static const Color surfaceContainerLow = Color(0xFFF0F5F0);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerHigh = Color(0xFFE5E9E4);
  static const Color surfaceContainerHighest = Color(0xFFDFE4DF);
  static const Color onSurface = Color(0xFF181D1A);
  static const Color onSurfaceVariant = Color(0xFF3E4943);

  static const Color background = Color(0xFFF6FBF5);
  static const Color onBackground = Color(0xFF181D1A);

  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF93000A);

  static const Color outline = Color(0xFF6E7A73);
  static const Color outlineVariant = Color(0xFFBDC9C1);
  static const Color inverseSurface = Color(0xFF2C322E);
  static const Color inverseOnSurface = Color(0xFFEDF2ED);
  static const Color inversePrimary = Color(0xFF77D9B0);
  static const Color surfaceTint = Color(0xFF006C4D);
}

class AppTheme {
  static const Color nightBlue = Color(0xFF0E1B2B);
  static const Color oceanBlue = Color(0xFF1C4E80);
  static const Color mint = Color(0xFF35C2B5);
  static const Color mango = Color(0xFFF6A623);
  static const Color card = Color(0xFFF4F7FB);

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
    final Color bgColor = scaffoldBackgroundColor ?? AppColors.background;
    final Color primary = primaryColor ?? AppColors.primary;

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgColor,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        tertiaryContainer: AppColors.tertiaryContainer,
        onTertiaryContainer: AppColors.onTertiaryContainer,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        surfaceContainerHighest: AppColors.surfaceContainerHighest,
        surfaceContainerHigh: AppColors.surfaceContainerHigh,
        surfaceContainer: AppColors.surfaceContainer,
        surfaceContainerLow: AppColors.surfaceContainerLow,
        surfaceContainerLowest: AppColors.surfaceContainerLowest,
        inverseSurface: AppColors.inverseSurface,
        onInverseSurface: AppColors.inverseOnSurface,
        inversePrimary: AppColors.inversePrimary,
        surfaceTint: AppColors.surfaceTint,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Manrope',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          foregroundColor: AppColors.secondary,
          side: const BorderSide(color: AppColors.secondaryContainer),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Manrope',
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Manrope',
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.surfaceContainerLowest;
          }
          return AppColors.surfaceContainerHighest;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
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
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: AppColors.onSurface,
          fontFamily: 'Manrope',
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: AppColors.onSurface,
          fontFamily: 'Manrope',
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.onSurface,
          fontFamily: 'Manrope',
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
          fontFamily: 'Manrope',
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
          fontFamily: 'Manrope',
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
          fontFamily: 'Manrope',
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: AppColors.onSurface,
          fontFamily: 'Inter',
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.onSurface,
          fontFamily: 'Inter',
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
          fontFamily: 'Inter',
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
          fontFamily: 'Inter',
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurfaceVariant,
          fontFamily: 'Inter',
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.outline,
          letterSpacing: 0.5,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  static ThemeData getDarkTheme({
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
  }) {
    final Color bgColor = scaffoldBackgroundColor ?? const Color(0xFF1A1A2E);
    final Color primary = primaryColor ?? AppColors.primary;
    final Color surface = const Color(0xFF252540);

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgColor,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        tertiaryContainer: AppColors.tertiaryContainer,
        onTertiaryContainer: AppColors.onTertiaryContainer,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surface: surface,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.grey[400]!,
        outline: Colors.grey[600],
        outlineVariant: Colors.grey[800],
        surfaceContainerHighest: const Color(0xFF2A2A3E),
        surfaceContainerHigh: const Color(0xFF252538),
        surfaceContainer: const Color(0xFF202030),
        surfaceContainerLow: const Color(0xFF1A1A28),
        surfaceContainerLowest: const Color(0xFF151520),
        inverseSurface: Colors.white,
        onInverseSurface: AppColors.inverseSurface,
        inversePrimary: AppColors.inversePrimary,
        surfaceTint: AppColors.surfaceTint,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Manrope',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
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
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: Colors.white,
          fontFamily: 'Manrope',
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFamily: 'Manrope',
        ),
        bodyLarge: TextStyle(fontSize: 16, color: Colors.grey[300]),
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
        return getLightTheme(
          scaffoldBackgroundColor: scaffoldBackgroundColor,
          primaryColor: primaryColor,
        );
    }
  }
}
