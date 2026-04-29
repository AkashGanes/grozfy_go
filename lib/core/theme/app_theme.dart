import 'package:flutter/material.dart';

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
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: nightBlue,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
        ),
        helperStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 11.5,
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFDC2626),
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
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: nightBlue,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: nightBlue,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF293847)),
      ),
    );
  }

  static ThemeData getDarkTheme({
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
  }) {
    final Color bgColor = scaffoldBackgroundColor ?? const Color(0xFF1A1A2E);
    final Color primary = primaryColor ?? oceanBlue;
    final Color surface = const Color(0xFF252540);

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
        surface: surface,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.6),
        ),
        helperStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 11.5,
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFFF6B6B),
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
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: Colors.white,
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
